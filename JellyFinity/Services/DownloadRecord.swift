import Foundation

/// Where downloaded media lives on this device (excluded from iCloud backups, since it can be re-downloaded).
enum DownloadStorage {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Downloads", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        }
        return url
    }

    static var indexURL: URL { directory.appendingPathComponent("index.json") }

    static func safeName(_ id: String) -> String {
        String(id.filter { $0.isLetter || $0.isNumber || $0 == "-" })
    }
}

/// An artist's pictures saved on this device for offline album pages.
struct OfflineArtist: Codable, Hashable, Sendable {
    var name: String
    var imageFileName: String?
    var backdropFileName: String?
}

/// A finished download, persisted so it survives relaunches and plays offline.
struct DownloadRecord: Codable, Identifiable, Hashable, Sendable {
    let id: String
    var name: String
    var subtitle: String?
    var kindRaw: String
    var libraryRaw: String
    var year: Int?
    var runtimeMinutes: Int?
    var overview: String?
    var durationSeconds: Double?
    var indexNumber: Int?
    var parentIndexNumber: Int?
    var groupId: String?
    var groupName: String?
    var fileName: String
    var artworkFileName: String?
    var bytes: Int64
    var resumeSeconds: Double?
    var addedAt: Date
    /// Full server details (genres, cast, ratings…) saved at download time so the page works offline.
    var metadata: MediaItem?
    /// The album or show this item belongs to, saved the same way.
    var groupItem: MediaItem?
    var groupArtworkFileName: String?
    var backdropFileName: String?
    var logoFileName: String?

    var library: LibraryKind { LibraryKind(rawValue: libraryRaw) ?? .movies }
    var fileURL: URL { DownloadStorage.directory.appendingPathComponent(fileName) }
    var artworkURL: URL? { artworkFileName.map { DownloadStorage.directory.appendingPathComponent($0) } }
    var groupArtworkURL: URL? { groupArtworkFileName.map { DownloadStorage.directory.appendingPathComponent($0) } }

    /// Every file in the downloads folder this record owns (media plus pictures).
    var allFileNames: [String] {
        [fileName, artworkFileName, groupArtworkFileName, backdropFileName, logoFileName].compactMap { $0 }
    }

    /// A playable item that points at the local file.
    var mediaItem: MediaItem {
        var item = metadata ?? basicItem
        if let resumeSeconds, let durationSeconds, durationSeconds > 0 {
            item.progress = resumeSeconds / durationSeconds
        } else {
            item.progress = nil
        }
        item.resumeSeconds = resumeSeconds
        item.localFileURL = fileURL
        if let artworkURL { item.primaryImageURL = artworkURL }
        if let backdropFileName { item.backdropImageURL = DownloadStorage.directory.appendingPathComponent(backdropFileName) }
        if let logoFileName { item.logoImageURL = DownloadStorage.directory.appendingPathComponent(logoFileName) }
        if item.durationSeconds == nil { item.durationSeconds = durationSeconds }
        return item
    }

    private var basicItem: MediaItem {
        MediaItem(
            id: id, name: name, subtitle: subtitle, kind: MediaItem.Kind(rawValue: kindRaw) ?? .movie,
            year: year, runtimeMinutes: runtimeMinutes, overview: overview,
            primaryImageURL: artworkURL, seriesId: groupId, indexNumber: indexNumber,
            parentIndexNumber: parentIndexNumber, durationSeconds: durationSeconds
        )
    }

    var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

extension MediaItem {
    /// The library a downloaded copy of this item belongs to; nil for items that can't be downloaded.
    var downloadLibrary: LibraryKind? {
        switch kind {
        case .movie: .movies
        case .episode: .shows
        case .track: .albums
        case .audiobook: .audiobooks
        default: nil
        }
    }
}
