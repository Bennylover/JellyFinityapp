import Foundation

/// Body for Jellyfin's playback reporting endpoints.
private struct PlaybackReport: Encodable {
    let itemId: String
    let mediaSourceId: String
    let playSessionId: String
    let positionTicks: Int64
    let isPaused: Bool

    enum CodingKeys: String, CodingKey {
        case itemId = "ItemId", mediaSourceId = "MediaSourceId", playSessionId = "PlaySessionId"
        case positionTicks = "PositionTicks", isPaused = "IsPaused"
    }
}

enum PlaybackStage: String, Sendable {
    case started = "Sessions/Playing"
    case progress = "Sessions/Playing/Progress"
    case stopped = "Sessions/Playing/Stopped"
}

extension JellyfinClient {
    // MARK: - Browsing

    func library(userId: String, kind: LibraryKind, sort: LibrarySort, search: String, genre: String? = nil,
                 startIndex: Int, limit: Int) async throws -> (items: [MediaItem], total: Int) {
        var query: [URLQueryItem] = [
            .init(name: "userId", value: userId), .init(name: "IncludeItemTypes", value: kind.includeTypes),
            .init(name: "Recursive", value: "true"), .init(name: "SortBy", value: sort.sortBy),
            .init(name: "SortOrder", value: sort.ascending ? "Ascending" : "Descending"),
            .init(name: "StartIndex", value: String(startIndex)), .init(name: "Limit", value: String(limit)),
            .init(name: "Fields", value: "Genres")
        ]
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { query.append(.init(name: "SearchTerm", value: trimmed)) }
        if let genre, !genre.isEmpty { query.append(.init(name: "Genres", value: genre)) }
        return try await page(path: "Items", query: query)
    }

    /// Genre names available in a library, for the genre filter.
    func genres(userId: String, kind: LibraryKind) async throws -> [String] {
        let path = kind == .albums ? "MusicGenres" : "Genres"
        let data = try await send(path, query: [
            .init(name: "userId", value: userId), .init(name: "IncludeItemTypes", value: kind.includeTypes),
            .init(name: "Recursive", value: "true"), .init(name: "SortBy", value: "SortName")
        ])
        let response = try decode(ItemsResponse.self, from: data)
        return response.items.compactMap(\.name).filter { !$0.isEmpty }
    }

    func detail(userId: String, itemId: String) async throws -> MediaItem {
        let data = try await send("Users/\(userId)/Items/\(itemId)")
        return map(try decode(ItemDTO.self, from: data))
    }

    func seasons(userId: String, seriesId: String) async throws -> [MediaItem] {
        try await page(path: "Shows/\(seriesId)/Seasons", query: [.init(name: "userId", value: userId)]).items
    }

    func episodes(userId: String, seriesId: String, seasonId: String) async throws -> [MediaItem] {
        try await page(path: "Shows/\(seriesId)/Episodes", query: [
            .init(name: "userId", value: userId), .init(name: "seasonId", value: seasonId),
            .init(name: "Fields", value: "Overview")
        ]).items
    }

    func tracks(userId: String, albumId: String) async throws -> [MediaItem] {
        try await page(path: "Items", query: [
            .init(name: "userId", value: userId), .init(name: "ParentId", value: albumId),
            .init(name: "IncludeItemTypes", value: "Audio"), .init(name: "Recursive", value: "true"),
            .init(name: "SortBy", value: "ParentIndexNumber,IndexNumber,SortName")
        ]).items
    }

    /// The most recently watched title of a kind (movie or episode), or nil if nothing was played yet.
    func lastWatched(userId: String, types: String) async throws -> MediaItem? {
        let result = try await page(path: "Items", query: [
            .init(name: "userId", value: userId), .init(name: "IncludeItemTypes", value: types),
            .init(name: "Recursive", value: "true"), .init(name: "SortBy", value: "DatePlayed"),
            .init(name: "SortOrder", value: "Descending"), .init(name: "Limit", value: "1"),
            .init(name: "Fields", value: "Genres,Overview")
        ])
        return result.items.first(where: \.hasWatchHistory)
    }

    func mediaTracks(userId: String, itemId: String) async throws -> MediaTracks {
        let data = try await send("Users/\(userId)/Items/\(itemId)")
        let streams = try decode(ItemDTO.self, from: data).mediaStreams ?? []
        var tracks = MediaTracks()
        for stream in streams {
            let fallback = stream.language?.uppercased() ?? "Track \(stream.index)"
            let title = stream.displayTitle ?? stream.title ?? fallback
            switch stream.type {
            case "Audio":
                tracks.audio.append(MediaTrack(index: stream.index, kind: .audio, title: title,
                                               isDefault: stream.isDefault ?? false))
            case "Subtitle":
                tracks.subtitles.append(MediaTrack(index: stream.index, kind: .subtitle, title: title,
                                                   isDefault: stream.isDefault ?? false))
            default:
                break
            }
        }
        return tracks
    }

    // MARK: - Streaming

    /// HLS stream that the server remuxes or transcodes into something AVPlayer can play.
    /// A chosen subtitle is burned into the picture so it works for every subtitle format.
    func videoStreamURL(itemId: String, playSessionId: String,
                        audioIndex: Int? = nil, subtitleIndex: Int? = nil) -> URL? {
        guard let token else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemId)/master.m3u8"),
                                  resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = [
            .init(name: "MediaSourceId", value: itemId), .init(name: "DeviceId", value: deviceId),
            .init(name: "PlaySessionId", value: playSessionId), .init(name: "api_key", value: token),
            .init(name: "VideoCodec", value: "h264,hevc"), .init(name: "AudioCodec", value: "aac,ac3,eac3"),
            .init(name: "TranscodingMaxAudioChannels", value: "6"),
            .init(name: "SegmentContainer", value: "mp4"), .init(name: "MinSegments", value: "1"),
            .init(name: "BreakOnNonKeyFrames", value: "true"),
            .init(name: "MaxStreamingBitrate", value: "40000000")
        ]
        if let audioIndex { query.append(.init(name: "AudioStreamIndex", value: String(audioIndex))) }
        if let subtitleIndex {
            query.append(.init(name: "SubtitleStreamIndex", value: String(subtitleIndex)))
            query.append(.init(name: "SubtitleMethod", value: "Encode"))
        }
        comps?.queryItems = query
        return comps?.url
    }

    func audioStreamURL(itemId: String, userId: String) -> URL? {
        guard let token else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Audio/\(itemId)/universal"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            .init(name: "UserId", value: userId), .init(name: "DeviceId", value: deviceId),
            .init(name: "api_key", value: token),
            .init(name: "Container", value: "mp3,aac,m4a|aac,m4b|aac,flac,wav"),
            .init(name: "AudioCodec", value: "aac"), .init(name: "TranscodingContainer", value: "ts"),
            .init(name: "TranscodingProtocol", value: "hls"),
            .init(name: "MaxStreamingBitrate", value: "140000000")
        ]
        return comps?.url
    }

    // MARK: - Playback reporting

    /// Best-effort progress report so Jellyfin can resume playback on any device.
    func report(_ stage: PlaybackStage, itemId: String, playSessionId: String,
                positionSeconds: Double, isPaused: Bool) async {
        let body = PlaybackReport(itemId: itemId, mediaSourceId: itemId, playSessionId: playSessionId,
                                  positionTicks: Int64(max(positionSeconds, 0) * 10_000_000), isPaused: isPaused)
        guard let data = try? JSONEncoder().encode(body) else { return }
        _ = try? await send(stage.rawValue, method: "POST", body: data)
    }
}
