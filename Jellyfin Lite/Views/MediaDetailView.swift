import SwiftUI

/// Title artwork: the movie's transparent logo when the server has one, styled text otherwise.
struct LogoTitleView: View {
    let item: MediaItem
    var alignment: Alignment = .center
    var maxHeight: CGFloat = 90

    var body: some View {
        if let url = item.logoImageURL {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                        .frame(maxWidth: 280, maxHeight: maxHeight, alignment: alignment)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                case .empty:
                    Color.clear.frame(height: maxHeight)
                default:
                    titleText
                }
            }
            .frame(maxWidth: .infinity, alignment: alignment)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
        } else {
            titleText.frame(maxWidth: .infinity, alignment: alignment)
        }
    }

    private var titleText: some View {
        Text(item.name)
            .font(.system(size: 32, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(alignment == .center ? .center : .leading)
            .lineLimit(3)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
    }
}

struct MediaDetailView: View {
    @Environment(\.appTheme) private var theme
    @Environment(SessionStore.self) private var store
    @Environment(AudioPlayer.self) private var audio
    @State private var item: MediaItem
    @State private var playingVideo: MediaItem?

    init(item: MediaItem) {
        _item = State(initialValue: item)
    }

    private var isCoverStyle: Bool { item.kind == .album || item.kind == .audiobook }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if isCoverStyle { coverHeader } else { cinematicHeader }
                info
                actions
                if let overview = item.overview, !overview.isEmpty {
                    Text(overview).font(.body).foregroundStyle(.secondary)
                }
                related
            }
            .padding()
            .padding(.bottom, 24)
        }
        .background(theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $playingVideo) { VideoPlayerScreen(item: $0) }
        .task { item = await store.fetchDetail(item) }
    }

    // MARK: - Headers

    private var cinematicHeader: some View {
        ArtworkView(url: item.backdropImageURL ?? item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
            .frame(height: 320)
            .overlay(alignment: .bottom) {
                LogoTitleView(item: item)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                    .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom))
            }
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: theme.accent.opacity(0.25), radius: 20, y: 10)
    }

    private var coverHeader: some View {
        VStack(spacing: 14) {
            ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
                .frame(width: 250, height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: theme.accent.opacity(0.35), radius: 22, y: 12)
            Text(item.name).font(.title.weight(.bold)).multilineTextAlignment(.center)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let rating = item.communityRating {
                    Label(String(format: "%.1f", rating), systemImage: "star.fill")
                        .foregroundStyle(.yellow)
                }
                Text(infoLine)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            genreChips
        }
    }

    private var infoLine: String {
        var parts = [item.metaLine]
        if item.kind == .audiobook, let text = item.durationText { parts.append(text) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
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

    // MARK: - Actions & related content

    @ViewBuilder
    private var actions: some View {
        switch item.kind {
        case .movie, .episode:
            PrimaryActionButton(title: playTitle, symbol: "play.fill") { playingVideo = item }
        case .audiobook:
            PrimaryActionButton(title: playTitle, symbol: "play.fill") {
                audio.play([item], startAt: 0, using: store)
            }
        default:
            EmptyView()
        }
    }

    private var playTitle: String {
        if let progress = item.progress, progress > 0.02, progress < 0.97 {
            return item.remainingText.map { "Resume · \($0)" } ?? "Resume"
        }
        if item.kind == .audiobook, let seconds = item.resumeSeconds, seconds > 5 {
            return "Resume · \(formatPlaybackTime(seconds))"
        }
        return "Play"
    }

    @ViewBuilder
    private var related: some View {
        switch item.kind {
        case .series:
            SeriesEpisodesSection(series: item) { playingVideo = $0 }
        case .album:
            AlbumTracksSection(album: item)
        default:
            EmptyView()
        }
    }
}

struct PrimaryActionButton: View {
    @Environment(\.appTheme) private var theme
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(theme.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: theme.accent.opacity(0.35), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
    }
}
