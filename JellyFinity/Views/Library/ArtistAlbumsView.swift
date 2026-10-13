import SwiftUI

/// Navigation value that opens an artist's albums.
struct ArtistRoute: Hashable {
    let name: String
}

/// Every album by one artist, in the same grid style as the Music tab.
struct ArtistAlbumsView: View {
    let artist: String
    @Environment(SessionStore.self) private var store
    @Environment(\.appTheme) private var theme
    @State private var albums: [MediaItem] = []
    @State private var isLoading = true
    @State private var failed = false
    @State private var details: ArtistHit?

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content.padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .ignoresSafeArea(edges: .top)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { await loadDetails() }
        .task { await load() }
    }

    private var header: some View {
        ArtistHeroHeader(name: artist, details: details,
                         fallbackArt: albums.first?.backdropImageURL ?? albums.first?.primaryImageURL,
                         albumCount: isLoading ? nil : albums.count)
    }

    private func loadDetails() async {
        details = await store.fetchArtistDetails(name: artist)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
        } else if albums.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: failed ? "wifi.exclamationmark" : "opticaldisc")
                    .font(.largeTitle).foregroundStyle(theme.accent)
                Text(failed ? "Couldn't load albums" : "No albums found").font(.headline)
                Text(failed ? "Check your connection and try again." : "This artist has no albums in your library.")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 60)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
                ForEach(albums) { album in
                    NavigationLink(value: album) { LibraryCard(item: album, kind: .albums) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func load() async {
        do {
            albums = try await store.fetchArtistAlbums(artist: artist)
        } catch {
            failed = true
        }
        isLoading = false
    }
}
