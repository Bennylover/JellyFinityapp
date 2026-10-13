import Foundation

enum SampleData {
    static let movies: [MediaItem] = [
        MediaItem(id: "m1", name: "Neon Tide", year: 2024, runtimeMinutes: 128, communityRating: 8.4, officialRating: "PG-13",
                  genres: ["Sci-Fi", "Thriller"],
                  overview: "A salvage diver discovers a glowing city beneath the Pacific — and the reason it was meant to stay buried."),
        MediaItem(id: "m2", name: "The Quiet Orbit", year: 2023, runtimeMinutes: 112, communityRating: 7.9, officialRating: "PG",
                  genres: ["Drama", "Space"], overview: "Alone on a research station, an astronaut starts receiving letters from home that haven't been written yet."),
        MediaItem(id: "m3", name: "Paper Lanterns", year: 2022, runtimeMinutes: 101, communityRating: 8.1, officialRating: "PG",
                  genres: ["Romance"], overview: "Two strangers meet every year at the same lantern festival, for ten years."),
        MediaItem(id: "m4", name: "Glass Harbor", year: 2024, runtimeMinutes: 134, communityRating: 7.6, officialRating: "R",
                  genres: ["Crime", "Mystery"], overview: "A detective returns to her coastal hometown to solve the case that made her leave."),
        MediaItem(id: "m5", name: "Echoes of Kepler", year: 2021, runtimeMinutes: 146, communityRating: 8.7, officialRating: "PG-13",
                  genres: ["Sci-Fi", "Adventure"], overview: "The first crew to a distant exoplanet finds footprints already there."),
        MediaItem(id: "m6", name: "Midnight Diner Club", year: 2023, runtimeMinutes: 96, communityRating: 7.4, officialRating: "PG-13",
                  genres: ["Comedy"], overview: "Four night-shift workers turn a failing diner into the city's most unlikely hotspot."),
        MediaItem(id: "m7", name: "Saltwater Hymn", year: 2020, runtimeMinutes: 118, communityRating: 8.0, officialRating: "PG",
                  genres: ["Drama", "Music"], overview: "A fisherman's daughter chases a choir audition across stormy islands.")
    ]

    static let continueWatching: [MediaItem] = [
        MediaItem(id: "c1", name: "The Quiet Orbit", subtitle: "Movie", year: 2023, runtimeMinutes: 112, progress: 0.62),
        MediaItem(id: "c2", name: "Departures", subtitle: "Northbound · S2 E4", kind: .episode, runtimeMinutes: 48, progress: 0.35),
        MediaItem(id: "c3", name: "Glass Harbor", subtitle: "Movie", year: 2024, runtimeMinutes: 134, progress: 0.18),
        MediaItem(id: "c4", name: "The Lighthouse Keeper", subtitle: "Coastline · S1 E7", kind: .episode, runtimeMinutes: 52, progress: 0.81)
    ]

    static let albums: [MediaItem] = [
        MediaItem(id: "a1", name: "Velvet Static", subtitle: "Luna Park", kind: .album, year: 2024),
        MediaItem(id: "a2", name: "Golden Hour FM", subtitle: "The Palms", kind: .album, year: 2023),
        MediaItem(id: "a3", name: "Low Tide Sessions", subtitle: "Mara Quinn", kind: .album, year: 2022),
        MediaItem(id: "a4", name: "City of Glass", subtitle: "Northern Lights Orchestra", kind: .album, year: 2024),
        MediaItem(id: "a5", name: "Paper Planes", subtitle: "Juniper & Co.", kind: .album, year: 2021)
    ]

    static let snapshot = LibrarySnapshot(
        featured: movies[0],
        continueWatching: continueWatching,
        recentMovies: Array(movies.dropFirst()),
        recentAlbums: albums,
        counts: LibraryCounts(movies: 248, series: 42, albums: 186, audiobooks: 37)
    )

    /// Gradient pairs used for artwork when no server image is available.
    static let palettes: [(UInt32, UInt32)] = [
        (0x6A3DE8, 0x00B4D8), (0xF2541B, 0xB5179E), (0x0B8457, 0x2E86DE),
        (0x3A0CA3, 0xF72585), (0xE09F3E, 0x9E2A2B), (0x1D3557, 0x457B9D),
        (0x7209B7, 0x4CC9F0), (0x2D6A4F, 0x95D5B2)
    ]
}
