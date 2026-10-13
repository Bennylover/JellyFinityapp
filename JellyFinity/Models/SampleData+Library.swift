import Foundation

extension SampleData {
    /// Public Apple test stream so demo mode can show the video player for real.
    static let demoVideoURL = URL(string: "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_adv_example_hevc/master.m3u8")

    static let series: [MediaItem] = [
        MediaItem(id: "s1", name: "Northbound", kind: .series, year: 2023, communityRating: 8.5, officialRating: "TV-14",
                  genres: ["Drama", "Mystery"], overview: "A ferry crew on the edge of the Arctic circle keeps finding passengers who were never on the manifest."),
        MediaItem(id: "s2", name: "Coastline", kind: .series, year: 2022, communityRating: 8.1, officialRating: "TV-PG",
                  genres: ["Drama"], overview: "Four generations of a lighthouse family navigate love, loss and a changing sea."),
        MediaItem(id: "s3", name: "Late Shift Labs", kind: .series, year: 2024, communityRating: 7.8, officialRating: "TV-14",
                  genres: ["Comedy", "Sci-Fi"], overview: "Night-shift interns at a research lab accidentally invent something wonderful."),
        MediaItem(id: "s4", name: "The Long Table", kind: .series, year: 2021, communityRating: 8.9, officialRating: "TV-MA",
                  genres: ["Drama", "Food"], overview: "One restaurant, one kitchen, one very tense dinner service per episode.")
    ]

    static let audiobooks: [MediaItem] = [
        MediaItem(id: "b1", name: "The Salt Road", subtitle: "Imani Okoye", kind: .audiobook, year: 2023,
                  overview: "A cartographer retraces her grandmother's caravan route across the Sahara.", durationSeconds: 39_600),
        MediaItem(id: "b2", name: "Small Hours", subtitle: "Theo Lindqvist", kind: .audiobook, year: 2022,
                  overview: "Twelve stories that all take place between 2 and 4 a.m.", durationSeconds: 28_800),
        MediaItem(id: "b3", name: "A Field Guide to Clouds", subtitle: "Priya Raman", kind: .audiobook, year: 2024,
                  overview: "A gentle, funny, curious tour of the sky above you.", durationSeconds: 21_600),
        MediaItem(id: "b4", name: "Orbit Station Nine", subtitle: "Mateo Vance", kind: .audiobook, year: 2021,
                  overview: "A locked-room mystery on a space station with seven suspects and no gravity.", durationSeconds: 46_800)
    ]

    static func items(for kind: LibraryKind) -> [MediaItem] {
        switch kind {
        case .movies: movies
        case .shows: series
        case .albums: albums
        case .audiobooks: audiobooks
        }
    }

    static func seasons(of series: MediaItem) -> [MediaItem] {
        (1...2).map { number in
            MediaItem(id: "\(series.id)-s\(number)", name: "Season \(number)", kind: .season,
                      seriesId: series.id, indexNumber: number)
        }
    }

    static func episodes(of season: MediaItem) -> [MediaItem] {
        let titles = ["Pilot", "The Long Way Round", "Static", "Open Water", "What the Tide Brings", "Last Light"]
        return titles.enumerated().map { offset, title in
            MediaItem(id: "\(season.id)-e\(offset + 1)", name: title, subtitle: season.name, kind: .episode,
                      runtimeMinutes: 44 + offset * 2,
                      overview: "A turning point for the crew as secrets surface and loyalties are tested.",
                      seriesId: season.seriesId, indexNumber: offset + 1,
                      parentIndexNumber: season.indexNumber, durationSeconds: Double((44 + offset * 2) * 60))
        }
    }

    static func tracks(of album: MediaItem) -> [MediaItem] {
        let titles = ["Opening", "Neon Rain", "Slow Burn", "Paper Skies", "Interlude", "Afterglow", "Closing Time"]
        return titles.enumerated().map { offset, title in
            MediaItem(id: "\(album.id)-t\(offset + 1)", name: title, subtitle: album.subtitle, kind: .track,
                      indexNumber: offset + 1, durationSeconds: Double(170 + offset * 17))
        }
    }
}
