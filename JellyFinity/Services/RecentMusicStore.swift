import Foundation

/// Remembers the albums you played last, on this device.
enum RecentMusicStore {
    private static let key = "jl.recentAlbums.v1"

    static func load() -> [MediaItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let albums = try? JSONDecoder().decode([MediaItem].self, from: data) else { return [] }
        return albums
    }

    static func save(_ albums: [MediaItem]) {
        guard let data = try? JSONEncoder().encode(albums) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
