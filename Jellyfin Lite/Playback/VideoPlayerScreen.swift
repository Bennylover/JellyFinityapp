import AVFoundation
import AVKit
import Observation
import SwiftUI

/// Owns a single video playback session: builds the stream, resumes, and syncs progress with Jellyfin.
@MainActor
@Observable
final class VideoPlayerModel {
    private(set) var player: AVPlayer?
    private(set) var errorMessage: String?

    @ObservationIgnored private var client: JellyfinClient?
    @ObservationIgnored private var itemId = ""
    @ObservationIgnored private var playSessionId = UUID().uuidString
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private var lastPosition: Double = 0

    func start(item: MediaItem, store: SessionStore, audio: AudioPlayer) {
        guard player == nil else { return }
        audio.pause()

        let url: URL?
        if store.isDemo {
            url = SampleData.demoVideoURL
        } else if let client = store.client {
            self.client = client
            url = client.videoStreamURL(itemId: item.id, playSessionId: playSessionId)
        } else {
            url = nil
        }
        guard let url else {
            errorMessage = "Connect to your Jellyfin server to play this."
            return
        }

        let audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playback, mode: .moviePlayback)
        try? audioSession.setActive(true)

        itemId = item.id
        let newPlayer = AVPlayer(url: url)
        if !store.isDemo, let resume = item.resumeSeconds, resume > 5 {
            newPlayer.seek(to: CMTime(seconds: resume, preferredTimescale: 600))
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
        guard let player else { return }
        send(.stopped, position: lastPosition, paused: true)
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player.pause()
        self.player = nil
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
    @Environment(\.dismiss) private var dismiss
    @State private var model = VideoPlayerModel()
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            content
            closeButton
        }
        .statusBarHidden(true)
        .task { model.start(item: item, store: store, audio: audio) }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private var content: some View {
        if let player = model.player {
            PlayerControllerView(player: player).ignoresSafeArea()
        } else if let message = model.errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle)
                Text(message).multilineTextAlignment(.center)
            }
            .foregroundStyle(.white)
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView().tint(.white).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
        .padding(.leading, 16)
        .padding(.top, 8)
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
