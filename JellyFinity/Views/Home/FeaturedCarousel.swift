import SwiftUI

/// Home hero: swipe sideways through the featured titles. It also advances by itself
/// every 6 seconds, and the timer restarts after each swipe.
struct FeaturedCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    let items: [MediaItem]
    @State private var position: Int? = 0
    @State private var autoAdvancing = false
    @State private var hapticTick = 0

    private var index: Int {
        guard !items.isEmpty else { return 0 }
        return min(max(position ?? 0, 0), items.count - 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            pager
            if items.count > 1 { dots }
        }
        .sensoryFeedback(.selection, trigger: hapticTick)
        .onChange(of: position) { _, _ in
            if autoAdvancing { autoAdvancing = false } else { hapticTick += 1 }
        }
        .task(id: timerKey) { await advanceLoop() }
    }

    private var timerKey: String {
        "\(items.map(\.id).joined(separator: ","))|\(position ?? 0)"
    }

    private var pager: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 40) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    NavigationLink(value: item) { FeaturedHeroCard(item: item) }
                        .buttonStyle(.plain)
                        .playHaptic()
                        .containerRelativeFrame(.horizontal)
                        .scrollTransition(.animated) { content, phase in
                            content
                                .opacity(phase.isIdentity ? 1 : 0.5)
                                .scaleEffect(phase.isIdentity ? 1 : 0.94)
                        }
                        .id(offset)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $position)
        .scrollClipDisabled()
        .onChange(of: items.map(\.id)) { _, _ in position = 0 }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { slot in
                Capsule()
                    .fill(slot == index ? theme.accent : Color.secondary.opacity(0.35))
                    .frame(width: slot == index ? 18 : 6, height: 6)
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: index)
        .accessibilityHidden(true)
    }

    private func advanceLoop() async {
        guard items.count > 1 else { return }
        try? await Task.sleep(for: .seconds(6))
        if Task.isCancelled { return }
        let next = (index + 1) % items.count
        autoAdvancing = true
        if reduceMotion {
            position = next
        } else {
            withAnimation(.easeInOut(duration: 0.6)) { position = next }
        }
    }
}
