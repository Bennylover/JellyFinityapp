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

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 14, alignment: .top)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                content
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.gradient).frame(width: 64, height: 64)
                Image(systemName: "music.mic").font(.title2).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(artist).font(.title2.weight(.bold)).lineLimit(2)
                if !isLoading && !albums.isEmpty {
                    Text("\(albums.count) \(albums.count == 1 ? "album" : "albums")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
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
