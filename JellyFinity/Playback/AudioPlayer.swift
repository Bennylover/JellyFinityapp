import AVFoundation
import Combine
import MediaPlayer
import Observation
import UIKit

/// App-wide music and audiobook player with a queue, lock-screen controls and Jellyfin progress sync.
@MainActor
@Observable
final class AudioPlayer {
    private(set) var queue: [MediaItem] = []
    private(set) var index = 0
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var sleepEndsAt: Date?
    var errorMessage: String?
    var rate: Float = 1.0 {
        didSet { applyRate() }
    }

    var current: MediaItem? { queue.indices.contains(index) ? queue[index] : nil }
    var hasNext: Bool { index + 1 < queue.count }
    var hasPrevious: Bool { index > 0 }
    var isActive: Bool { current != nil }

    /// Called with the position of a downloaded item so offline progress can be saved on the device.
    @ObservationIgnored var onLocalProgress: ((String, Double) -> Void)?
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var statusCancellable: AnyCancellable?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var client: JellyfinClient?
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var playSessionId = UUID().uuidString
    @ObservationIgnored private var sleepTask: Task<Void, Never>?
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        statusCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                MainActor.assumeIsolated {
                    self?.isPlaying = status != .paused
                    self?.updateNowPlaying()
                }
            }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.tick(seconds) }
        }
        configureRemoteCommands()
    }

    // MARK: - Transport

    func play(_ items: [MediaItem], startAt startIndex: Int, using store: SessionStore) {
        let client = store.client
        let userId = store.session?.userId
        let allLocal = !items.isEmpty && items.allSatisfy { $0.localFileURL != nil }
        guard allLocal || (client != nil && userId != nil) else {
            errorMessage = "Connect to your own Jellyfin server to play music and audiobooks."
            return
        }
        guard items.indices.contains(startIndex) else { return }
        reportCurrent(.stopped)
        currentTime = 0
        self.client = client
        self.userId = userId
        queue = items
        errorMessage = nil
        activateSession()
        load(at: startIndex)
    }

    func resume() { player.play() }

    func pause() { player.pause() }

    func togglePlayPause() {
        if isPlaying { pause() } else { resume() }
    }

    func next() {
        guard hasNext else { return }
        load(at: index + 1)
    }

    func previous() {
        if currentTime > 5 || !hasPrevious {
            seek(to: 0)
        } else {
            load(at: index - 1)
        }
    }

    func skip(by seconds: Double) {
        seek(to: min(max(currentTime + seconds, 0), max(duration, 0)))
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlaying()
    }

    func stop() {
        reportCurrent(.stopped)
        sleepTask?.cancel()
        sleepEndsAt = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        queue = []
        index = 0
        currentTime = 0
        duration = 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        guard let minutes else {
            sleepEndsAt = nil
            return
        }
        sleepEndsAt = Date.now.addingTimeInterval(Double(minutes) * 60)
        sleepTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled else { return }
            self?.pause()
            self?.sleepEndsAt = nil
        }
    }

    // MARK: - Loading

    private func load(at newIndex: Int) {
        reportCurrent(.stopped)
        guard queue.indices.contains(newIndex) else { return }
        index = newIndex
        let item = queue[newIndex]
        var streamURL: URL?
        if let local = item.localFileURL {
            streamURL = local
        } else if let client, let userId {
            streamURL = client.audioStreamURL(itemId: item.id, userId: userId)
        }
        guard let url = streamURL else {
            errorMessage = "That item couldn't be played."
            return
        }
        playSessionId = UUID().uuidString
        let playerItem = AVPlayerItem(url: url)
        observeEnd(of: playerItem)
        player.replaceCurrentItem(with: playerItem)
        currentTime = 0
        duration = item.durationSeconds ?? 0
        if let resume = item.resumeSeconds, resume > 5, resume < duration - 10 {
            seek(to: resume)
        }
        player.defaultRate = rate
        player.play()
        reportCurrent(.started)
        loadArtwork(for: item)
        updateNowPlaying()
    }

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemFinished() }
        }
    }

    private func itemFinished() {
        if hasNext {
            next()
        } else {
            reportCurrent(.stopped)
            player.pause()
            seek(to: 0)
        }
    }

    private func tick(_ seconds: Double) {
        guard current != nil, seconds.isFinite else { return }
        currentTime = seconds
        if let total = player.currentItem?.duration.seconds, total.isFinite, total > 0, abs(total - duration) > 1 {
            duration = total
        }
        if Date.now.timeIntervalSince(lastReport) > 15 {
            reportCurrent(.progress)
        }
    }

    private func applyRate() {
        player.defaultRate = rate
        if isPlaying { player.rate = rate }
        updateNowPlaying()
    }

    // MARK: - Server sync

    private func reportCurrent(_ stage: PlaybackStage) {
        guard let item = current else { return }
        lastReport = .now
        if item.localFileURL != nil, stage != .started, currentTime > 0 {
            onLocalProgress?(item.id, currentTime)
        }
        guard let client else { return }
        let sessionId = playSessionId
        let position = currentTime
        let paused = !isPlaying
        Task {
            await client.report(stage, itemId: item.id, playSessionId: sessionId,
                                positionSeconds: position, isPaused: paused)
        }
    }

    // MARK: - System integration

    private func activateSession() {
        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .default)
        try? audioSession.setActive(true)
    }

    private func updateNowPlaying() {
        guard let item = current else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(rate) : 0.0
        ]
        if let artist = item.subtitle { info[MPMediaItemPropertyArtist] = artist }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(for item: MediaItem) {
        artwork = nil
        artworkTask?.cancel()
        guard let url = item.primaryImageURL else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), !Task.isCancelled else { return }
            let made = Self.makeArtwork(image)
            self?.artwork = made
            self?.updateNowPlaying()
        }
    }

    nonisolated private static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            let position = event.positionTime
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
    }
}
