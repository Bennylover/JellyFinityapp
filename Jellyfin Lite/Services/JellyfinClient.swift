import Foundation

struct JellyfinClient: Sendable {
    let baseURL: URL
    var token: String?
    let deviceId: String

    enum ClientError: LocalizedError {
        case invalidAddress, unreachable, unauthorized, server(Int), decoding

        var errorDescription: String? {
            switch self {
            case .invalidAddress: "That doesn't look like a valid server address."
            case .unreachable: "We couldn't reach that server. Check the address and that you're on the same network."
            case .unauthorized: "Incorrect username or password."
            case .server(let code): "The server responded with an error (\(code))."
            case .decoding: "The server sent a response we didn't understand."
            }
        }
    }

    // MARK: - Discovery

    /// Normalizes user input like "192.168.1.5:8096" and finds a responding Jellyfin server.
    static func discover(address: String, deviceId: String) async throws -> (URL, PublicSystemInfo) {
        var trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { throw ClientError.invalidAddress }

        let candidates = trimmed.contains("://") ? [trimmed] : ["https://\(trimmed)", "http://\(trimmed)"]
        var lastError: Error = ClientError.invalidAddress
        for candidate in candidates {
            guard let url = URL(string: candidate), url.host() != nil,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { continue }
            do {
                let client = JellyfinClient(baseURL: url, token: nil, deviceId: deviceId)
                let info = try await client.publicInfo()
                return (url, info)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Endpoints

    func publicInfo() async throws -> PublicSystemInfo {
        try decode(PublicSystemInfo.self, from: await send("System/Info/Public"))
    }

    func authenticate(username: String, password: String) async throws -> AuthResult {
        let body = try JSONEncoder().encode(["Username": username, "Pw": password])
        let data = try await send("Users/AuthenticateByName", method: "POST", body: body)
        return try decode(AuthResult.self, from: data)
    }

    func resumeItems(userId: String) async throws -> [MediaItem] {
        try await items(query: [
            .init(name: "userId", value: userId), .init(name: "Filters", value: "IsResumable"),
            .init(name: "MediaTypes", value: "Video"), .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"), .init(name: "Recursive", value: "true"),
            .init(name: "Limit", value: "12"), .init(name: "Fields", value: "Genres,Overview")
        ])
    }

    func latest(userId: String, types: String, limit: Int) async throws -> [MediaItem] {
        try await items(query: [
            .init(name: "userId", value: userId), .init(name: "IncludeItemTypes", value: types),
            .init(name: "SortBy", value: "DateCreated"), .init(name: "SortOrder", value: "Descending"),
            .init(name: "Recursive", value: "true"), .init(name: "Limit", value: String(limit)),
            .init(name: "Fields", value: "Genres,Overview")
        ])
    }

    func counts(userId: String) async throws -> LibraryCounts {
        let data = try await send("Items/Counts", query: [.init(name: "userId", value: userId)])
        let dto = try decode(CountsDTO.self, from: data)
        return LibraryCounts(movies: dto.movieCount ?? 0, series: dto.seriesCount ?? 0,
                             albums: dto.albumCount ?? 0, audiobooks: dto.bookCount ?? 0)
    }

    // MARK: - Helpers

    private func items(query: [URLQueryItem]) async throws -> [MediaItem] {
        let data = try await send("Items", query: query)
        return try decode(ItemsResponse.self, from: data).items.map(map)
    }

    private func imageURL(_ itemId: String, type: String, maxWidth: Int) -> URL? {
        var comps = URLComponents(url: baseURL.appendingPathComponent("Items/\(itemId)/Images/\(type)"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [.init(name: "maxWidth", value: String(maxWidth)), .init(name: "quality", value: "90")]
        return comps?.url
    }

    private func map(_ dto: ItemDTO) -> MediaItem {
        let kind: MediaItem.Kind = switch dto.type {
        case "Movie": .movie
        case "Episode": .episode
        case "Series": .series
        case "MusicAlbum": .album
        case "AudioBook": .audiobook
        default: .other
        }
        let hasPrimary = dto.imageTags?["Primary"] != nil
        var backdrop: URL?
        if let tags = dto.backdropImageTags, !tags.isEmpty {
            backdrop = imageURL(dto.id, type: "Backdrop", maxWidth: 1200)
        } else if let parent = dto.parentBackdropItemId {
            backdrop = imageURL(parent, type: "Backdrop", maxWidth: 1200)
        }
        let subtitle = kind == .episode ? dto.seriesName : dto.albumArtist
        return MediaItem(
            id: dto.id, name: dto.name ?? "Untitled", subtitle: subtitle, kind: kind,
            year: dto.productionYear,
            runtimeMinutes: dto.runTimeTicks.map { Int($0 / 600_000_000) },
            communityRating: dto.communityRating, officialRating: dto.officialRating,
            genres: dto.genres ?? [], overview: dto.overview,
            progress: dto.userData?.playedPercentage.map { $0 / 100 },
            primaryImageURL: hasPrimary ? imageURL(dto.id, type: "Primary", maxWidth: 600) : nil,
            backdropImageURL: backdrop
        )
    }

    private var authorizationHeader: String {
        var header = "MediaBrowser Client=\"Jellyfin Lite\", Device=\"iPhone\", DeviceId=\"\(deviceId)\", Version=\"1.0\""
        if let token { header += ", Token=\"\(token)\"" }
        return header
    }

    private func send(_ path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) async throws -> Data {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw ClientError.invalidAddress
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw ClientError.invalidAddress }

        var request = URLRequest(url: url, timeoutInterval: 12)
        request.httpMethod = method
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClientError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.unreachable }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw ClientError.unauthorized
        default: throw ClientError.server(http.statusCode)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try JSONDecoder().decode(type, from: data) } catch { throw ClientError.decoding }
    }
}
