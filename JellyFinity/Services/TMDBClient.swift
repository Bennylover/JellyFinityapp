import Foundation

/// Fetches cast and crew from The Movie Database using the user's own API key (kept in the Keychain).
/// Every failure returns an empty result so the caller can fall back to other sources.
enum TMDBClient {
    static let keyAccount = "tmdb.apikey"

    struct Result: Sendable {
        var tmdbId: String
        var members: [CastMember]
    }

    static var hasKey: Bool { storedKey != nil }

    private static var storedKey: String? {
        guard let key = KeychainStore.read(account: keyAccount), isValid(key) else { return nil }
        return key
    }

    /// TMDB keys are alphanumeric (v3) or a dotted JWT (v4); reject anything else.
    static func isValid(_ key: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        return key.count >= 16 && key.count <= 600 && key.unicodeScalars.allSatisfy(allowed.contains)
    }

    // MARK: - Lookup

    static func lookup(item: MediaItem) async -> Result? {
        guard let key = storedKey, item.kind == .movie || item.kind == .series else { return nil }
        let path = item.kind == .movie ? "movie" : "tv"
        guard let id = await resolveId(item: item, path: path, key: key) else { return nil }
        guard let data = await get("\(path)/\(id)/credits", query: [], key: key),
              let credits = try? JSONDecoder().decode(Credits.self, from: data) else { return nil }
        let members = map(credits)
        return members.isEmpty ? nil : Result(tmdbId: id, members: members)
    }

    private static func resolveId(item: MediaItem, path: String, key: String) async -> String? {
        if let tmdbId = item.tmdbId { return tmdbId }
        if let imdbId = item.imdbId, let id = await findByIMDb(imdbId, path: path, key: key) { return id }
        return await search(item: item, path: path, key: key)
    }

    private struct Found: Decodable {
        struct Entry: Decodable { let id: Int }
        let movieResults: [Entry]?
        let tvResults: [Entry]?
        let results: [Entry]?
        enum CodingKeys: String, CodingKey {
            case movieResults = "movie_results", tvResults = "tv_results", results
        }
    }

    private static func findByIMDb(_ imdbId: String, path: String, key: String) async -> String? {
        guard imdbId.range(of: "^tt[0-9]+$", options: .regularExpression) != nil,
              let data = await get("find/\(imdbId)", query: [.init(name: "external_source", value: "imdb_id")], key: key),
              let found = try? JSONDecoder().decode(Found.self, from: data) else { return nil }
        let entries = path == "movie" ? found.movieResults : found.tvResults
        return entries?.first.map { String($0.id) }
    }

    private static func search(item: MediaItem, path: String, key: String) async -> String? {
        var query: [URLQueryItem] = [.init(name: "query", value: item.name)]
        if let year = item.year {
            query.append(.init(name: path == "movie" ? "year" : "first_air_date_year", value: String(year)))
        }
        guard let data = await get("search/\(path)", query: query, key: key),
              let found = try? JSONDecoder().decode(Found.self, from: data) else { return nil }
        return found.results?.first.map { String($0.id) }
    }

    // MARK: - Credits

    private struct Credits: Decodable {
        struct Cast: Decodable {
            let id: Int
            let name: String
            let character: String?
            let profilePath: String?
            enum CodingKeys: String, CodingKey { case id, name, character, profilePath = "profile_path" }
        }
        struct Crew: Decodable {
            let id: Int
            let name: String
            let job: String?
            let profilePath: String?
            enum CodingKeys: String, CodingKey { case id, name, job, profilePath = "profile_path" }
        }
        let cast: [Cast]?
        let crew: [Crew]?
    }

    private static func map(_ credits: Credits) -> [CastMember] {
        let actors = (credits.cast ?? []).prefix(30).map {
            CastMember(id: "tmdb-\($0.id)", name: $0.name,
                       character: ($0.character?.isEmpty == false) ? $0.character : nil,
                       role: .actor, imageURL: portrait($0.profilePath))
        }
        var crew: [CastMember] = []
        var seen = Set<String>()
        let jobs: [(role: CastMember.Role, names: Set<String>)] = [
            (.director, ["Director"]),
            (.writer, ["Writer", "Screenplay", "Story", "Creator"]),
            (.producer, ["Producer", "Executive Producer"])
        ]
        for entry in jobs {
            let matches = (credits.crew ?? []).filter { entry.names.contains($0.job ?? "") }.prefix(6)
            for person in matches where seen.insert("\(entry.role.rawValue)-\(person.id)").inserted {
                crew.append(CastMember(id: "tmdb-\(entry.role.rawValue)-\(person.id)", name: person.name,
                                       role: entry.role, imageURL: portrait(person.profilePath)))
            }
        }
        return actors + crew
    }

    private static func portrait(_ path: String?) -> URL? {
        guard let path, path.hasPrefix("/") else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w185\(path)")
    }

    // MARK: - Networking

    private static func get(_ path: String, query: [URLQueryItem], key: String) async -> Data? {
        guard var comps = URLComponents(string: "https://api.themoviedb.org/3/\(path)") else { return nil }
        var items = query
        let isBearer = key.hasPrefix("eyJ")
        if !isBearer { items.append(.init(name: "api_key", value: key)) }
        comps.queryItems = items
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isBearer { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
