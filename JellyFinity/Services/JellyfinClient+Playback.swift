import Foundation

/// The stream the server picked for this iPhone: the original file, a lossless remux, or a transcode.
struct VideoPlayback: Sendable {
    enum Method: String, Sendable { case directPlay = "DirectPlay", directStream = "DirectStream", transcode = "Transcode" }

    let url: URL
    let playSessionId: String
    let mediaSourceId: String
    let method: Method
}

private struct PlaybackInfoResponse: Decodable {
    struct Source: Decodable {
        let id: String?
        let container: String?
        let supportsDirectPlay: Bool?
        let supportsDirectStream: Bool?
        let transcodingUrl: String?
        let eTag: String?

        enum CodingKeys: String, CodingKey {
            case id = "Id", container = "Container", supportsDirectPlay = "SupportsDirectPlay"
            case supportsDirectStream = "SupportsDirectStream", transcodingUrl = "TranscodingUrl", eTag = "ETag"
        }
    }

    let mediaSources: [Source]?
    let playSessionId: String?

    enum CodingKeys: String, CodingKey {
        case mediaSources = "MediaSources", playSessionId = "PlaySessionId"
    }
}

extension JellyfinClient {
    /// Negotiates playback with the server, Swiftfin-style: we describe what iPhone plays natively and the
    /// server sends the untouched file when it can, remuxes without re-encoding when only the container is
    /// a problem (e.g. MKV), and transcodes at the user's bitrate only as a last resort.
    func resolveVideoPlayback(itemId: String, userId: String, audioIndex: Int?, subtitleIndex: Int?,
                              audioIsDefault: Bool, allowDirectPlay: Bool = true) async throws -> VideoPlayback {
        // Burned-in subtitles or a non-default audio track need the server to build the stream for us.
        let canDirectPlay = allowDirectPlay && subtitleIndex == nil && audioIsDefault
        var body: [String: Any] = [
            "UserId": userId,
            "MediaSourceId": itemId,
            "MaxStreamingBitrate": Self.maxStreamingBitrate,
            "EnableDirectPlay": canDirectPlay,
            "EnableDirectStream": true,
            "EnableTranscoding": true,
            "AllowVideoStreamCopy": true,
            "AllowAudioStreamCopy": true,
            "AutoOpenLiveStream": true,
            "SubtitleStreamIndex": subtitleIndex ?? -1,
            "DeviceProfile": Self.iPhoneDeviceProfile(maxBitrate: Self.maxStreamingBitrate)
        ]
        if let audioIndex { body["AudioStreamIndex"] = audioIndex }
        let payload = try JSONSerialization.data(withJSONObject: body)

        let data = try await send("Items/\(itemId)/PlaybackInfo",
                                  query: [.init(name: "userId", value: userId)], method: "POST", body: payload)
        let info = try decode(PlaybackInfoResponse.self, from: data)
        guard let source = info.mediaSources?.first else { throw ClientError.decoding }
        let sessionId = info.playSessionId ?? UUID().uuidString
        let sourceId = source.id ?? itemId

        if canDirectPlay, source.supportsDirectPlay == true,
           let url = directPlayURL(itemId: itemId, source: source, playSessionId: sessionId) {
            NSLog("JellyFinity playback: DirectPlay (%@)", source.container ?? "?")
            return VideoPlayback(url: url, playSessionId: sessionId, mediaSourceId: sourceId, method: .directPlay)
        }
        guard let path = source.transcodingUrl, let url = absoluteStreamURL(path) else {
            throw ClientError.decoding
        }
        let method: VideoPlayback.Method = source.supportsDirectStream == true ? .directStream : .transcode
        NSLog("JellyFinity playback: %@ (%@)", method.rawValue, source.container ?? "?")
        return VideoPlayback(url: url, playSessionId: sessionId, mediaSourceId: sourceId, method: method)
    }

    private func directPlayURL(itemId: String, source: PlaybackInfoResponse.Source, playSessionId: String) -> URL? {
        guard let token else { return nil }
        var comps = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemId)/stream"),
                                  resolvingAgainstBaseURL: false)
        var query: [URLQueryItem] = [
            .init(name: "static", value: "true"),
            .init(name: "MediaSourceId", value: source.id ?? itemId),
            .init(name: "PlaySessionId", value: playSessionId),
            .init(name: "DeviceId", value: deviceId),
            .init(name: "api_key", value: token)
        ]
        if let container = source.container { query.append(.init(name: "Container", value: container)) }
        if let tag = source.eTag { query.append(.init(name: "Tag", value: tag)) }
        comps?.queryItems = query
        return comps?.url
    }

    /// The server hands back a path relative to its root; keep any base path (reverse proxies) and the token.
    private func absoluteStreamURL(_ path: String) -> URL? {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        var full = base + (path.hasPrefix("/") ? path : "/" + path)
        let lower = full.lowercased()
        if let token, !lower.contains("api_key=") && !lower.contains("apikey=") {
            full += (full.contains("?") ? "&" : "?") + "api_key=" + token
        }
        return URL(string: full)
    }

    /// What AVPlayer on iPhone handles natively, in Jellyfin's DeviceProfile format.
    static func iPhoneDeviceProfile(maxBitrate: Int) -> [String: Any] {
        let directAudio = "aac,ac3,eac3,alac,flac,mp3"
        let hlsAudio = "aac,ac3,eac3,alac,flac"
        return [
            "Name": "JellyFinity iPhone",
            "MaxStreamingBitrate": maxBitrate,
            "MaxStaticBitrate": maxBitrate,
            "MusicStreamingTranscodingBitrate": 384_000,
            "DirectPlayProfiles": [
                ["Type": "Video", "Container": "mp4,m4v,mov", "VideoCodec": "hevc,h264", "AudioCodec": directAudio]
            ],
            "TranscodingProfiles": [
                ["Type": "Video", "Container": "mp4", "Protocol": "hls", "Context": "Streaming",
                 "VideoCodec": "hevc,h264", "AudioCodec": hlsAudio, "MaxAudioChannels": "6",
                 "MinSegments": 2, "BreakOnNonKeyFrames": true, "CopyTimestamps": false]
            ],
            "ContainerProfiles": [],
            "CodecProfiles": [
                ["Type": "Video", "Codec": "hevc", "Conditions": [
                    ["Condition": "EqualsAny", "Property": "VideoCodecTag", "Value": "hvc1|dvh1", "IsRequired": false],
                    ["Condition": "LessThanEqual", "Property": "VideoBitDepth", "Value": "10", "IsRequired": false]
                ]],
                ["Type": "Video", "Codec": "h264", "Conditions": [
                    ["Condition": "LessThanEqual", "Property": "VideoBitDepth", "Value": "8", "IsRequired": false],
                    ["Condition": "NotEquals", "Property": "IsAnamorphic", "Value": "true", "IsRequired": false]
                ]]
            ],
            "SubtitleProfiles": [
                ["Format": "srt", "Method": "Encode"], ["Format": "ass", "Method": "Encode"],
                ["Format": "ssa", "Method": "Encode"], ["Format": "vtt", "Method": "Encode"],
                ["Format": "subrip", "Method": "Encode"], ["Format": "pgssub", "Method": "Encode"],
                ["Format": "dvdsub", "Method": "Encode"], ["Format": "dvbsub", "Method": "Encode"]
            ]
        ]
    }
}
