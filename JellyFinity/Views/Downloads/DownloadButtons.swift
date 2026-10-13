import SwiftUI

/// Full-width download control for one or more items (a movie, an audiobook, an album or a season).
struct DownloadButton: View {
    @Environment(SessionStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.appTheme) private var theme
    let items: [MediaItem]
    var group: MediaItem? = nil
    var idleTitle = "Download"

    private var states: [DownloadManager.State] { items.map { downloads.state(for: $0.id) } }
    private var doneCount: Int { states.filter { $0 == .done }.count }
    private var activeFractions: [Double] {
        states.compactMap { if case .downloading(let value) = $0 { value } else { nil } }
    }

    var body: some View {
        if !store.isDemo, !items.isEmpty {
            if doneCount == items.count {
                doneMenu
            } else if !activeFractions.isEmpty {
                activeButton
            } else {
                idleButton
            }
        }
    }

    private var idleButton: some View {
        Button {
            downloads.download(items, group: group, store: store)
        } label: {
            chipLabel(idleTitle, symbol: "arrow.down.circle")
        }
        .buttonStyle(.plain)
    }

    private var activeButton: some View {
        let total = Double(items.count)
        let finished = Double(doneCount) + activeFractions.reduce(0, +)
        let fraction = min(finished / total, 1)
        let title = "Downloading \(Int(fraction * 100))%"
        return Button {
            for item in items { downloads.cancel(item.id) }
        } label: {
            HStack(spacing: 10) {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .tint(theme.accent)
                Text(title)
                Text("Tap to cancel").font(.caption).foregroundStyle(.secondary)
            }
            .font(.headline)
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Downloading, \(Int(fraction * 100)) percent. Double tap to cancel.")
    }

    private var doneMenu: some View {
        Menu {
            Button(role: .destructive) {
                downloads.remove(items.map(\.id))
            } label: {
                Label("Remove Download", systemImage: "trash")
            }
        } label: {
            chipLabel("Downloaded", symbol: "checkmark.circle.fill")
        }
    }

    private func chipLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Compact per-row download control (episodes and tracks).
struct DownloadIconButton: View {
    @Environment(SessionStore.self) private var store
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.appTheme) private var theme
    let item: MediaItem
    var group: MediaItem? = nil

    var body: some View {
        content
            .foregroundStyle(theme.accent)
            .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if !store.isDemo {
            switch downloads.state(for: item.id) {
            case .none:
                Button {
                    downloads.download([item], group: group, store: store)
                } label: {
                    Image(systemName: "arrow.down.circle").font(.title3)
                }
                .accessibilityLabel("Download \(item.name)")
            case .downloading(let fraction):
                Button {
                    downloads.cancel(item.id)
                } label: {
                    ZStack {
                        ProgressView(value: fraction).progressViewStyle(.circular).scaleEffect(0.8)
                        Image(systemName: "stop.fill").font(.system(size: 8))
                    }
                    .frame(width: 26, height: 26)
                }
                .accessibilityLabel("Cancel download of \(item.name)")
            case .done:
                Menu {
                    Button(role: .destructive) {
                        downloads.remove([item.id])
                    } label: {
                        Label("Remove Download", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill").font(.title3)
                }
                .accessibilityLabel("\(item.name) is downloaded")
            }
        }
    }
}
