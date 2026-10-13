import AVFoundation
import AVKit
import Combine
import Observation
import SwiftUI

/// Owns a single video playback session: builds the stream, resumes, and syncs progress with Jellyfin.
@MainActor
@Observable
final class VideoPlayerModel {
    private(set) var player: AVPlayer?
    private(set) var errorMessage: String?
    private(set) var tracks = MediaTracks.empty
    private(set) var audioIndex: Int?
    private(set) var subtitleIndex: Int?

    @ObservationIgnored private var client: JellyfinClient?
    @ObservationIgnored private var itemId = ""
    @ObservationIgnored private var playSessionId = UUID().uuidString
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private(set) var lastPosition: Double = 0
    @ObservationIgnored private(set) var isLocal = false
    @ObservationIgnored private var failureWatch: AnyCancellable?
    @ObservationIgnored private var userId: String?
    @ObservationIgnored private var isDirectPlay = false
    @ObservationIgnored private var isStopped = false

    /// Shows a message when AVPlayer can't handle the file (for example some downloaded containers).
    /// If the original file fails to play directly, retries once with a server remux instead.
    private func watchForFailure(of newPlayer: AVPlayer, isLocal: Bool) {
        guard let playerItem = newPlayer.currentItem else { return }
        failureWatch = playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard status == .failed else { return }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.isDirectPlay, !isLocal {
                        NSLog("JellyFinity playback: direct play failed, retrying via server stream")
                        self.restartStream(allowDirectPlay: false)
                        return
                    }
                    self.errorMessage = isLocal
                        ? "This download is in a format iPhone can't play. Stream it from your server instead."
                        : "This video couldn't be played."
                }
            }
    }

    /// Asks the server for the best stream for this iPhone; falls back to the classic HLS URL if that fails.
    private func resolveStreamURL(allowDirectPlay: Bool = true) async -> URL? {
        guard let client else { return nil }
        if let userId {
            let audioIsDefault = audioIndex == nil || audioIndex == tracks.defaultAudio?.index
            do {
                let playback = try await client.resolveVideoPlayback(
                    itemId: itemId, userId: userId, audioIndex: audioIndex, subtitleIndex: subtitleIndex,
                    audioIsDefault: audioIsDefault, allowDirectPlay: allowDirectPlay)
                playSessionId = playback.playSessionId
                isDirectPlay = playback.method == .directPlay
                return playback.url
            } catch {
                NSLog("JellyFinity playback: PlaybackInfo failed (%@), using HLS fallback", "\(error)")
            }
        }
        isDirectPlay = false
        return client.videoStreamURL(itemId: itemId, playSessionId: playSessionId,
                                     audioIndex: audioIndex, subtitleIndex: subtitleIndex)
    }

    func start(item: MediaItem, store: SessionStore, audio: AudioPlayer) async {
        guard player == nil, !isStopped else { return }
        audio.pause()
        itemId = item.id

        let url: URL?
        if let local = item.localFileURL {
            isLocal = true
            self.client = store.client
            url = local
        } else if store.isDemo {
            url = SampleData.demoVideoURL
        } else if let client = store.client {
            self.client = client
            self.userId = store.session?.userId
            url = await resolveStreamURL()
        } else {
            url = nil
        }
        guard !isStopped, player == nil else { return }
        guard let url else {
            errorMessage = "Connect to your Jellyfin server to play this."
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)

        let newPlayer = AVPlayer(url: url)
        watchForFailure(of: newPlayer, isLocal: isLocal)
        if !store.isDemo, let resume = item.resumeSeconds, resume > 5 {
            newPlayer.seek(to: CMTime(seconds: resume, preferredTimescale: 600), completionHandler: { _ in })
        }
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserver = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.tick(seconds) }
        }
        player = newPlayer
        newPlayer.play()
        send(.started, position: item.resumeSeconds ?? 0, paused: false)
    }

    func stop() {
        isStopped = true
        guard let player else { return }
        send(.stopped, position: lastPosition, paused: true)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        self.player = nil
    }

    // MARK: - Audio & subtitle tracks

    func loadTracks(store: SessionStore) async {
        guard client != nil, !isLocal, !itemId.isEmpty else { return }
        let loaded = await store.fetchVideoTracks(itemId: itemId)
        tracks = loaded
        audioIndex = loaded.defaultAudio?.index
    }

    func selectAudio(_ index: Int) {
        guard index != audioIndex else { return }
        audioIndex = index
        restartStream()
    }

    func selectSubtitle(_ index: Int?) {
        guard index != subtitleIndex else { return }
        subtitleIndex = index
        restartStream()
    }

    /// Asks the server for the same video with the chosen tracks and continues from the current position.
    private func restartStream(allowDirectPlay: Bool = true) {
        guard let player, client != nil, !isLocal else { return }
        let position = player.currentTime().seconds
        let wasPlaying = player.timeControlStatus != .paused || !allowDirectPlay
        Task {
            guard let url = await resolveStreamURL(allowDirectPlay: allowDirectPlay),
                  !isStopped, self.player === player else { return }
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            watchForFailure(of: player, isLocal: false)
            if position.isFinite, position > 1 {
                await player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
            }
            if wasPlaying { player.play() }
        }
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        lastPosition = seconds
        if Date.now.timeIntervalSince(lastReport) > 10 {
            send(.progress, position: seconds, paused: (player?.timeControlStatus ?? .paused) == .paused)
        }
    }

    private func send(_ stage: PlaybackStage, position: Double, paused: Bool) {
        guard let client else { return }
        lastReport = .now
        let id = itemId
        let sessionId = playSessionId
        Task {
            await client.report(stage, itemId: id, playSessionId: sessionId,
                                positionSeconds: position, isPaused: paused)
        }
    }
}

