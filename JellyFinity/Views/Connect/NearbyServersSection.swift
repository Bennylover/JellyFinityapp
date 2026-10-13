import SwiftUI

/// Lists Jellyfin servers found on the local network; tap one to skip typing its address.
struct NearbyServersSection: View {
    @Environment(\.appTheme) private var theme
    let onSelect: (NearbyServer) -> Void

    @State private var servers: [NearbyServer] = []
    @State private var isScanning = false
    @State private var scanID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if servers.isEmpty {
                statusRow
            } else {
                ForEach(servers) { server in row(server) }
            }
        }
        .task(id: scanID) { await scan() }
    }

    private var header: some View {
        HStack {
            Label("On your network", systemImage: "wifi")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if isScanning {
                ProgressView().controlSize(.small)
            } else {
                Button("Scan again") { scanID += 1 }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var statusRow: some View {
        let text = isScanning ? "Looking for Jellyfin servers…" : "No servers found. Make sure you're on the same Wi‑Fi, or type the address below."
        return Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(theme.elevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ server: NearbyServer) -> some View {
        let address = server.url.host().map { "\($0):\(server.url.port ?? 8096)" } ?? server.url.absoluteString
        return Button { onSelect(server) } label: {
            HStack(spacing: 12) {
                Image(systemName: "server.rack")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(theme.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name).font(.headline).foregroundStyle(.primary)
                    Text(server.version.map { "\(address) · Jellyfin \($0)" } ?? address)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private func scan() async {
        isScanning = true
        let found = await ServerScanner.scan()
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { servers = found }
        isScanning = false
    }
}
