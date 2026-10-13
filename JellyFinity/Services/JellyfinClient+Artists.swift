import Foundation

/// An artist found by searching the Music library.
struct ArtistHit: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let imageURL: URL?
    let seed: Int

    init(id: String, name: String, imageURL: URL?) {
        self.id = id
        self.name = name
        self.imageURL = imageURL
        self.seed = name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 9973 }
    }
}

extension JellyfinClient {
    /// Artists whose name matches the search text. Album artists come first, then any other credited artists.
    func searchArtists(userId: String, term: String) async throws -> [ArtistHit] {
        let query: [URLQueryItem] = [
            .init(name: "userId", value: userId), .init(name: "searchTerm", value: term),
            .init(name: "Limit", value: "12"), .init(name: "SortBy", value: "SortName")
        ]
        let albumArtists = try await page(path: "Artists/AlbumArtists", query: query).items
        let others = (try? await page(path: "Artists", query: query).items) ?? []
        var seen = Set<String>()
        return (albumArtists + others).compactMap { artist in
            guard seen.insert(artist.id).inserted else { return nil }
            return ArtistHit(id: artist.id, name: artist.name, imageURL: artist.primaryImageURL)
        }
    }
}
