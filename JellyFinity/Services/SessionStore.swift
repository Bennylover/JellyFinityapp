import Foundation
import Observation

@MainActor
@Observable
final class SessionStore {
    enum Phase: Equatable { case signedOut, demo, connected }

    private(set) var phase: Phase = .signedOut
    private(set) var session: ServerSession?
    private(set) var snapshot: LibrarySnapshot = .empty
    private(set) var isLoading = false
    private(set) var loadError: String?

    let deviceId: String

    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let sessionKey = "jl.session"
    private static let demoKey = "jl.demo"
    private static let deviceKey = "jl.deviceId"

    init() {
        if let existing = defaults.string(forKey: Self.deviceKey) {
            deviceId = existing
        } else {
            let newId = UUID().uuidString
            defaults.set(newId, forKey: Self.deviceKey)
            deviceId = newId
        }

        if let data = defaults.data(forKey: Self.sessionKey),
           let saved = try? JSONDecoder().decode(ServerSession.self, from: data),
           KeychainStore.read(account: saved.keychainAccount) != nil {
            session = saved
            phase = .connected
        } else if defaults.bool(forKey: Self.demoKey) {
            phase = .demo
            snapshot = SampleData.snapshot
        }
    }

    var displayName: String {
        switch phase {
        case .connected: session?.userName ?? "there"
        default: "Alex"
        }
    }

    var serverName: String {
        phase == .connected ? (session?.serverName ?? "Jellyfin") : "Demo Library"
    }

    // MARK: - Actions

    func signIn(serverURL: URL, serverName: String, username: String, password: String) async throws {
        let client = JellyfinClient(baseURL: serverURL, token: nil, deviceId: deviceId)
        let auth = try await client.authenticate(username: username, password: password)
        let newSession = ServerSession(serverURL: serverURL, serverName: serverName,
                                       userId: auth.user.id, userName: auth.user.name)
        KeychainStore.save(auth.accessToken, account: newSession.keychainAccount)
        if let data = try? JSONEncoder().encode(newSession) {
            defaults.set(data, forKey: Self.sessionKey)
        }
        defaults.set(false, forKey: Self.demoKey)
        session = newSession
        snapshot = .empty
        phase = .connected
        await refresh()
    }

    func startDemo() {
        defaults.set(true, forKey: Self.demoKey)
        snapshot = SampleData.snapshot
        phase = .demo
    }

    func signOut() {
        if let session { KeychainStore.delete(account: session.keychainAccount) }
        defaults.removeObject(forKey: Self.sessionKey)
        defaults.set(false, forKey: Self.demoKey)
        session = nil
        snapshot = .empty
        loadError = nil
        phase = .signedOut
    }

    /// Up to 8 movies with backdrops: most-watched first, topped up with recent ones.
    static func featuredRotation(topWatched: [MediaItem], recent: [MediaItem]) -> [MediaItem] {
        var result: [MediaItem] = []
        var seen = Set<String>()
        let top = topWatched.filter { $0.backdropImageURL != nil }.prefix(8)
        for item in top where seen.insert(item.id).inserted { result.append(item) }
        if result.count < 5 {
            for item in recent where item.backdropImageURL != nil && result.count < 8 {
                if seen.insert(item.id).inserted { result.append(item) }
            }
        }
        if result.isEmpty, let first = recent.first { result = [first] }
        return result
    }

    func refresh() async {
        if phase == .demo {
            snapshot = SampleData.snapshot
            return
        }
        guard phase == .connected, let session,
              let token = KeychainStore.read(account: session.keychainAccount) else { return }

        let client = JellyfinClient(baseURL: session.serverURL, token: token, deviceId: deviceId)
        let userId = session.userId
        isLoading = true
        defer { isLoading = false }

        do {
            async let resume = client.resumeItems(userId: userId)
            async let movies = client.latest(userId: userId, types: "Movie", limit: 16)
            async let albums = client.latest(userId: userId, types: "MusicAlbum", limit: 12)
            async let counts = client.counts(userId: userId)
            let (resumeItems, movieItems, albumItems, countValues) = try await (resume, movies, albums, counts)

            let topWatched = (try? await client.topWatchedMovies(userId: userId, limit: 12)) ?? []
            let rotation = Self.featuredRotation(topWatched: topWatched, recent: movieItems)
            snapshot = LibrarySnapshot(
                featured: rotation.first,
                featuredItems: rotation,
                continueWatching: resumeItems,
                recentMovies: movieItems,
                recentAlbums: albumItems,
                counts: countValues
            )
            loadError = nil
        } catch JellyfinClient.ClientError.unauthorized {
            loadError = "Your session expired. Please sign in again."
            signOut()
        } catch {
            NSLog("Jellyfin refresh failed: \(error.localizedDescription)")
            loadError = error.localizedDescription
        }
    }
}
