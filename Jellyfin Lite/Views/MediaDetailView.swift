import SwiftUI

struct MediaDetailView: View {
    @Environment(\.appTheme) private var theme
    let item: MediaItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ArtworkView(url: item.backdropImageURL ?? item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
                    .frame(height: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.name).font(.largeTitle.weight(.bold))
                    if !item.metaLine.isEmpty {
                        Text(item.metaLine).font(.subheadline).foregroundStyle(.secondary)
                    }
                    genreChips
                }
                Label("Playback arrives in the next update", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                if let overview = item.overview {
                    Text(overview).font(.body).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var genreChips: some View {
        HStack(spacing: 8) {
            ForEach(item.genres.prefix(3), id: \.self) { genre in
                Text(genre)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accent.opacity(0.12), in: Capsule())
            }
        }
    }
}
