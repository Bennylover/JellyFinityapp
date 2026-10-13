import Foundation

/// An artist found by searching the Music library.
struct ArtistHit: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let imageURL: URL?
    let backdropURL: URL?
    let seed: Int

    init(id: String, name: String, imageURL: URL?, backdropURL: URL? = nil) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.backdropURL = backdropURL
        self.seed = name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 9973 }
    }
}

/// Minimal artist payload so unusual fields on artist items can never break decoding.
private struct ArtistListDTO: Decodable {
    struct Entry: Decodable {
        let id: String?
        let itemId: String?
        let name: String?
        let type: String?
        let imageTags: [String: String]?
        let primaryImageTag: String?
        let backdropImageTags: [String]?
        enum CodingKeys: String, CodingKey {
            case id = "Id", itemId = "ItemId", name = "Name", type = "Type"
            case imageTags = "ImageTags", primaryImageTag = "PrimaryImageTag"
            case backdropImageTags = "BackdropImageTags"
        }
    }
    let items: [Entry]?
    let searchHints: [Entry]?
    enum CodingKeys: String, CodingKey { case items = "Items", searchHints = "SearchHints" }
    var entries: [Entry] { (items ?? []) + (searchHints ?? []) }
}

extension JellyfinClient {
    /// Artists whose name matches the search text, gathered from several endpoints because
    /// Jellyfin versions differ in which ones honour `searchTerm`.
    func searchArtists(userId: String, term: String) async -> [ArtistHit] {
        let base: [URLQueryItem] = [.init(name: "userId", value: userId), .init(name: "searchTerm", value: term)]
        let artistQuery = base + [.init(name: "Limit", value: "20"), .init(name: "Recursive", value: "true"),
                                  .init(name: "Fields", value: "PrimaryImageAspectRatio")]
        async let albumArtists = artistEntries("Artists/AlbumArtists", artistQuery)
        async let allArtists = artistEntries("Artists", artistQuery)
        async let hints = artistEntries("Search/Hints", base + [
            .init(name: "IncludeItemTypes", value: "MusicArtist"), .init(name: "Limit", value: "20")
        ])
        async let items = artistEntries("Items", artistQuery + [.init(name: "IncludeItemTypes", value: "MusicArtist")])
        var hits = rank(await albumArtists + allArtists + hints + items, term: term)
        if hits.isEmpty {
            // Last resort: some servers ignore searchTerm on artist routes, so filter the full list locally.
            let everyone = await artistEntries("Artists/AlbumArtists", [
                .init(name: "userId", value: userId), .init(name: "Limit", value: "5000"),
                .init(name: "SortBy", value: "SortName")
            ])
            hits = rank(everyone, term: term)
        }
        NSLog("JellyFinity artist search '%@' → %d hits", term, hits.count)
        return Array(hits.prefix(15))
    }

    /// The artist entry whose name matches exactly, used for header artwork on the artist page.
    func artistDetails(userId: String, name: String) async -> ArtistHit? {
        let hits = await searchArtists(userId: userId, term: name)
        let wanted = Self.normalized(name)
        let exact = hits.filter { Self.normalized($0.name) == wanted }
        return exact.first { $0.backdropURL != nil } ?? exact.first
    }

    private func artistEntries(_ path: String, _ query: [URLQueryItem]) async -> [ArtistListDTO.Entry] {
        do {
            let data = try await send(path, query: query)
            return try JSONDecoder().decode(ArtistListDTO.self, from: data).entries
        } catch {
            NSLog("JellyFinity artist lookup %@ failed: %@", path, String(describing: error))
            return []
        }
    }

    /// Keeps matching artists only, de-duplicated by name, with name-prefix matches first.
    private func rank(_ entries: [ArtistListDTO.Entry], term: String) -> [ArtistHit] {
        let needle = Self.normalized(term)
        var seen = Set<String>()
        var hits: [(hit: ArtistHit, score: Int)] = []
        for entry in entries {
            if let type = entry.type, type != "MusicArtist" { continue }
            guard let id = entry.id ?? entry.itemId, let name = entry.name, !name.isEmpty else { continue }
            let key = Self.normalized(name)
            guard key.contains(needle), seen.insert(key).inserted else { continue }
            let hasImage = entry.imageTags?["Primary"] != nil || entry.primaryImageTag != nil
            let image = hasImage ? imageURL(id, type: "Primary", maxWidth: 300) : nil
            let hasBackdrop = !(entry.backdropImageTags ?? []).isEmpty
            let backdrop = hasBackdrop ? imageURL(id, type: "Backdrop", maxWidth: 1400) : nil
            let score = key == needle ? 0 : (key.hasPrefix(needle) ? 1 : 2)
            hits.append((ArtistHit(id: id, name: name, imageURL: image, backdropURL: backdrop), score))
        }
        return hits.sorted { $0.score < $1.score }.map(\.hit)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
