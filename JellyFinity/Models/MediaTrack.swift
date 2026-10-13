import Foundation

/// An audio or subtitle stream inside a video file.
struct MediaTrack: Identifiable, Hashable, Sendable {
    enum Kind: Sendable { case audio, subtitle }

    let index: Int
    let kind: Kind
    let title: String
    let isDefault: Bool

    var id: Int { index }
}

/// All selectable audio and subtitle streams of one video.
struct MediaTracks: Sendable, Equatable {
    var audio: [MediaTrack] = []
    var subtitles: [MediaTrack] = []

    static let empty = MediaTracks()

    var isEmpty: Bool { audio.count < 2 && subtitles.isEmpty }

    /// The audio stream the server plays when nothing else is requested.
    var defaultAudio: MediaTrack? { audio.first(where: \.isDefault) ?? audio.first }

    func audioTrack(_ index: Int?) -> MediaTrack? { audio.first { $0.index == index } }
    func subtitleTrack(_ index: Int?) -> MediaTrack? { subtitles.first { $0.index == index } }
}
