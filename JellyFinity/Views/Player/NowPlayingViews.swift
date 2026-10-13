import SwiftUI

func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let secs = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, secs)
                     : String(format: "%d:%02d", minutes, secs)
}

extension View {
    /// Docks the mini player just above the tab bar (and below any pushed screen content).
    func miniPlayerInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) { MiniPlayerBar() }
    }
}

/// Compact player that floats above the tab bar while audio is active.
struct MiniPlayerBar: View {
    @Environment(AudioPlayer.self) private var audio
    @Environment(\.appTheme) private var theme
    @State private var showFull = false

    var body: some View {
        if let item = audio.current {
            HStack(spacing: 12) {
                ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol, showsSymbol: false)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    if let subtitle = item.subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Button { audio.togglePlayPause() } label: {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill").font(.title3)
                }
                .playHaptic()
                .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
                Button { audio.next() } label: {
                    Image(systemName: "forward.fill").font(.title3)
                }
                .disabled(!audio.hasNext)
                .accessibilityLabel("Next")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.accent)
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .contentShape(Rectangle())
            .onTapGesture { showFull = true }
            .sheet(isPresented: $showFull) { NowPlayingView() }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct NowPlayingView: View {
    @Environment(AudioPlayer.self) private var audio
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var scrubValue: Double?

    var body: some View {
        VStack(spacing: 22) {
            Capsule().fill(.secondary.opacity(0.4)).frame(width: 40, height: 5).padding(.top, 8)
            if let item = audio.current {
                artwork(for: item)
                titles(for: item)
                scrubber
                transport
                extras
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 20)
        .background(theme.background.ignoresSafeArea())
        .presentationDragIndicator(.hidden)
    }

    private func artwork(for item: MediaItem) -> some View {
        ArtworkView(url: item.primaryImageURL, seed: item.artworkSeed, symbol: item.symbol)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: theme.accent.opacity(0.35), radius: 24, y: 14)
            .scaleEffect(audio.isPlaying ? 1 : 0.92)
            .animation(.spring(response: 0.5, dampingFraction: 0.75), value: audio.isPlaying)
            .padding(.top, 8)
    }

    private func titles(for item: MediaItem) -> some View {
        VStack(spacing: 4) {
            Text(item.name).font(.title2.weight(.bold)).lineLimit(2).multilineTextAlignment(.center)
            if let subtitle = item.subtitle {
                Text(subtitle).font(.body).foregroundStyle(.secondary).lineLimit(1)
            }
            if audio.queue.count > 1 {
                Text("Track \(audio.index + 1) of \(audio.queue.count)")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private var scrubber: some View {
        let total = max(audio.duration, 1)
        let shown = scrubValue ?? audio.currentTime
        return VStack(spacing: 4) {
            Slider(value: Binding(get: { min(shown, total) }, set: { scrubValue = $0 }),
                   in: 0...total) { editing in
                if !editing, let value = scrubValue {
                    audio.seek(to: value)
                    scrubValue = nil
                }
            }
            .tint(theme.accent)
            HStack {
                Text(formatPlaybackTime(shown))
                Spacer()
                Text("-" + formatPlaybackTime(max(total - shown, 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transport: some View {
        HStack(spacing: 26) {
            Button { audio.skip(by: -15) } label: { Image(systemName: "gobackward.15").font(.title2) }
                .accessibilityLabel("Back 15 seconds")
            Button { audio.previous() } label: { Image(systemName: "backward.fill").font(.title) }
                .accessibilityLabel("Previous")
            Button { audio.togglePlayPause() } label: {
                Image(systemName: audio.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 68))
                    .foregroundStyle(theme.gradient)
            }
            .playHaptic()
            .accessibilityLabel(audio.isPlaying ? "Pause" : "Play")
            Button { audio.next() } label: { Image(systemName: "forward.fill").font(.title) }
                .disabled(!audio.hasNext)
                .accessibilityLabel("Next")
            Button { audio.skip(by: 30) } label: { Image(systemName: "goforward.30").font(.title2) }
                .accessibilityLabel("Forward 30 seconds")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var extras: some View {
        HStack {
            speedMenu
            Spacer()
            sleepMenu
        }
        .font(.subheadline.weight(.semibold))
        .tint(theme.accent)
    }

    private var speedMenu: some View {
        Menu {
            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                Button {
                    audio.rate = Float(speed)
                } label: {
                    if Float(speed) == audio.rate { Label(speedLabel(speed), systemImage: "checkmark") }
                    else { Text(speedLabel(speed)) }
                }
            }
        } label: {
            Label(speedLabel(Double(audio.rate)), systemImage: "speedometer")
        }
    }

    private var sleepMenu: some View {
        Menu {
            Button("Off") { audio.setSleepTimer(minutes: nil) }
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) minutes") { audio.setSleepTimer(minutes: minutes) }
            }
        } label: {
            if let end = audio.sleepEndsAt {
                Label {
                    Text(end, style: .timer).monospacedDigit()
                } icon: {
                    Image(systemName: "moon.zzz.fill")
                }
            } else {
                Label("Sleep", systemImage: "moon.zzz")
            }
        }
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == speed.rounded() ? String(format: "%.0f×", speed) : String(format: "%g×", speed)
    }
}
