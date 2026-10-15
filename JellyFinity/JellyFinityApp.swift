import SwiftUI

@main
struct JellyFinityApp: App {
    @State private var session = SessionStore()
    @State private var audio = AudioPlayer()
    @State private var downloads = DownloadManager()
    @AppStorage("jl.theme") private var themeRaw = AppTheme.aurora.rawValue
    @AppStorage("jl.appearance") private var appearanceRaw = AppearanceMode.system.rawValue

    private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .aurora }
    private var appearance: AppearanceMode { AppearanceMode(rawValue: appearanceRaw) ?? .system }

    var body: some Scene {
        WindowGroup {
            RootView()
                .macWindowMinimumSize()
                .environment(session)
                .environment(audio)
                .environment(downloads)
                .onAppear {
                    audio.onLocalProgress = { id, seconds in downloads.saveResume(id: id, seconds: seconds) }
                }
                .environment(\.appTheme, theme)
                .tint(theme.accent)
                .preferredColorScheme(appearance.colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(SessionStore.self) private var session
    @State private var showSplash = true

    var body: some View {
        ZStack {
            content
            if showSplash {
                SplashView { withAnimation(.easeInOut(duration: 0.45)) { showSplash = false } }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
    }

    private var content: some View {
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
    @State private var tab = 0

    var body: some View {
        TabView(selection: $tab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            LibraryView(kind: .movies)
                .tabItem { Label("Movies", systemImage: "film.stack") }
                .tag(1)
            LibraryView(kind: .shows)
                .tabItem { Label("Shows", systemImage: "tv") }
                .tag(2)
            LibraryView(kind: .albums)
                .tabItem { Label("Music", systemImage: "music.note") }
                .tag(3)
            LibraryView(kind: .audiobooks)
                .tabItem { Label("Books", systemImage: "headphones") }
                .tag(4)
        }
        .sensoryFeedback(.selection, trigger: tab)
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
