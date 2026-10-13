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

    func reload(kind: LibraryKind, sort: LibrarySort, search: String, store: SessionStore) async {
        generation += 1
        let current = generation
        isLoading = true
        errorMessage = nil
        do {
            let result = try await store.fetchLibrary(kind: kind, sort: sort, search: search,
                                                      startIndex: 0, limit: pageSize)
            guard current == generation else { return }
            items = result.items
            total = result.total
        } catch {
            guard current == generation, !Task.isCancelled else { return }
            items = []
            total = 0
            errorMessage = error.localizedDescription
        }
        isLoading = false
        hasLoaded = true
    }

    func loadMoreIfNeeded(after item: MediaItem, kind: LibraryKind, sort: LibrarySort,
                          search: String, store: SessionStore) async {
        guard item.id == items.last?.id, items.count < total, !isLoading else { return }
        let current = generation
        isLoading = true
        defer { isLoading = false }
        guard let result = try? await store.fetchLibrary(kind: kind, sort: sort, search: search,
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
    @State private var model = LibraryModel()
    @State private var search = ""
    @State private var sort: LibrarySort = .recentlyAdded
    @State private var lastWatched: MediaItem?
    @State private var playing: MediaItem?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: kind.isSquare ? 150 : 108, maximum: 200), spacing: 14, alignment: .top)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    content
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(kind.title)
            .searchable(text: $search, prompt: "Search \(kind.title.lowercased())")
            .toolbar { sortMenu }
            .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
            .fullScreenCover(item: $playing) { VideoPlayerScreen(item: $0) }
            .refreshable {
                await loadHero()
                await reload()
            }
            .task { await loadHero() }
            .onChange(of: playing?.id) { _, newValue in
                if newValue == nil { Task { await loadHero() } }
            }
            .task(id: "\(search)|\(sort.rawValue)") {
                if !search.isEmpty { try? await Task.sleep(for: .milliseconds(350)) }
                guard !Task.isCancelled else { return }
                await reload()
            }
        }
        .miniPlayerInset()
    }

    @ViewBuilder
    private var hero: some View {
        if search.isEmpty, let lastWatched {
            RecentHeroHeader(item: lastWatched) { playing = lastWatched }
                .transition(.opacity)
        }
    }

    private func loadHero() async {
        let item = await store.fetchLastWatched(kind: kind)
        withAnimation(.easeOut(duration: 0.3)) { lastWatched = item }
    }

    @ViewBuilder
    private var content: some View {
        if !model.hasLoaded && model.items.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 100)
        } else if model.items.isEmpty {
            LibraryEmptyView(kind: kind, isSearching: !search.isEmpty, error: model.errorMessage)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(model.total) \(model.total == 1 ? "title" : "titles") · \(sort.label)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
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

    private var sortMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
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
        await model.reload(kind: kind, sort: sort, search: search, store: store)
    }

    private func loadMore(after item: MediaItem) async {
        await model.loadMoreIfNeeded(after: item, kind: kind, sort: sort, search: search, store: store)
    }
}

private struct LibraryCard: View {
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
