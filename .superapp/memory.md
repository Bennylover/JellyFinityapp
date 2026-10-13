# Project Memory

Notes the coding agent keeps between sessions. Source code, project configuration, git state, and build output are more authoritative than this file — verify against them before relying on a note.

## Project

Generated iOS SwiftUI application.

- SwiftUI
- XcodeGen project generation: `project.yml` is the project config; do not edit `.xcodeproj/project.pbxproj` directly
- Local state/storage unless the user asks for a backend
- App source lives in the generated app folder named by the project title

Prefer native Apple-like UI. Avoid web-dashboard-style components unless explicitly requested.

## Decisions

- Jellyfin client: `JellyfinClient` (URLSession, `/Items`, `/Items/Counts`, `/Users/AuthenticateByName`), token in Keychain, session JSON in UserDefaults (`jl.session`), demo mode flag `jl.demo`.
- Themes: `AppTheme` (aurora/ember/jade) with dynamic light/dark colors; `@AppStorage("jl.theme")` + `jl.appearance`; injected via `\.appTheme` env.
- Tabs: Home, Movies, Shows, Music, Books (real `LibraryView`s); Settings is a sheet from the Home avatar.
- App renamed to JellyFinity (folder `JellyFinity/`, bundle id still com.superapp.jellyfinlite).
- Video tracks: audio/subtitle chosen in `VideoPlayerScreen` menu; changing re-requests HLS with AudioStreamIndex / SubtitleStreamIndex (+SubtitleMethod=Encode, burned in).
- Movies/Shows libraries show `RecentHeroHeader` (last watched via SortBy=DatePlayed, Limit 1).
- ATS: only NSAllowsLocalNetworking; remote servers need HTTPS.

- Branding: user's jellyfish-infinity logo is `Image("JellyLogo")` (Connect + Home header) and AppIcon.png (resized to 1024 via sips once; generateAppIcon rejects non-1024 images).
- Downloads: `DownloadManager` (env, foreground URLSession, original file via `/Items/{id}/Download`, header auth), records in Application Support/Downloads/index.json, `MediaItem.localFileURL` makes Audio/Video players play offline. UI: toolbar link in `LibraryView` → `DownloadsView(kind:)`; `DownloadButton`/`DownloadIconButton` in detail views. Demo mode hides download buttons. Downloads pause when app is suspended; MKV etc. may not play in AVPlayer.

- Download conversion: iPhone can't transcode MKV itself; `JellyfinClient.downloadPlan` probes container/codecs and, if not AVPlayer-friendly, asks the server for `Videos/{id}/stream.mp4` (h264/aac) or `Audio/{id}/stream.mp3`. Toggle `jl.convertDownloads` (Settings, default on). Progress uses `countOfBytesClientExpectsToReceive` estimate.
- Artist page: `ArtistRoute` → `ArtistAlbumsView`, linked from album detail artist name (destination registered in LibraryView and HomeView).
- Artist albums: resolve artist id via `/Artists?searchTerm` (then `/Artists/AlbumArtists`), query `AlbumArtistIds`, verify album artist name in-app (servers may ignore name filters).
- Splash: `SplashView` overlay in `RootView` (~1.4 s, Reduce Motion aware); session restores underneath.
- Dynamic Island: uses system Now Playing (MPNowPlayingInfoCenter + remote commands + background audio), not a custom Live Activity (would duplicate system UI). Audiobooks get 15/30 s skips.

## Pitfalls

- iOS 27 simulator runtime may be missing locally; build works but runApp can fail to boot.