struct VideoPlayerScreen: View {
    @Environment(SessionStore.self) private var store
    @Environment(AudioPlayer.self) private var audio
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss
    @State private var model = VideoPlayerModel()
    @State private var showTitle = true
    let item: MediaItem

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topControls
                content
            }
        }
        .statusBarHidden(true)
        .task {
            await model.start(item: downloads.localized(item), store: store, audio: audio)
            await model.loadTracks(store: store)
        }
        .task {
            try? await Task.sleep(for: .seconds(2.5))
            showTitle = false
        }
        .onDisappear {
            model.stop()
            if model.isLocal { downloads.saveResume(id: item.id, seconds: model.lastPosition) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
                Text(message).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let player = model.player {
            PlayerControllerView(player: player).ignoresSafeArea(edges: .bottom)
        } else {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topControls: some View {
        HStack(spacing: 12) {
            closeButton
            Text(item.name)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .opacity(showTitle ? 1 : 0)
                .animation(.easeOut(duration: 0.8), value: showTitle)
            if model.tracks.isEmpty {
                Color.clear.frame(width: 40, height: 40)
            } else {
                tracksMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    private var tracksMenu: some View {
        let audioBinding = Binding<Int>(
            get: { model.audioIndex ?? -1 },
            set: { model.selectAudio($0) })
        let subtitleBinding = Binding<Int>(
            get: { model.subtitleIndex ?? -1 },
            set: { model.selectSubtitle($0 < 0 ? nil : $0) })
        return Menu {
            if model.tracks.audio.count > 1 {
                Picker("Audio", selection: audioBinding) {
                    ForEach(model.tracks.audio) { Text($0.title).tag($0.index) }
                }
                .pickerStyle(.inline)
            }
            if !model.tracks.subtitles.isEmpty {
                Picker("Subtitles", selection: subtitleBinding) {
                    Text("Off").tag(-1)
                    ForEach(model.tracks.subtitles) { Text($0.title).tag($0.index) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: model.subtitleIndex == nil ? "captions.bubble" : "captions.bubble.fill")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel("Audio and subtitles")
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .accessibilityLabel("Close player")
    }
}

private struct PlayerControllerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {}
}
