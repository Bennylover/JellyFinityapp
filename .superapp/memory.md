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
- Video quality: `JellyfinClient+Playback.resolveVideoPlayback` POSTs `/Items/{id}/PlaybackInfo` with an iPhone DeviceProfile (direct play mp4/m4v/mov h264/hevc; HLS fMP4 hevc/h264 transcode profile; subs = Encode). Direct play disabled when subtitle burned in or non-default audio; if AVPlayer fails on direct play it retries via server stream; if PlaybackInfo fails falls back to `videoStreamURL`. Logs "JellyFinity playback: <method>".

- Branding: user's jellyfish-infinity logo is `Image("JellyLogo")` (Connect + Home header) and AppIcon.png (resized to 1024 via sips once; generateAppIcon rejects non-1024 images).
- Downloads: `DownloadManager` (env, foreground URLSession, original file via `/Items/{id}/Download`, header auth), records in Application Support/Downloads/index.json, `MediaItem.localFileURL` makes Audio/Video players play offline. UI: toolbar link in `LibraryView` → `DownloadsView(kind:)`; `DownloadButton`/`DownloadIconButton` in detail views. Demo mode hides download buttons. Downloads pause when app is suspended; MKV etc. may not play in AVPlayer.

- Download conversion: iPhone can't transcode MKV itself; `JellyfinClient.downloadPlan` probes container/codecs and, if not AVPlayer-friendly, asks the server for `Videos/{id}/stream.mp4` (h264/aac) or `Audio/{id}/stream.mp3`. Toggle `jl.convertDownloads` (Settings, default on). Progress uses `countOfBytesClientExpectsToReceive` estimate.
- Artist page: `ArtistRoute` → `ArtistAlbumsView`, linked from album detail artist name (destination registered in LibraryView and HomeView).
- Artist albums: resolve artist id via `/Artists?searchTerm` (then `/Artists/AlbumArtists`), query `AlbumArtistIds`, verify album artist name in-app (servers may ignore name filters).
- Splash: `SplashView` overlay in `RootView` (~1.4 s, Reduce Motion aware); session restores underneath.
- Dynamic Island: uses system Now Playing (MPNowPlayingInfoCenter + remote commands + background audio), not a custom Live Activity (would duplicate system UI). Audiobooks get 15/30 s skips.

- Artist search: `JellyfinClient+Artists.swift` queries Artists/AlbumArtists, Artists, Search/Hints, Items(MusicArtist) in parallel with a minimal DTO, filters names locally; fallback filters full album-artist list.
- Server discovery: `ServerScanner` probes the device's /24 subnet on port 8096 (`System/Info/Public`); shown by `NearbyServersSection` in ConnectView. No UDP broadcast (needs multicast entitlement).

- Music queue: `AudioPlayer.entries` ([QueueEntry], `isQueued` = added by hand); `enqueue(_:playNext:using:)`, `upcoming`, `QueueView` sheet from NowPlaying. `.swipeToQueue` modifier on album track rows (+ leading swipe in Downloads). Recently played albums: `RecentMusicStore` (UserDefaults `jl.recentAlbums.v1`), recorded via `audio.play(..., album:)`; shown as `RecentMusicHero` in Music tab and `RecentAlbumsRow` on Home.

- Mac: Mac Catalyst was tried and REMOVED (user wants iOS-only): SUPPORTS_MACCATALYST NO, no entitlements file. Leftover `#if targetEnvironment(macCatalyst)` code (`MacWindow.swift`, context menu in `SwipeToQueue`) is inert. Publish error "No Accounts with App Store Connect Access" = needs Admin-role credentials to create a distribution cert (account only had a development cert).

## Pitfalls
- Offline: `DownloadManager+Offline` — `LibraryModel.reload` falls back to `offlineLibrary` (albums/shows grouped by groupId) on server error; album tracks/episodes fall back to `offlineChildren`; `localized()` swaps in local files (VideoPlayerScreen does it centrally; audio callers must call it).
- `CachedImage`: content closure may render nothing while loading; `.task` on an empty view never fires → keep a zero-size `Color.clear` anchor in its ZStack (this caused all-blank posters).
- Artist page hero: `ArtistHeroHeader` uses artist Backdrop → Primary → first album art; details via `client.artistDetails` (exact-name search hit).

- iOS 27 simulator runtime may be missing locally; build works but runApp can fail to boot.
