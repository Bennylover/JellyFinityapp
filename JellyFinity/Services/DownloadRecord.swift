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

    var library: LibraryKind { LibraryKind(rawValue: libraryRaw) ?? .movies }
    var fileURL: URL { DownloadStorage.directory.appendingPathComponent(fileName) }
    var artworkURL: URL? { artworkFileName.map { DownloadStorage.directory.appendingPathComponent($0) } }

    /// A playable item that points at the local file.
    var mediaItem: MediaItem {
        let kind = MediaItem.Kind(rawValue: kindRaw) ?? .movie
        var progress: Double?
        if let resumeSeconds, let durationSeconds, durationSeconds > 0 { progress = resumeSeconds / durationSeconds }
        return MediaItem(
            id: id, name: name, subtitle: subtitle, kind: kind, year: year, runtimeMinutes: runtimeMinutes,
            overview: overview, progress: progress, primaryImageURL: artworkURL, seriesId: groupId,
            indexNumber: indexNumber, parentIndexNumber: parentIndexNumber, durationSeconds: durationSeconds,
            resumeSeconds: resumeSeconds, localFileURL: fileURL
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
