import SwiftUI

/// A cinematic header for the album you listened to most recently, like the one in Movies.
struct RecentMusicHero: View {
    @Environment(SessionStore.self) private var store
    @Environment(AudioPlayer.self) private var audio
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.appTheme) private var theme
    let album: MediaItem
    @State private var isStarting = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            content
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: theme.accent.opacity(0.3), radius: 22, y: 12)
    }

    private var backdrop: some View {
        ArtworkView(url: album.primaryImageURL, seed: album.artworkSeed, symbol: album.symbol, showsSymbol: false)
            .blur(radius: 36)
            .scaleEffect(1.4)
            .overlay(Color.black.opacity(0.45))
            .accessibilityHidden(true)
    }

    private var content: some View {
        HStack(alignment: .bottom, spacing: 16) {
            ArtworkView(url: album.primaryImageURL, seed: album.artworkSeed, symbol: album.symbol)
                .frame(width: 130, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
            VStack(alignment: .leading, spacing: 8) {
                tag
                Text(album.name).font(.title3.weight(.bold)).lineLimit(2)
                if let artist = album.subtitle {
                    Text(artist).font(.subheadline).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                }
                buttons
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(18)
    }

    private var tag: some View {
        Label("LISTENED RECENTLY", systemImage: "clock.arrow.circlepath")
            .font(.caption2.weight(.heavy))
            .tracking(1.1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Button { Task { await start() } } label: {
                Label("Play", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isStarting)
            .playHaptic()
            NavigationLink(value: album) {
                Image(systemName: "info.circle")
                    .font(.headline)
                    .padding(9)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Album details")
        }
        .padding(.top, 2)
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        var tracks: [MediaItem] = []
        if let fetched = try? await store.fetchTracks(of: album), !fetched.isEmpty {
            tracks = downloads.localized(fetched)
        } else {
            tracks = downloads.offlineChildren(of: album.id)
        }
        guard !tracks.isEmpty else { return }
        audio.play(tracks, startAt: 0, using: store, album: album)
    }
}

/// Horizontal shelf of albums you played lately.
struct RecentAlbumsRow: View {
    let albums: [MediaItem]
    var title = "Recently Played"
    var subtitle: String? = "Pick up where you left off"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(albums) { album in
                        NavigationLink(value: album) { card(album) }
                            .buttonStyle(.plain)
                            .selectionHaptic()
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private func card(_ album: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: album.primaryImageURL, seed: album.artworkSeed, symbol: album.symbol)
                .frame(width: 140, height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            Text(album.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            Text(album.subtitle ?? " ").font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 140, alignment: .leading)
    }
}
