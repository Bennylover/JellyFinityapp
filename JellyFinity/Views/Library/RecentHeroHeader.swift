import SwiftUI

extension MediaItem {
    /// The show an episode belongs to, so headers and links can point at the series.
    var seriesItem: MediaItem? {
        guard kind == .episode, let seriesId else { return nil }
        return MediaItem(id: seriesId, name: subtitle ?? name, kind: .series,
                         backdropImageURL: backdropImageURL, logoImageURL: logoImageURL)
    }
}

/// A cinematic header that highlights the movie or show you watched most recently.
struct RecentHeroHeader: View {
    @Environment(\.appTheme) private var theme
    let item: MediaItem
    let onPlay: () -> Void

    private var titleItem: MediaItem { item.seriesItem ?? item }
    private var detailTarget: MediaItem { item.seriesItem ?? item }

    private var inProgress: Bool {
        guard let progress = item.progress else { return false }
        return progress > 0.02 && progress < 0.97
    }

    var body: some View {
        ArtworkView(url: item.backdropImageURL ?? item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
            .frame(height: 400)
            .overlay(alignment: .bottomLeading) { details }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: theme.accent.opacity(0.3), radius: 22, y: 12)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            tag
            LogoTitleView(item: titleItem, alignment: .leading, maxHeight: 76)
            Text(subline)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
            if inProgress, let progress = item.progress { progressBar(progress) }
            buttons
        }
        .foregroundStyle(.white)
        .padding(20)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.45), .black.opacity(0.88)],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private var tag: some View {
        Label(inProgress ? "CONTINUE WATCHING" : "WATCHED RECENTLY",
              systemImage: inProgress ? "play.circle.fill" : "clock.arrow.circlepath")
            .font(.caption2.weight(.heavy))
            .tracking(1.2)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var subline: String {
        if let label = item.episodeLabel { return "\(label) · \(item.name)" }
        let parts = [item.metaLine, item.genres.first ?? ""].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }

    private func progressBar(_ progress: Double) -> some View {
        Capsule()
            .fill(.white.opacity(0.25))
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(.white).frame(width: proxy.size.width * min(max(progress, 0), 1))
                }
            }
            .accessibilityLabel("Progress")
            .accessibilityValue("\(Int(progress * 100)) percent")
    }

    private var buttons: some View {
        HStack(spacing: 10) {
            if item.isVideo {
                Button(action: onPlay) {
                    Label(inProgress ? "Resume" : "Play", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            NavigationLink(value: detailTarget) {
                Label("Details", systemImage: "info.circle")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 2)
    }
}
