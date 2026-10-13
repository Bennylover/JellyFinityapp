import SwiftUI

struct FeaturedHeroCard: View {
    @Environment(\.appTheme) private var theme
    let item: MediaItem

    var body: some View {
        ArtworkView(url: item.backdropImageURL ?? item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
            .frame(height: 440)
            .overlay(alignment: .bottomLeading) { details }
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: theme.accent.opacity(0.3), radius: 24, y: 14)
    }

    private var scrim: LinearGradient {
        LinearGradient(colors: [.clear, .black.opacity(0.35), .black.opacity(0.85)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FEATURED")
                .font(.caption2.weight(.heavy))
                .tracking(1.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.white.opacity(0.2), in: Capsule())
            Text(item.name)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .lineLimit(2)
            metaRow
            HStack(spacing: 10) {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(.white, in: Capsule())
                Label("Details", systemImage: "info.circle")
                    .font(.headline)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.top, 4)
        }
        .foregroundStyle(.white)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scrim)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            if let rating = item.communityRating {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .foregroundStyle(.yellow)
            }
            Text(item.metaLine)
            if let genre = item.genres.first {
                Text("· \(genre)")
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white.opacity(0.9))
    }
}

struct StatsRow: View {
    let counts: LibraryCounts

    var body: some View {
        HStack(spacing: 12) {
            StatTile(value: counts.movies, label: "Movies", symbol: "film.fill")
            StatTile(value: counts.albums, label: "Albums", symbol: "music.note")
            StatTile(value: counts.audiobooks, label: "Books", symbol: "headphones")
        }
        .padding(.horizontal)
    }
}

private struct StatTile: View {
    @Environment(\.appTheme) private var theme
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(theme.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(value, format: .number)
                .font(.title2.weight(.bold).monospacedDigit())
                .contentTransition(.numericText())
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(radius: 20)
    }
}

struct ContinueWatchingRow: View {
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Continue Watching", subtitle: "Pick up right where you left off")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { ContinueCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ContinueCard: View {
    @Environment(\.appTheme) private var theme
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: item.backdropImageURL ?? item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
                .frame(width: 270, height: 152)
                .overlay(alignment: .bottom) { progressBar }
                .overlay {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.9))
                        .shadow(radius: 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text([item.subtitle, item.remainingText].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 270, alignment: .leading)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3))
                Capsule().fill(theme.gradient)
                    .frame(width: proxy.size.width * (item.progress ?? 0))
            }
        }
        .frame(height: 5)
        .padding(12)
    }
}

struct PosterRow: View {
    let title: String
    let subtitle: String
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: title, subtitle: subtitle)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { PosterCard(item: item) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct PosterCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
                .frame(width: 140, height: 210)
                .overlay(alignment: .topTrailing) { ratingBadge }
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Text(item.year.map(String.init) ?? " ")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140, alignment: .leading)
    }

    @ViewBuilder
    private var ratingBadge: some View {
        if let rating = item.communityRating {
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

struct AlbumRow: View {
    let items: [MediaItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "New in Music", subtitle: "Albums recently added")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
                                .frame(width: 150, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text(item.subtitle ?? "Unknown Artist").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(width: 150, alignment: .leading)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}
