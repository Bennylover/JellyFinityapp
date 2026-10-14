import SwiftUI

/// "Up Next": what is playing now and what comes after. Reorder, remove or jump to a song.
struct QueueView: View {
    @Environment(AudioPlayer.self) private var audio
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    private var queued: [QueueEntry] { audio.upcoming.filter(\.isQueued) }
    private var rest: [QueueEntry] { audio.upcoming.filter { !$0.isQueued } }

    var body: some View {
        NavigationStack {
            List {
                if let current = audio.current { nowPlayingSection(current) }
                if audio.upcoming.isEmpty {
                    emptySection
                } else {
                    upcomingSection
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("Up Next")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if !audio.upcoming.isEmpty {
                EditButton()
                Button("Clear", role: .destructive) { audio.clearUpcoming() }
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Done") { dismiss() }.fontWeight(.semibold)
        }
    }

    private func nowPlayingSection(_ item: MediaItem) -> some View {
        Section("Now Playing") {
            QueueRow(item: item, isCurrent: true)
        }
    }

    private var upcomingSection: some View {
        Section {
            ForEach(audio.upcoming) { entry in
                Button { audio.jump(to: entry.id) } label: {
                    QueueRow(item: entry.item, isCurrent: false, isQueued: entry.isQueued)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        audio.removeUpcoming(entry.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                }
            }
            .onMove { audio.moveUpcoming(from: $0, to: $1) }
        } header: {
            Text(queued.isEmpty ? "Next Up" : "Next Up · \(queued.count) queued by you")
        } footer: {
            Text("Tap Edit to reorder. Swipe left to remove.")
        }
    }

    private var emptySection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.largeTitle)
                    .foregroundStyle(theme.accent)
                Text("Nothing queued")
                    .font(.headline)
                Text("Swipe a song in any album to line it up next.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        }
    }
}

private struct QueueRow: View {
    @Environment(\.appTheme) private var theme
    let item: MediaItem
    let isCurrent: Bool
    var isQueued = false

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol, showsSymbol: false)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? theme.accent : Color.primary)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if isQueued {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel("Added by you")
            }
            if isCurrent {
                Image(systemName: "waveform").foregroundStyle(theme.accent)
            }
        }
        .contentShape(Rectangle())
    }
}
