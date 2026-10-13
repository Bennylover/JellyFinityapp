import Foundation

struct MediaItem: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case movie, episode, series, season, album, track, audiobook, other
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
    var logoImageURL: URL? = nil
    var seriesId: String? = nil
    var indexNumber: Int? = nil
    var parentIndexNumber: Int? = nil
    var durationSeconds: Double? = nil
    var resumeSeconds: Double? = nil
    var hasWatchHistory = false
    var cast: [CastMember] = []
    var imdbId: String? = nil

    /// "S2 · E4" style label for episodes.
    var episodeLabel: String? {
        guard kind == .episode, let indexNumber else { return nil }
        if let parentIndexNumber { return "S\(parentIndexNumber) · E\(indexNumber)" }
        return "E\(indexNumber)"
    }

    var artworkSeed: Int {
        id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    }

    var symbol: String {
        switch kind {
        case .movie: "film"
        case .episode, .series, .season: "tv"
        case .album, .track: "music.note"
        case .audiobook: "book.closed"
        case .other: "sparkles"
        }
    }

    var isVideo: Bool { kind == .movie || kind == .episode }
    var isAudio: Bool { kind == .track || kind == .audiobook }

    var durationText: String? {
        guard let durationSeconds, durationSeconds > 0 else { return nil }
        let total = Int(durationSeconds)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                         : String(format: "%d:%02d", minutes, seconds)
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

/// The four libraries a user can browse.
enum LibraryKind: String, CaseIterable, Sendable {
    case movies, shows, albums, audiobooks

    var title: String {
        switch self {
        case .movies: "Movies"
        case .shows: "Shows"
        case .albums: "Music"
        case .audiobooks: "Audiobooks"
        }
    }

    var includeTypes: String {
        switch self {
        case .movies: "Movie"
        case .shows: "Series"
        case .albums: "MusicAlbum"
        case .audiobooks: "AudioBook"
        }
    }

    var symbol: String {
        switch self {
        case .movies: "film.stack"
        case .shows: "tv"
        case .albums: "music.note"
        case .audiobooks: "headphones"
        }
    }

    var isSquare: Bool { self == .albums || self == .audiobooks }

    var emptyMessage: String {
        switch self {
        case .movies: "No movies yet. Add a Movies library on your Jellyfin server and they'll show up here."
        case .shows: "No shows yet. Add a Shows library on your server and pull down to refresh."
        case .albums: "No albums yet. Add a Music library on your server to fill this shelf."
        case .audiobooks: "No audiobooks yet. Add a Books library with audiobooks to your server."
        }
    }
}

enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case recentlyAdded, title, year, rating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recentlyAdded: "Recently Added"
        case .title: "Title"
        case .year: "Year"
        case .rating: "Rating"
        }
    }

    var sortBy: String {
        switch self {
        case .recentlyAdded: "DateCreated,SortName"
        case .title: "SortName"
        case .year: "ProductionYear,SortName"
        case .rating: "CommunityRating,SortName"
        }
    }

    var ascending: Bool { self == .title }
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
