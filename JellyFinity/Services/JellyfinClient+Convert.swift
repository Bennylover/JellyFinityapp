import Foundation

/// A download request plus a rough size guess, used for progress when the server converts on the fly.
struct DownloadPlan: Sendable {
    let request: URLRequest
    let expectedBytes: Int64?
    let isConverted: Bool
}

extension JellyfinClient {
    private static let videoBitrate = 6_000_000
    private static let audioBitrateForVideo = 192_000
    private static let musicBitrate = 256_000

    // MARK: - Artists

    /// Albums by one artist, newest first. Falls back to albums the artist only appears on.
    func artistAlbums(userId: String, artist: String) async throws -> [MediaItem] {
        let base: [URLQueryItem] = [
            .init(name: "userId", value: userId), .init(name: "IncludeItemTypes", value: "MusicAlbum"),
            .init(name: "Recursive", value: "true"), .init(name: "SortBy", value: "ProductionYear,SortName"),
            .init(name: "SortOrder", value: "Descending"), .init(name: "Fields", value: "Genres")
        ]
        let wanted = Self.normalized(artist)
        if let artistId = try? await artistId(named: artist, userId: userId) {
            let primary = try await items(query: base + [.init(name: "AlbumArtistIds", value: artistId)])
            let ownAlbums = primary.filter { Self.album($0, matches: wanted) }
            if !ownAlbums.isEmpty { return ownAlbums }
            // An empty result means the server honoured the id filter, so "appears on" albums can be trusted.
            if primary.isEmpty {
                let appearsOn = try await items(query: base + [.init(name: "ArtistIds", value: artistId)])
                if !appearsOn.isEmpty { return appearsOn }
            }
        }
        // Last resort: search by name and keep only albums whose artist really matches.
        let searched = try await items(query: base + [.init(name: "searchTerm", value: artist), .init(name: "Limit", value: "200")])
        let byName = try await items(query: base + [.init(name: "AlbumArtists", value: artist)])
        var seen = Set<String>()
        return (byName + searched).filter { Self.album($0, matches: wanted) && seen.insert($0.id).inserted }
    }

    /// Finds the server id of an artist by exact (case-insensitive) name.
    private func artistId(named artist: String, userId: String) async throws -> String? {
        let wanted = Self.normalized(artist)
        let query: [URLQueryItem] = [
            .init(name: "userId", value: userId), .init(name: "searchTerm", value: artist), .init(name: "Limit", value: "25")
        ]
        let found = try await page(path: "Artists", query: query).items
        if let exact = found.first(where: { Self.normalized($0.name) == wanted }) { return exact.id }
        let albumArtists = try await page(path: "Artists/AlbumArtists", query: query).items
        return albumArtists.first(where: { Self.normalized($0.name) == wanted })?.id
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when the album's artist line names this artist (handles "A, B" and "A feat. B").
    private static func album(_ album: MediaItem, matches wanted: String) -> Bool {
        guard let line = album.subtitle else { return false }
        let full = normalized(line)
        if full == wanted { return true }
        let parts = full.components(separatedBy: CharacterSet(charactersIn: ",;&/")).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return parts.contains(wanted) || full.hasPrefix(wanted + " feat")
    }

    // MARK: - Converted downloads

    /// Chooses between the original file and a server-converted copy that iPhone can always play.
    /// If the server can't be asked, the original file is downloaded.
    func downloadPlan(userId: String, item: MediaItem, convertIfNeeded: Bool) async -> DownloadPlan {
        let original = DownloadPlan(request: downloadRequest(itemId: item.id), expectedBytes: nil, isConverted: false)
        guard convertIfNeeded, item.isVideo || item.kind == .track || item.kind == .audiobook,
              let data = try? await send("Users/\(userId)/Items/\(item.id)"),
              let dto = try? decode(ItemDTO.self, from: data) else { return original }
        let playable = item.isVideo ? Self.isPlayableVideo(dto) : Self.isPlayableAudio(dto)
        if playable { return original }
        return convertedPlan(for: item) ?? original
    }

    private func convertedPlan(for item: MediaItem) -> DownloadPlan? {
        let seconds = item.durationSeconds ?? 0
        var comps: URLComponents?
        var query: [URLQueryItem] = [
            .init(name: "MediaSourceId", value: item.id), .init(name: "DeviceId", value: deviceId)
        ]
        let bitsPerSecond: Int
        if item.isVideo {
            comps = URLComponents(url: baseURL.appendingPathComponent("Videos/\(item.id)/stream.mp4"),
                                  resolvingAgainstBaseURL: false)
            query += [
                .init(name: "VideoCodec", value: "h264"), .init(name: "AudioCodec", value: "aac"),
                .init(name: "VideoBitRate", value: String(Self.videoBitrate)),
                .init(name: "AudioBitRate", value: String(Self.audioBitrateForVideo)),
                .init(name: "MaxHeight", value: "1080"), .init(name: "TranscodingMaxAudioChannels", value: "2"),
                .init(name: "Static", value: "false")
            ]
            bitsPerSecond = Self.videoBitrate + Self.audioBitrateForVideo
        } else {
            comps = URLComponents(url: baseURL.appendingPathComponent("Audio/\(item.id)/stream.mp3"),
                                  resolvingAgainstBaseURL: false)
            query += [
                .init(name: "AudioCodec", value: "mp3"),
                .init(name: "AudioBitRate", value: String(Self.musicBitrate)), .init(name: "Static", value: "false")
            ]
            bitsPerSecond = Self.musicBitrate
        }
        comps?.queryItems = query
        guard let url = comps?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 180)
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        let expected = seconds > 0 ? Int64(seconds * Double(bitsPerSecond) / 8) : nil
        return DownloadPlan(request: request, expectedBytes: expected, isConverted: true)
    }

    // MARK: - Compatibility checks

    private static func containers(_ dto: ItemDTO) -> Set<String> {
        Set((dto.container ?? "").lowercased().split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) })
    }

    private static func isPlayableVideo(_ dto: ItemDTO) -> Bool {
        guard !containers(dto).isDisjoint(with: ["mp4", "m4v", "mov"]) else { return false }
        let streams = dto.mediaStreams ?? []
        let video = streams.first { $0.type == "Video" }?.codec?.lowercased()
        let audio = streams.first { $0.type == "Audio" }?.codec?.lowercased()
        guard let video, ["h264", "hevc"].contains(video) else { return false }
        guard let audio else { return true }
        return ["aac", "ac3", "eac3", "mp3", "alac"].contains(audio)
    }

    private static func isPlayableAudio(_ dto: ItemDTO) -> Bool {
        let okContainers: Set<String> = ["mp3", "flac", "wav", "aac", "m4a", "m4b", "mp4", "aiff", "caf", "mov"]
        guard !containers(dto).isDisjoint(with: okContainers) else { return false }
        guard let codec = (dto.mediaStreams ?? []).first(where: { $0.type == "Audio" })?.codec?.lowercased() else {
            return true
        }
        return ["aac", "mp3", "flac", "alac", "ac3", "eac3"].contains(codec) || codec.hasPrefix("pcm")
    }
}
