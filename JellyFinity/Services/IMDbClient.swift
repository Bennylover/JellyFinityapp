import Foundation

/// Looks up a title's IMDb ID and cast from IMDb's public endpoints (no API key needed).
/// Everything is best effort: any failure just returns nil so the app falls back to Jellyfin's own metadata.
enum IMDbClient {
    struct Result: Sendable {
        var imdbId: String
        var actors: [CastMember]
    }

    // MARK: - Public

    /// Finds the IMDb ID (from the server, or by searching title + year) and downloads the cast.
    static func lookup(name: String, year: Int?, knownId: String?, allowSearch: Bool) async -> Result? {
        var matchedId = knownId
        var teaser: [CastMember] = []
        if matchedId == nil, allowSearch, let hit = await search(name: name, year: year) {
            matchedId = hit.id
            teaser = hit.names.enumerated().map { CastMember(id: "imdb-s\($0.offset)", name: $0.element) }
        }
        guard let imdbId = matchedId else { return nil }
        var actors = await fetchCast(imdbId: imdbId)
        if actors.isEmpty { actors = teaser }
        return Result(imdbId: imdbId, actors: actors)
    }

    // MARK: - Search (suggestion API)

    private struct Suggestion: Decodable {
        struct Entry: Decodable {
            let id: String
            let l: String?
            let y: Int?
            let qid: String?
            let s: String?
        }
        let d: [Entry]?
    }

    private static let titleKinds: Set<String> = ["movie", "tvMovie", "tvSeries", "tvMiniSeries", "tvSpecial", "video"]

    private static func search(name: String, year: Int?) async -> (id: String, names: [String])? {
        let key = normalized(name)
        guard let first = key.first, !key.isEmpty else { return nil }
        let bucket = first.isLetter || first.isNumber ? String(first) : "x"
        let slug = key.replacingOccurrences(of: " ", with: "_")
        guard let url = URL(string: "https://v2.sg.media-imdb.com/suggestion/\(bucket)/\(slug).json"),
              let data = await get(url),
              let result = try? JSONDecoder().decode(Suggestion.self, from: data) else { return nil }
        let match = (result.d ?? []).first { entry in
            guard entry.id.hasPrefix("tt"), let kind = entry.qid, titleKinds.contains(kind),
                  normalized(entry.l ?? "") == key else { return false }
            guard let year, let found = entry.y else { return true }
            return abs(found - year) <= 1
        }
        guard let match else { return nil }
        let names = (match.s ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        return (match.id, names.filter { !$0.isEmpty })
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current).lowercased()
        let cleaned = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(cleaned).split(separator: " ").joined(separator: " ")
    }

    // MARK: - Cast (GraphQL)

    private struct GraphResponse: Decodable {
        struct DataBox: Decodable { let title: TitleBox? }
        struct TitleBox: Decodable { let credits: Credits? }
        struct Credits: Decodable { let edges: [Edge]? }
        struct Edge: Decodable { let node: Node? }
        struct Node: Decodable {
            let name: Person?
            let characters: [Character]?
        }
        struct Person: Decodable {
            let id: String?
            let nameText: Text?
            let primaryImage: Image?
        }
        struct Text: Decodable { let text: String? }
        struct Image: Decodable { let url: String? }
        struct Character: Decodable { let name: String? }
        let data: DataBox?
    }

    private static func fetchCast(imdbId: String) async -> [CastMember] {
        guard imdbId.range(of: "^tt[0-9]+$", options: .regularExpression) != nil else { return [] }
        for categories in ["\"cast\"", "\"actor\",\"actress\""] {
            for withCharacters in [true, false] {
                let members = await runCastQuery(imdbId: imdbId, categories: categories, withCharacters: withCharacters)
                if !members.isEmpty { return members }
            }
        }
        return []
    }

    private static func runCastQuery(imdbId: String, categories: String, withCharacters: Bool) async -> [CastMember] {
        let extra = withCharacters ? "... on Cast { characters { name } }" : ""
        let query = """
        { title(id: "\(imdbId)") { credits(first: 50, filter: { categories: [\(categories)] }) \
        { edges { node { name { id nameText { text } primaryImage { url } } \(extra) } } } } }
        """
        guard let url = URL(string: "https://api.graphql.imdb.com/"),
              let body = try? JSONSerialization.data(withJSONObject: ["query": query]),
              let data = await get(url, body: body),
              let response = try? JSONDecoder().decode(GraphResponse.self, from: data) else { return [] }
        let edges = response.data?.title?.credits?.edges ?? []
        var seen = Set<String>()
        return edges.compactMap { edge -> CastMember? in
            guard let node = edge.node, let person = node.name, let name = person.nameText?.text,
                  !name.isEmpty else { return nil }
            let id = person.id ?? name
            guard seen.insert(id).inserted else { return nil }
            let character = node.characters?.compactMap(\.name).filter { !$0.isEmpty }.joined(separator: " / ")
            return CastMember(id: "imdb-\(id)", name: name,
                              character: character?.isEmpty == false ? character : nil,
                              role: .actor, imageURL: portraitURL(person.primaryImage?.url))
        }
    }

    /// IMDb serves full-size posters; ask for a small version instead.
    private static func portraitURL(_ raw: String?) -> URL? {
        guard let raw, raw.hasPrefix("https://") else { return nil }
        let sized = raw.replacingOccurrences(of: "._V1_.", with: "._V1_UX240_.")
        return URL(string: sized)
    }

    // MARK: - Networking

    private static func get(_ url: URL, body: Data? = nil) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
