import SwiftUI

@main
struct JellyfinLiteApp: App {
    @State private var session = SessionStore()
    @State private var audio = AudioPlayer()
    @AppStorage("jl.theme") private var themeRaw = AppTheme.aurora.rawValue
    @AppStorage("jl.appearance") private var appearanceRaw = AppearanceMode.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .aurora }
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(audio)
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
    @Environment(AudioPlayer.self) private var audio

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            LibraryView(kind: .movies)
                .tabItem { Label("Movies", systemImage: "film.stack") }
            LibraryView(kind: .shows)
                .tabItem { Label("Shows", systemImage: "tv") }
            LibraryView(kind: .albums)
                .tabItem { Label("Music", systemImage: "music.note") }
            LibraryView(kind: .audiobooks)
                .tabItem { Label("Books", systemImage: "headphones") }
        }
        .alert("Can't play that", isPresented: errorBinding) {
            Button("OK", role: .cancel) { audio.errorMessage = nil }
        } message: {
            Text(audio.errorMessage ?? "")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { audio.errorMessage != nil }, set: { if !$0 { audio.errorMessage = nil } })
    }
}
