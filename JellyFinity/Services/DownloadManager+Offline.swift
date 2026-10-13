import Foundation

/// Lets the regular library screens fall back to what's saved on this iPhone.
extension DownloadManager {
    /// The same item, pointed at its downloaded file when one exists so playback is local.
    func localized(_ item: MediaItem) -> MediaItem {
        guard item.localFileURL == nil, let record = record(for: item.id) else { return item }
        var copy = item
        copy.localFileURL = record.fileURL
        return copy
    }

    func localized(_ items: [MediaItem]) -> [MediaItem] { items.map(localized) }

    /// Library cards built from downloads: albums and shows are grouped, movies and books listed as-is.
    func offlineLibrary(kind: LibraryKind, search: String, genre: String?) -> [MediaItem] {
        let saved = records(for: kind)
        var items: [MediaItem]
        if kind == .albums || kind == .shows {
            let groups = Dictionary(grouping: saved) { $0.groupId ?? $0.groupName ?? $0.id }
            items = groups.values.compactMap { groupItem(for: $0, kind: kind) }
        } else {
            items = saved.map(\.mediaItem)
        }
        if let genre, !genre.isEmpty { items = items.filter { $0.genres.contains(genre) } }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            items = items.filter {
                $0.name.localizedCaseInsensitiveContains(term) || ($0.subtitle ?? "").localizedCaseInsensitiveContains(term)
            }
        }
        return items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Downloaded tracks of an album (or episodes of a show) in play order.
    func offlineChildren(of groupId: String) -> [MediaItem] {
        records.filter { $0.groupId == groupId }
            .sorted { ($0.parentIndexNumber ?? 0, $0.indexNumber ?? 0) < ($1.parentIndexNumber ?? 0, $1.indexNumber ?? 0) }
            .map(\.mediaItem)
    }

    private func groupItem(for group: [DownloadRecord], kind: LibraryKind) -> MediaItem? {
        guard let first = group.first else { return nil }
        let artwork = first.groupArtworkURL ?? first.artworkURL
        if var saved = first.groupItem {
            saved.primaryImageURL = artwork ?? saved.primaryImageURL
            return saved
        }
        let id = first.groupId ?? first.id
        return MediaItem(
            id: id, name: first.groupName ?? first.name,
            subtitle: kind == .albums ? first.subtitle : nil,
            kind: kind == .albums ? .album : .series,
            year: first.year, primaryImageURL: artwork
        )
    }
}
