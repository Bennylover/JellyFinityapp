import SwiftUI

/// Seasons picker plus episode list for a show. Tapping an episode starts playback.
struct SeriesEpisodesSection: View {
    @Environment(SessionStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.appTheme) private var theme
    let series: MediaItem
    let onPlay: (MediaItem) -> Void

    @State private var seasons: [MediaItem] = []
    @State private var selected: MediaItem?
    @State private var episodes: [MediaItem] = []
    @State private var isLoading = true
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Episodes").font(.title3.weight(.bold))
            if seasons.count > 1 { seasonChips }
            if !episodes.isEmpty {
                DownloadButton(items: episodes, group: series, idleTitle: "Download \(selected?.name ?? "Season")")
            }
            if isLoading {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if failed || episodes.isEmpty {
                Text(failed ? "Couldn't load episodes. Check your connection." : "No episodes found.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(episodes) { episode in
                    HStack(spacing: 8) {
                        Button { onPlay(episode) } label: { EpisodeRow(episode: episode) }
                            .buttonStyle(.plain)
                        DownloadIconButton(item: episode, group: series)
                    }
                }
            }
        }
        .task { await loadSeasons() }
        .task(id: selected?.id) { await loadEpisodes() }
    }

    private var seasonChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(seasons) { season in
                    let isSelected = season.id == selected?.id
                    Button { selected = season } label: {
                        Text(season.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.white : theme.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(isSelected ? AnyShapeStyle(theme.gradient) : AnyShapeStyle(theme.accent.opacity(0.12)), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func loadSeasons() async {
        do {
            seasons = try await store.fetchSeasons(of: series)
            selected = seasons.first
            if seasons.isEmpty { isLoading = false }
        } catch {
            episodes = downloads.offlineChildren(of: series.id)
            failed = episodes.isEmpty
            isLoading = false
        }
    }

    private func loadEpisodes() async {
        guard let selected else { return }
        isLoading = true
        failed = false
        do {
            episodes = try await store.fetchEpisodes(of: selected, seriesId: series.id)
        } catch {
            failed = true
        }
        isLoading = false
    }
}

private struct EpisodeRow: View {
    @Environment(\.appTheme) private var theme
    let episode: MediaItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ArtworkView(url: episode.primaryImageURL, seed: episode.artworkSeed, symbol: "play.fill")
                .frame(width: 132, height: 74)
                .overlay(alignment: .bottom) { progressBar }
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(titleLine).font(.subheadline.weight(.semibold)).lineLimit(2)
                if let minutes = episode.runtimeMinutes {
                    Text(MediaItem.formatRuntime(minutes)).font(.caption).foregroundStyle(.secondary)
                }
                if let overview = episode.overview {
                    Text(overview).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private var titleLine: String {
        guard let number = episode.indexNumber else { return episode.name }
        return "\(number). \(episode.name)"
    }

    @ViewBuilder
    private var progressBar: some View {
        if let progress = episode.progress, progress > 0 {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(.black.opacity(0.4))
                    Rectangle().fill(theme.accent).frame(width: proxy.size.width * min(progress, 1))
                }
            }
            .frame(height: 4)
        }
    }
}

/// Track list for an album with Play and Shuffle.
struct AlbumTracksSection: View {
    @Environment(SessionStore.self) private var store
    @Environment(AudioPlayer.self) private var audio
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.appTheme) private var theme
    let album: MediaItem

    @State private var tracks: [MediaItem] = []
    @State private var isLoading = true
    @State private var swipeActive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                PrimaryActionButton(title: "Play", symbol: "play.fill") {
                    audio.play(tracks, startAt: 0, using: store, album: album)
                }
                Button {
                    audio.play(tracks.shuffled(), startAt: 0, using: store, album: album)
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                        .font(.headline)
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .playHaptic()
            }
            .disabled(tracks.isEmpty)
            DownloadButton(items: tracks, group: album, idleTitle: "Download Album")
            trackList
        }
        .task { await load() }
    }

    @ViewBuilder
    private var trackList: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if tracks.isEmpty {
            Text("No tracks found.").font(.subheadline).foregroundStyle(.secondary)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, track in
                    HStack(spacing: 0) {
                        Button {
                            guard !swipeActive else { return }
                            audio.play(tracks, startAt: offset, using: store, album: album)
                        } label: {
                            TrackRow(track: track, number: offset + 1, isCurrent: audio.current?.id == track.id)
                        }
                        .buttonStyle(.plain)
                        .selectionHaptic()
                        DownloadIconButton(item: track, group: album)
                            .padding(.trailing, 14)
                    }
                    .swipeToQueue(suppressTap: $swipeActive) { audio.enqueue(track, using: store) }
                    .contextMenu {
                        Button { audio.enqueue(track, playNext: true, using: store) } label: {
                            Label("Play Next", systemImage: "text.insert")
                        }
                        Button { audio.enqueue(track, using: store) } label: {
                            Label("Add to Queue", systemImage: "text.append")
                        }
                    }
                    if offset < tracks.count - 1 { Divider() }
                }
            }
            .cardSurface(radius: 18)
        }
    }

    private func load() async {
        if let fetched = try? await store.fetchTracks(of: album), !fetched.isEmpty {
            tracks = downloads.localized(fetched)
        } else {
            tracks = downloads.offlineChildren(of: album.id)
        }
        isLoading = false
    }
}

private struct TrackRow: View {
    @Environment(\.appTheme) private var theme
    let track: MediaItem
    let number: Int
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if isCurrent {
                    Image(systemName: "waveform").foregroundStyle(theme.accent)
                } else {
                    Text("\(track.indexNumber ?? number)").foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.monospacedDigit())
            .frame(width: 28)
            Text(track.name)
                .font(.body.weight(isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? theme.accent : Color.primary)
                .lineLimit(1)
            Spacer()
            if let duration = track.durationText {
                Text(duration).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}
