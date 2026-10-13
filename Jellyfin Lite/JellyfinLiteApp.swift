import SwiftUI

@main
struct JellyfinLiteApp: App {
    @State private var session = SessionStore()
    @AppStorage("jl.theme") private var themeRaw = AppTheme.aurora.rawValue
    @AppStorage("jl.appearance") private var appearanceRaw = AppearanceMode.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .aurora }
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(\.appTheme, theme)
                .tint(theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.phase == .signedOut {
                ConnectView()
                    .transition(.opacity)
            } else {
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.phase)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            MoviesView()
                .tabItem { Label("Movies", systemImage: "film.stack") }
            MusicView()
                .tabItem { Label("Music", systemImage: "music.note") }
            AudiobooksView()
                .tabItem { Label("Books", systemImage: "headphones") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "paintpalette") }
        }
    }
}
