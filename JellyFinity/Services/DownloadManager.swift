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
    private(set) var progress: [String: Double] = [:]
    var errorMessage: String?

    @ObservationIgnored private var pending: [String: Pending] = [:]
    @ObservationIgnored private var tasks: [String: URLSessionDownloadTask] = [:]
    @ObservationIgnored private let delegate = DownloadSessionDelegate()
    @ObservationIgnored private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        delegate.handler = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        records = Self.loadRecords()
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
        for item in items where item.downloadLibrary != nil && state(for: item.id) == .none {
            let task = session.downloadTask(with: client.downloadRequest(itemId: item.id))
            task.taskDescription = item.id
            pending[item.id] = Pending(item: item, group: group)
            tasks[item.id] = task
            progress[item.id] = 0
            task.resume()
        }
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        pending[id] = nil
        progress[id] = nil
    }

    func remove(_ ids: [String]) {
        for id in ids {
            guard let record = record(for: id) else { continue }
            try? FileManager.default.removeItem(at: record.fileURL)
            if let artwork = record.artworkURL { try? FileManager.default.removeItem(at: artwork) }
        }
        records.removeAll { ids.contains($0.id) }
        save()
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
        save()
        if let url = item.primaryImageURL {
            Task { await saveArtwork(from: url, for: id) }
        }
    }

    private func saveArtwork(from url: URL, for id: String) async {
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { return }
        let name = "\(DownloadStorage.safeName(id)).jpg"
        let destination = DownloadStorage.directory.appendingPathComponent(name)
        guard (try? data.write(to: destination, options: .atomic)) != nil,
              let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].artworkFileName = name
        save()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: DownloadStorage.indexURL, options: .atomic)
    }

    private static func loadRecords() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: DownloadStorage.indexURL),
              let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return [] }
        return decoded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }
}
