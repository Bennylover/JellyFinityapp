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

## Pitfalls

- iOS 27 simulator runtime may be missing locally; build works but runApp can fail to boot.
