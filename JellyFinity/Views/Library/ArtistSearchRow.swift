import SwiftUI

/// Round artist icons shown above album results when searching the Music tab.
struct ArtistSearchRow: View {
    let artists: [ArtistHit]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Artists")
                .font(.title3.weight(.bold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(artists) { artist in
                        NavigationLink(value: ArtistRoute(name: artist.name)) {
                            ArtistBubble(artist: artist)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
        }
    }
}

private struct ArtistBubble: View {
    let artist: ArtistHit

    var body: some View {
        VStack(spacing: 8) {
            ArtworkView(url: artist.imageURL, seed: artist.seed, symbol: "music.mic")
                .frame(width: 88, height: 88)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 5)
            Text(artist.name)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 92)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(artist.name), artist")
        .accessibilityHint("Shows all albums")
    }
}
