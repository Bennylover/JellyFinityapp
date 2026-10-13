import SwiftUI

/// Full-width artist artwork that fades into the page, with the artist's portrait and name on top.
struct ArtistHeroHeader: View {
    let name: String
    let details: ArtistHit?
    let fallbackArt: URL?
    let albumCount: Int?
    @Environment(\.appTheme) private var theme

    private var seed: Int { name.unicodeScalars.reduce(0) { ($0 &+ Int($1.value)) % 9973 } }
    private var heroURL: URL? { details?.backdropURL ?? details?.imageURL ?? fallbackArt }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            backdrop
            HStack(alignment: .bottom, spacing: 14) {
                portrait
                titleBlock
                Spacer(minLength: 0)
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
        .frame(height: 320)
        .accessibilityElement(children: .combine)
    }

    private var backdrop: some View {
        ArtworkView(url: heroURL, seed: seed, symbol: "music.mic", showsSymbol: heroURL == nil)
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .overlay {
                LinearGradient(stops: [
                    .init(color: .clear, location: 0.25),
                    .init(color: theme.background.opacity(0.7), location: 0.7),
                    .init(color: theme.background, location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
            .accessibilityHidden(true)
    }

    private var portrait: some View {
        ArtworkView(url: details?.imageURL, seed: seed, symbol: "music.mic")
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ARTIST")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(theme.accent)
            Text(name)
                .font(.largeTitle.weight(.bold))
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            if let albumCount, albumCount > 0 {
                Text("\(albumCount) \(albumCount == 1 ? "album" : "albums")")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
