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

    func library(userId: String, kind: LibraryKind, sort: LibrarySort, search: String,
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
        return try await page(path: "Items", query: query)
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

    // MARK: - Streaming

    /// HLS stream that the server remuxes or transcodes into something AVPlayer can play.
    func videoStreamURL(itemId: String, playSessionId: String) -> URL? {
        guard let token else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemId)/master.m3u8"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [
            .init(name: "MediaSourceId", value: itemId), .init(name: "DeviceId", value: deviceId),
            .init(name: "PlaySessionId", value: playSessionId), .init(name: "api_key", value: token),
            .init(name: "VideoCodec", value: "h264,hevc"), .init(name: "AudioCodec", value: "aac,ac3,eac3"),
            .init(name: "TranscodingMaxAudioChannels", value: "6"),
            .init(name: "SegmentContainer", value: "mp4"), .init(name: "MinSegments", value: "1"),
            .init(name: "BreakOnNonKeyFrames", value: "true"),
            .init(name: "MaxStreamingBitrate", value: "40000000")
        ]
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
