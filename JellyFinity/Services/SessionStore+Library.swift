import Foundation

extension SessionStore {
    /// An authenticated client for the connected server, or nil in demo / signed-out mode.
    var client: JellyfinClient? {
        guard phase == .connected, let session,
              let token = KeychainStore.read(account: session.keychainAccount) else { return nil }
        return JellyfinClient(baseURL: session.serverURL, token: token, deviceId: deviceId)
    }

    var isDemo: Bool { phase == .demo }

    private func requireClient() throws -> (JellyfinClient, String) {
        guard let client, let userId = session?.userId else { throw JellyfinClient.ClientError.unreachable }
        return (client, userId)
    }

    func fetchLibrary(kind: LibraryKind, sort: LibrarySort, search: String, genre: String? = nil,
                      startIndex: Int, limit: Int) async throws -> (items: [MediaItem], total: Int) {
        if isDemo {
            return Self.demoLibrary(kind: kind, sort: sort, search: search, genre: genre, startIndex: startIndex)
        }
        let (client, userId) = try requireClient()
        return try await client.library(userId: userId, kind: kind, sort: sort, search: search, genre: genre,
                                        startIndex: startIndex, limit: limit)
    }

    func fetchGenres(kind: LibraryKind) async -> [String] {
        if isDemo {
            return Array(Set(SampleData.items(for: kind).flatMap(\.genres))).sorted()
        }
        guard let (client, userId) = try? requireClient() else { return [] }
        return (try? await client.genres(userId: userId, kind: kind)) ?? []
    }

    /// Loads the full record (overview, genres, logo) for an item shown in a detail page.
    func fetchDetail(_ item: MediaItem) async -> MediaItem {
        if isDemo, item.isVideo, item.cast.isEmpty {
            var demo = item
            demo.cast = CastMember.demo
            return demo
        }
        guard let (client, userId) = try? requireClient() else { return item }
        guard var full = try? await client.detail(userId: userId, itemId: item.id) else { return item }
        if full.primaryImageURL == nil { full.primaryImageURL = item.primaryImageURL }
        if full.backdropImageURL == nil { full.backdropImageURL = item.backdropImageURL }
        if full.logoImageURL == nil { full.logoImageURL = item.logoImageURL }
        return full
    }

    /// Upgrades the cast list: The Movie Database first (needs the user's own key), then IMDb,
    /// and finally whatever the Jellyfin server already provided.
    func enrichCast(_ item: MediaItem) async -> MediaItem {
        guard !isDemo, item.kind == .movie || item.kind == .series || item.kind == .episode else { return item }
        var updated = item
        if let tmdb = await TMDBClient.lookup(item: item) {
            updated.tmdbId = tmdb.tmdbId
            updated.cast = tmdb.members
            updated.castSource = "TMDB"
            return updated
        }
        let imdb = await IMDbClient.lookup(name: item.name, year: item.year, knownId: item.imdbId,
                                           allowSearch: item.kind != .episode)
        guard let imdb else { return item }
        updated.imdbId = imdb.imdbId
        if !imdb.actors.isEmpty {
            updated.cast = imdb.actors + item.cast.filter { $0.role != .actor }
            updated.castSource = "IMDb"
        }
        return updated
    }

    /// The title you watched most recently in a movies or shows library, for the cinematic header.
    func fetchLastWatched(kind: LibraryKind) async -> MediaItem? {
        guard kind == .movies || kind == .shows else { return nil }
        if isDemo {
            guard var first = SampleData.items(for: kind).first else { return nil }
            first.hasWatchHistory = true
            return first
        }
        guard let (client, userId) = try? requireClient() else { return nil }
        let types = kind == .movies ? "Movie" : "Episode"
        return try? await client.lastWatched(userId: userId, types: types)
    }

    func fetchVideoTracks(itemId: String) async -> MediaTracks {
        guard let (client, userId) = try? requireClient() else { return .empty }
        return (try? await client.mediaTracks(userId: userId, itemId: itemId)) ?? .empty
    }

    func fetchSeasons(of series: MediaItem) async throws -> [MediaItem] {
        if isDemo { return SampleData.seasons(of: series) }
        let (client, userId) = try requireClient()
        return try await client.seasons(userId: userId, seriesId: series.id)
    }

    func fetchEpisodes(of season: MediaItem, seriesId: String) async throws -> [MediaItem] {
        if isDemo { return SampleData.episodes(of: season) }
        let (client, userId) = try requireClient()
        return try await client.episodes(userId: userId, seriesId: seriesId, seasonId: season.id)
    }

    /// Artists matching a search term, for the Music tab's search results.
    func searchArtists(term: String) async -> [ArtistHit] {
        if isDemo {
            let names = Set(SampleData.items(for: .albums).compactMap(\.subtitle))
            return names.filter { $0.localizedCaseInsensitiveContains(term) }.sorted()
                .map { ArtistHit(id: $0, name: $0, imageURL: nil) }
        }
        guard let (client, userId) = try? requireClient() else { return [] }
        return (try? await client.searchArtists(userId: userId, term: term)) ?? []
    }

    func fetchArtistAlbums(artist: String) async throws -> [MediaItem] {
        if isDemo { return SampleData.items(for: .albums).filter { $0.subtitle == artist } }
        let (client, userId) = try requireClient()
        return try await client.artistAlbums(userId: userId, artist: artist)
    }

    func fetchTracks(of album: MediaItem) async throws -> [MediaItem] {
        if isDemo { return SampleData.tracks(of: album) }
        let (client, userId) = try requireClient()
        return try await client.tracks(userId: userId, albumId: album.id)
    }

    private static func demoLibrary(kind: LibraryKind, sort: LibrarySort, search: String, genre: String?,
                                    startIndex: Int) -> (items: [MediaItem], total: Int) {
        guard startIndex == 0 else { return ([], SampleData.items(for: kind).count) }
        var items = SampleData.items(for: kind)
        if let genre, !genre.isEmpty {
            items = items.filter { $0.genres.contains(genre) }
        }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(term) }
        }
        switch sort {
        case .recentlyAdded: break
        case .title: items.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .year: items.sort { ($0.year ?? 0) > ($1.year ?? 0) }
        case .rating: items.sort { ($0.communityRating ?? 0) > ($1.communityRating ?? 0) }
        }
        return (items, items.count)
    }
}
