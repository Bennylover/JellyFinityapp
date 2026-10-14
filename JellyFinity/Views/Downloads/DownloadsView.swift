import SwiftUI

/// Everything saved on this device for one library; plays without leaving the app.
struct DownloadsView: View {
    let kind: LibraryKind
    @Environment(SessionStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(AudioPlayer.self) private var audio
    @Environment(\.appTheme) private var theme
    @State private var playing: MediaItem?

    private var records: [DownloadRecord] { downloads.records(for: kind) }
    private var active: [(item: MediaItem, fraction: Double)] { downloads.activeItems(for: kind) }
    private var isGrouped: Bool { kind == .shows || kind == .albums }

    var body: some View {
        List {
            if !active.isEmpty { activeSection }
            if !records.isEmpty { summarySection }
            if isGrouped { groupedSections } else { flatSection }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle("\(kind.title) Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if records.isEmpty && active.isEmpty { emptyState } }
        .fullScreenCover(item: $playing) { VideoPlayerScreen(item: $0) }
        .alert("Download problem", isPresented: errorBinding) {
            Button("OK", role: .cancel) { downloads.errorMessage = nil }
        } message: {
            Text(downloads.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { downloads.errorMessage != nil }, set: { if !$0 { downloads.errorMessage = nil } })
    }

    // MARK: - Sections

    private var summarySection: some View {
        let bytes = ByteCountFormatter.string(fromByteCount: downloads.totalBytes(for: kind), countStyle: .file)
        return Section {
            Label("\(records.count) saved · \(bytes) on this iPhone", systemImage: "internaldrive")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var activeSection: some View {
        Section("Downloading") {
            ForEach(active, id: \.item.id) { entry in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.item.name).font(.body.weight(.medium)).lineLimit(1)
                        ProgressView(value: entry.fraction).tint(theme.accent)
                    }
                    Button {
                        downloads.cancel(entry.item.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Cancel download of \(entry.item.name)")
                }
            }
        }
    }

    private var flatSection: some View {
        let sorted = records.sorted { $0.addedAt > $1.addedAt }
        return Section {
            ForEach(sorted) { record in
                row(record) { play(record, in: sorted) }
            }
        }
    }

    private var groupedSections: some View {
        let groups = Dictionary(grouping: records) { $0.groupId ?? $0.groupName ?? "other" }
        let ordered = groups.values
            .map { $0.sorted(by: Self.trackOrder) }
            .sorted { ($0.first?.groupName ?? "") < ($1.first?.groupName ?? "") }
        return ForEach(ordered, id: \.first?.id) { group in
            Section {
                ForEach(group) { record in
                    row(record) { play(record, in: group) }
                }
            } header: {
                groupHeader(group)
            }
        }
    }

    private func groupHeader(_ group: [DownloadRecord]) -> some View {
        HStack {
            Text(group.first?.groupName ?? "Other")
            Spacer()
            Menu {
                Button(role: .destructive) {
                    downloads.remove(group.map(\.id))
                } label: {
                    Label("Remove All", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Options for \(group.first?.groupName ?? "group")")
        }
    }

    private static func trackOrder(_ lhs: DownloadRecord, _ rhs: DownloadRecord) -> Bool {
        let left = (lhs.parentIndexNumber ?? 0, lhs.indexNumber ?? 0)
        let right = (rhs.parentIndexNumber ?? 0, rhs.indexNumber ?? 0)
        return left < right
    }

    private func row(_ record: DownloadRecord, onPlay: @escaping () -> Void) -> some View {
        Button(action: onPlay) {
            DownloadRow(record: record, isCurrent: audio.current?.id == record.id)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if record.library == .albums {
                Button {
                    audio.enqueue(record.mediaItem, using: store)
                } label: {
                    Label("Queue", systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .tint(theme.accent)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                downloads.remove([record.id])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Playback

    private func play(_ record: DownloadRecord, in list: [DownloadRecord]) {
        if record.library == .movies || record.library == .shows {
            playing = record.mediaItem
            return
        }
        let queue = list.map(\.mediaItem)
        guard let start = queue.firstIndex(where: { $0.id == record.id }) else { return }
        audio.play(queue, startAt: start, using: store)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.14)).frame(width: 120, height: 120)
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(theme.gradient)
            }
            Text("No downloads yet").font(.title3.weight(.bold))
            Text(hint)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    private var hint: String {
        switch kind {
        case .movies: "Open a movie and tap Download to watch it anywhere, even offline."
        case .shows: "Open a show and tap the download icon next to an episode, or download a whole season."
        case .albums: "Open an album and tap Download to listen without a connection."
        case .audiobooks: "Open an audiobook and tap Download to keep listening offline."
        }
    }
}

private struct DownloadRow: View {
    @Environment(\.appTheme) private var theme
    let record: DownloadRecord
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            artwork
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(isCurrent ? theme.accent : Color.primary)
                    .lineLimit(2)
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let progress = resumeFraction {
                    ProgressView(value: progress).tint(theme.accent).padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: isCurrent ? "waveform" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(theme.accent)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private var artwork: some View {
        let size: CGSize = switch record.library {
        case .movies: CGSize(width: 46, height: 68)
        case .shows: CGSize(width: 96, height: 54)
        case .albums, .audiobooks: CGSize(width: 56, height: 56)
        }
        let item = record.mediaItem
        return ArtworkView(url: record.artworkURL, seed: item.artworkSeed, symbol: item.symbol)
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var title: String {
        guard let number = record.indexNumber, record.library != .movies, record.library != .audiobooks else {
            return record.name
        }
        return "\(number). \(record.name)"
    }

    private var detail: String {
        var parts: [String] = []
        if record.library == .shows, let season = record.parentIndexNumber { parts.append("Season \(season)") }
        if record.library == .movies, let year = record.year { parts.append(String(year)) }
        if record.library == .audiobooks, let author = record.subtitle { parts.append(author) }
        if let duration = record.mediaItem.durationText { parts.append(duration) }
        parts.append(record.sizeText)
        return parts.joined(separator: " · ")
    }

    private var resumeFraction: Double? {
        guard record.library != .albums, let progress = record.mediaItem.progress, progress > 0.01 else { return nil }
        return min(progress, 1)
    }
}
