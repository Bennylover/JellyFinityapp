import Foundation

struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case movie, episode, series, album, audiobook, other
    }

    let id: String
    let name: String
    var subtitle: String? = nil
    var kind: Kind = .movie
    var year: Int? = nil
    var runtimeMinutes: Int? = nil
    var communityRating: Double? = nil
    var officialRating: String? = nil
    var genres: [String] = []
    var overview: String? = nil
    var progress: Double? = nil
    var primaryImageURL: URL? = nil
    var backdropImageURL: URL? = nil

    var artworkSeed: Int {
        id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }

    var symbol: String {
        switch kind {
        case .movie: "film"
        case .episode, .series: "tv"
        case .album: "music.note"
        case .audiobook: "book.closed"
        case .other: "sparkles"
        }
    }

    var metaLine: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        if let runtimeMinutes { parts.append(Self.formatRuntime(runtimeMinutes)) }
        if let officialRating { parts.append(officialRating) }
        return parts.joined(separator: " · ")
    }

    var remainingText: String? {
        guard let progress, let runtimeMinutes else { return nil }
        let left = Int(Double(runtimeMinutes) * (1 - progress))
        return "\(max(left, 1)) min left"
    }

    static func formatRuntime(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}

struct LibraryCounts: Sendable, Equatable {
    var movies = 0
    var series = 0
    var albums = 0
    var audiobooks = 0

    var total: Int { movies + series + albums + audiobooks }
}

struct LibrarySnapshot: Sendable {
    var featured: MediaItem?
    var continueWatching: [MediaItem] = []
    var recentMovies: [MediaItem] = []
    var recentAlbums: [MediaItem] = []
    var counts = LibraryCounts()

    var isEmpty: Bool {
        featured == nil && continueWatching.isEmpty && recentMovies.isEmpty && recentAlbums.isEmpty
    }

    static let empty = LibrarySnapshot()
}

struct ServerSession: Codable, Sendable, Equatable {
    let serverURL: URL
    let serverName: String
    let userId: String
    let userName: String

    var keychainAccount: String { "token.\(userId)@\(serverURL.absoluteString)" }
}
