import Observation
import SwiftUI

@MainActor
@Observable
final class LibraryModel {
    private(set) var items: [MediaItem] = []
    private(set) var total = 0
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var generation = 0
    private let pageSize = 60

    /// True when the server couldn't be reached and the grid shows downloads instead.
    private(set) var isOffline = false

    func reload(kind: LibraryKind, sort: LibrarySort, search: String, genre: String?,
                store: SessionStore, downloads: DownloadManager) async {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await store.fetchLibrary(kind: kind, sort: sort, search: search, genre: genre,
                                                      startIndex: 0, limit: pageSize)
            guard current == generation else { return }
            items = result.items
            total = result.total
            isOffline = false
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            items = downloads.offlineLibrary(kind: kind, search: search, genre: genre)
            total = items.count
            isOffline = true
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func loadMoreIfNeeded(after item: MediaItem, kind: LibraryKind, sort: LibrarySort,
                          search: String, genre: String?, store: SessionStore) async {
        guard !isOffline, item.id == items.last?.id, items.count < total, !isLoading else { return }
        let current = generation
        isLoading = true
        defer { isLoading = false }
        guard let result = try? await store.fetchLibrary(kind: kind, sort: sort, search: search, genre: genre,
                                                         startIndex: items.count, limit: pageSize),
              current == generation else { return }
        items.append(contentsOf: result.items)
        total = result.total
    }
}

/// A browsable library (movies, shows, albums or audiobooks) with search, sorting and paging.
struct LibraryView: View {
    let kind: LibraryKind
    @Environment(SessionStore.self) private var store
    @Environment(\.appTheme) private var theme
    @Environment(DownloadManager.self) private var downloads
    @State private var model = LibraryModel()
    @State private var search = ""
    @State private var sort: LibrarySort = .recentlyAdded
    @State private var lastWatched: MediaItem?
    @State private var playing: MediaItem?
    @State private var genres: [String] = []
    @State private var selectedGenre: String?
    @State private var artists: [ArtistHit] = []

    private var matchingGenres: [String] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return genres.filter { $0.localizedCaseInsensitiveContains(term) }.prefix(6).map { $0 }
    }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: kind.isSquare ? 150 : 108, maximum: 200), spacing: 14, alignment: .top)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    GenreChipRow(genres: genres, selected: $selectedGenre)
                    content
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(kind.title)
            .searchable(text: $search, prompt: "Search \(kind.title.lowercased()) or genres")
            .searchSuggestions {
                ForEach(matchingGenres, id: \.self) { genre in
                    Button {
                        selectedGenre = genre
                        search = ""
                    } label: {
                        Label(genre, systemImage: "tag")
                    }
                }
            }
            .toolbar { sortMenu }
            .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
            .navigationDestination(for: ArtistRoute.self) { ArtistAlbumsView(artist: $0.name) }
            .fullScreenCover(item: $playing) { VideoPlayerScreen(item: $0) }
            .refreshable {
                await loadHero()
                await reload()
            }
            .task { await loadHero() }
            .task { genres = await store.fetchGenres(kind: kind) }
            .onChange(of: playing?.id) { _, newValue in
                if newValue == nil { Task { await loadHero() } }
            }
            .task(id: "\(search)|\(sort.rawValue)|\(selectedGenre ?? "")") {
                if !search.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                await reload()
            }
            .task(id: search) { await loadArtists() }
        }
        .miniPlayerInset()
    }

    @ViewBuilder
    private var hero: some View {
        if search.isEmpty, selectedGenre == nil, let lastWatched {
            RecentHeroHeader(item: lastWatched) { playing = lastWatched }
                .transition(.opacity)
        }
    }

    private func loadHero() async {
        let item = await store.fetchLastWatched(kind: kind)
        withAnimation(.easeOut(duration: 0.3)) { lastWatched = item }
    }

    private func loadArtists() async {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kind == .albums, !term.isEmpty else {
            artists = []
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        let found = await store.searchArtists(term: term)
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.2)) { artists = found }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded && model.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
        } else if model.items.isEmpty {
            if !artists.isEmpty { ArtistSearchRow(artists: artists) }
            else {
                LibraryEmptyView(kind: kind, isSearching: !search.isEmpty || selectedGenre != nil,
                                 error: model.errorMessage)
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !artists.isEmpty { ArtistSearchRow(artists: artists) }
                countLine
                LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                    ForEach(model.items) { item in
                        NavigationLink(value: item) { LibraryCard(item: item, kind: kind) }
                            .buttonStyle(.plain)
                            .task { await loadMore(after: item) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var countLine: some View {
        if model.isOffline {
            Label("Server offline · showing \(model.total) downloaded", systemImage: "icloud.slash")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.accent)
        } else {
            Text("\(model.total) \(model.total == 1 ? "title" : "titles") · \(sort.label)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var sortMenu: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                DownloadsView(kind: kind)
            } label: {
                Image(systemName: downloads.records(for: kind).isEmpty ? "arrow.down.circle" : "arrow.down.circle.fill")
            }
            .accessibilityLabel("Downloads")
            Menu {
                Picker("Sort by", selection: $sort) {
                    ForEach(LibrarySort.allCases) { Text($0.label).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down.circle")
            }
            .accessibilityLabel("Sort")
        }
    }

    private func reload() async {
        await model.reload(kind: kind, sort: sort, search: search, genre: selectedGenre,
                           store: store, downloads: downloads)
    }

    private func loadMore(after item: MediaItem) async {
        await model.loadMoreIfNeeded(after: item, kind: kind, sort: sort, search: search,
                                     genre: selectedGenre, store: store)
    }
}

/// Horizontally scrolling genre filter; tap a genre to filter, tap again to clear.
private struct GenreChipRow: View {
    @Environment(\.appTheme) private var theme
    let genres: [String]
    @Binding var selected: String?

    var body: some View {
        if !genres.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        chip(genre)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    private func chip(_ genre: String) -> some View {
        let isOn = selected == genre
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { selected = isOn ? nil : genre }
        } label: {
            Text(genre)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : theme.accent)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(isOn ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.accent.opacity(0.12)), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct LibraryCard: View {
    let item: MediaItem
    let kind: LibraryKind

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
                .aspectRatio(kind.isSquare ? 1 : 2.0 / 3.0, contentMode: .fit)
                .overlay(alignment: .topTrailing) { ratingBadge }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(secondaryLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var secondaryLine: String {
        if kind.isSquare, let subtitle = item.subtitle { return subtitle }
        return item.year.map(String.init) ?? " "
    }

    @ViewBuilder
    private var ratingBadge: some View {
        if !kind.isSquare, let rating = item.communityRating {
            Label(String(format: "%.1f", rating), systemImage: "star.fill")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(8)
        }
    }
}

private struct LibraryEmptyView: View {
    @Environment(\.appTheme) private var theme
    let kind: LibraryKind
    let isSearching: Bool
    let error: String?

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.14)).frame(width: 120, height: 120)
                Image(systemName: error == nil ? kind.symbol : "wifi.exclamationmark")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(theme.gradient)
            }
            Text(title).font(.title3.weight(.bold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.top, 80)
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        if error != nil { return "Couldn't load your library" }
        return isSearching ? "No matches" : "Nothing here yet"
    }

    private var message: String {
        if let error { return error }
        return isSearching ? "Try a different title or clear the search." : kind.emptyMessage
    }
}
