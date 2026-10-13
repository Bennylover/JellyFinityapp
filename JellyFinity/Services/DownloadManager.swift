import Foundation
import Observation

/// Downloads media from the Jellyfin server and keeps the offline library.
@MainActor
@Observable
final class DownloadManager {
    enum State: Equatable {
        case none
        case downloading(Double)
        case done
    }

    private struct Pending {
        let item: MediaItem
        let group: MediaItem?
    }

    private(set) var records: [DownloadRecord] = []
    private(set) var artists: [String: OfflineArtist] = [:]
    private(set) var progress: [String: Double] = [:]
    private(set) var converting: Set<String> = []
    var errorMessage: String?

    @ObservationIgnored private var pending: [String: Pending] = [:]
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private let delegate = DownloadSessionDelegate()
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private weak var store: SessionStore?
    @ObservationIgnored private var didBackfill = false

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.handler = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        records = Self.loadRecords()
        artists = Self.loadArtists()
    }

    // MARK: - Queries

    func state(for id: String) -> State {
        if let value = progress[id] { return .downloading(value) }
        return records.contains { $0.id == id } ? .done : .none
    }

    func record(for id: String) -> DownloadRecord? { records.first { $0.id == id } }

    func records(for library: LibraryKind) -> [DownloadRecord] {
        records.filter { $0.library == library }
    }

    func activeItems(for library: LibraryKind) -> [(item: MediaItem, fraction: Double)] {
        pending.compactMap { id, entry in
            guard entry.item.downloadLibrary == library, let fraction = progress[id] else { return nil }
            return (entry.item, fraction)
        }
        .sorted { $0.item.name < $1.item.name }
    }

    func totalBytes(for library: LibraryKind) -> Int64 {
        records(for: library).reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Actions

    /// Starts downloading each item that isn't already saved or in progress.
    func download(_ items: [MediaItem], group: MediaItem? = nil, store: SessionStore) {
        guard !store.isDemo, let client = store.client else {
            errorMessage = "Connect to your own Jellyfin server to download media."
            return
        }
        let convert = UserDefaults.standard.object(forKey: Self.convertKey) as? Bool ?? true
        self.store = store
        let userId = store.session?.userId ?? ""
        for item in items where item.downloadLibrary != nil && state(for: item.id) == .none {
            pending[item.id] = Pending(item: item, group: group)
            progress[item.id] = 0
            Task { [weak self] in
                let plan = await client.downloadPlan(userId: userId, item: item, convertIfNeeded: convert)
                self?.start(plan, for: item)
            }
        }
    }

    /// Whether downloads are converted by the server when the original wouldn't play on iPhone.
    static let convertKey = "jl.convertDownloads"

    private func start(_ plan: DownloadPlan, for item: MediaItem) {
        guard pending[item.id] != nil, tasks[item.id] == nil else { return }
        let task = session.downloadTask(with: plan.request)
        task.taskDescription = item.id
        if let expected = plan.expectedBytes { task.countOfBytesClientExpectsToReceive = expected }
        if plan.isConverted { converting.insert(item.id) }
        tasks[item.id] = task
        task.resume()
    }

    /// Items the server is converting while they download.
    func isConverting(_ id: String) -> Bool { converting.contains(id) }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        pending[id] = nil
        progress[id] = nil
        converting.remove(id)
    }

    func remove(_ ids: [String]) {
        let removed = records.filter { ids.contains($0.id) }
        records.removeAll { ids.contains($0.id) }
        let inUse = Set(records.flatMap(\.allFileNames))
        for name in removed.flatMap(\.allFileNames) where !inUse.contains(name) {
            try? FileManager.default.removeItem(at: DownloadStorage.directory.appendingPathComponent(name))
        }
        pruneArtists()
        save()
    }

    /// Drops saved artist pictures once no downloaded album by that artist is left.
    private func pruneArtists() {
        let wanted = Set(records.filter { $0.library == .albums }.compactMap { $0.groupItem?.subtitle?.lowercased() })
        let inUse = Set(records.flatMap(\.allFileNames))
        for (key, artist) in artists where !wanted.contains(key) {
            for name in [artist.imageFileName, artist.backdropFileName].compactMap({ $0 }) where !inUse.contains(name) {
                try? FileManager.default.removeItem(at: DownloadStorage.directory.appendingPathComponent(name))
            }
            artists[key] = nil
        }
        saveArtists()
    }

    func saveResume(id: String, seconds: Double) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let duration = records[index].durationSeconds ?? 0
        let finished = duration > 0 && seconds > duration * 0.95
        records[index].resumeSeconds = (seconds > 5 && !finished) ? seconds : nil
        save()
    }

    // MARK: - Events

    private func handle(_ event: DownloadEvent) {
        switch event {
        case .progress(let id, let fraction):
            if progress[id] != nil { progress[id] = fraction }
        case .finished(let id, let fileName, let bytes):
            finish(id: id, fileName: fileName, bytes: bytes)
        case .failed(let id, let message):
            guard progress[id] != nil else { return }
            tasks[id] = nil
            pending[id] = nil
            progress[id] = nil
            converting.remove(id)
            errorMessage = message
        }
    }

    private func finish(id: String, fileName: String, bytes: Int64) {
        guard let entry = pending[id] else { return }
        let item = entry.item
        let group = entry.group
        let record = DownloadRecord(
            id: id, name: item.name, subtitle: item.subtitle, kindRaw: item.kind.rawValue,
            libraryRaw: item.downloadLibrary?.rawValue ?? LibraryKind.movies.rawValue,
            year: item.year, runtimeMinutes: item.runtimeMinutes, overview: item.overview,
            durationSeconds: item.durationSeconds, indexNumber: item.indexNumber,
            parentIndexNumber: item.parentIndexNumber,
            groupId: group?.id ?? item.seriesId,
            groupName: group?.name ?? (item.kind == .episode ? item.subtitle : nil),
            fileName: fileName, artworkFileName: nil, bytes: bytes,
            resumeSeconds: item.resumeSeconds, addedAt: .now
        )
        records.removeAll { $0.id == id }
        records.insert(record, at: 0)
        tasks[id] = nil
        pending[id] = nil
        progress[id] = nil
        converting.remove(id)
        save()
        Task { await saveOfflineMetadata(item: item, group: group) }
    }

    /// Saves full details and pictures next to the file so the page looks complete offline.
    private func saveOfflineMetadata(item: MediaItem, group: MediaItem?) async {
        let id = item.id
        var full = item
        if let client = store?.client, let userId = store?.session?.userId,
           let detail = try? await client.detail(userId: userId, itemId: id) {
            full = detail
        }
        let artwork = await saveImage(item.primaryImageURL ?? full.primaryImageURL, name: "\(DownloadStorage.safeName(id)).jpg")
        let backdrop = await saveImage(full.backdropImageURL, name: "\(DownloadStorage.safeName(id))-backdrop.jpg")
        let logo = await saveImage(full.logoImageURL, name: "\(DownloadStorage.safeName(id))-logo.jpg")
        var groupArtwork: String?
        if let group {
            groupArtwork = await saveImage(group.primaryImageURL, name: "\(DownloadStorage.safeName(group.id))-group.jpg")
        }
        if let index = records.firstIndex(where: { $0.id == id }) {
            records[index].metadata = full
            records[index].groupItem = group
            records[index].artworkFileName = artwork
            records[index].backdropFileName = backdrop
            records[index].logoFileName = logo
            records[index].groupArtworkFileName = groupArtwork
            save()
        }
        if item.downloadLibrary == .albums, let artistName = group?.subtitle ?? item.subtitle {
            await saveArtist(named: artistName)
        }
    }

    private func saveArtist(named name: String) async {
        let key = name.lowercased()
        guard artists[key] == nil, let hit = await store?.fetchArtistDetails(name: name) else { return }
        let base = DownloadStorage.safeName("artist-\(key)")
        let image = await saveImage(hit.imageURL, name: "\(base).jpg")
        let backdrop = await saveImage(hit.backdropURL, name: "\(base)-backdrop.jpg")
        artists[key] = OfflineArtist(name: hit.name, imageFileName: image, backdropFileName: backdrop)
        saveArtists()
    }

    /// Downloads a picture into the downloads folder; returns its file name, or nil on failure.
    private func saveImage(_ url: URL?, name: String) async -> String? {
        guard let url, !url.isFileURL else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return nil }
        let destination = DownloadStorage.directory.appendingPathComponent(name)
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return nil }
        return name
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: DownloadStorage.indexURL, options: .atomic)
    }

    private static var artistsURL: URL { DownloadStorage.directory.appendingPathComponent("artists.json") }

    private func saveArtists() {
        guard let data = try? JSONEncoder().encode(artists) else { return }
        try? data.write(to: Self.artistsURL, options: .atomic)
    }

    private static func loadArtists() -> [String: OfflineArtist] {
        guard let data = try? Data(contentsOf: artistsURL),
              let decoded = try? JSONDecoder().decode([String: OfflineArtist].self, from: data) else { return [:] }
        return decoded
    }

    private static func loadRecords() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: DownloadStorage.indexURL),
              let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return [] }
        return decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }
}
