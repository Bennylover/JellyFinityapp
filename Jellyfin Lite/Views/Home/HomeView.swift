import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.appTheme) private var theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HomeHeader(name: session.displayName, server: session.serverName,
                               isDemo: session.phase == .demo)
                    if let error = session.loadError {
                        ErrorBanner(message: error)
                    }
                    mainContent
                }
                .padding(.vertical, 8)
                .padding(.bottom, 24)
            }
            .background(theme.background.ignoresSafeArea())
            .refreshable { await session.refresh() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: MediaItem.self) { MediaDetailView(item: $0) }
            .task {
                if session.snapshot.isEmpty { await session.refresh() }
            }
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        let snapshot = session.snapshot
        if snapshot.isEmpty && session.isLoading {
            ProgressView("Loading your library…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if snapshot.isEmpty {
            EmptyLibraryView()
        } else {
            sections(snapshot)
        }
    }

    @ViewBuilder
    private func sections(_ snapshot: LibrarySnapshot) -> some View {
        if let featured = snapshot.featured {
            NavigationLink(value: featured) { FeaturedHeroCard(item: featured) }
                .buttonStyle(.plain)
                .padding(.horizontal)
        }
        StatsRow(counts: snapshot.counts)
        if !snapshot.continueWatching.isEmpty {
            ContinueWatchingRow(items: snapshot.continueWatching)
        }
        LibraryMixCard(counts: snapshot.counts)
            .padding(.horizontal)
        if !snapshot.recentMovies.isEmpty {
            PosterRow(title: "Recently Added", subtitle: "Fresh on your server", items: snapshot.recentMovies)
        }
        if !snapshot.recentAlbums.isEmpty {
            AlbumRow(items: snapshot.recentAlbums)
        }
    }
}

private struct HomeHeader: View {
    @Environment(\.appTheme) private var theme
    let name: String
    let server: String
    let isDemo: Bool

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Label(server, systemImage: isDemo ? "sparkles" : "server.rack")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.accent.opacity(0.12), in: Capsule())
                Text("\(greeting),\n\(name)")
                    .font(.largeTitle.weight(.bold))
                    .lineLimit(2)
            }
            Spacer()
            Circle()
                .fill(theme.gradient)
                .frame(width: 48, height: 48)
                .overlay {
                    Text(String(name.prefix(1)).uppercased())
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
        }
        .padding(.horizontal)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "wifi.exclamationmark")
            .font(.footnote.weight(.medium))
            .foregroundStyle(.orange)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal)
    }
}

private struct EmptyLibraryView: View {
    @Environment(\.appTheme) private var theme

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.14)).frame(width: 130, height: 130)
                Image(systemName: "popcorn")
                    .font(.system(size: 50, weight: .semibold))
                    .foregroundStyle(theme.gradient)
            }
            Text("It's quiet in here")
                .font(.title2.weight(.bold))
            Text("Add movies, music or audiobooks to your Jellyfin libraries and they'll appear here. Pull down to refresh.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .cardSurface(radius: 28)
        .padding(.horizontal)
        .padding(.top, 20)
    }
}
