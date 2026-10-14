import SwiftUI

/// Swipe a row sideways to add it to the queue; it springs back with a haptic, like Spotify.
private struct SwipeToQueue: ViewModifier {
    @Environment(\.appTheme) private var theme
    let onQueue: () -> Void

    @State private var offset: CGFloat = 0
    @State private var crossed = false
    @State private var fired = 0
    private let threshold: CGFloat = 72

    func body(content: Content) -> some View {
        content
            .offset(x: offset)
            .background { indicator }
            .clipped()
            .simultaneousGesture(drag)
            .sensoryFeedback(.impact(weight: .light), trigger: crossed) { _, now in now }
            .sensoryFeedback(.success, trigger: fired)
    }

    private var progress: Double {
        min(Double(abs(offset)) / Double(threshold), 1)
    }

    private var indicator: some View {
        ZStack(alignment: offset >= 0 ? .leading : .trailing) {
            Rectangle().fill(theme.accent.opacity(0.10 + 0.14 * progress))
            Image(systemName: "text.line.first.and.arrowtriangle.forward")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.accent)
                .scaleEffect(0.7 + 0.3 * progress)
                .opacity(progress)
                .padding(.horizontal, 22)
        }
        .opacity(offset == 0 ? 0 : 1)
        .accessibilityHidden(true)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard isHorizontal(value.translation) else { return }
                let width = value.translation.width
                let magnitude = abs(width)
                let damped = magnitude < 96 ? magnitude : 96 + (magnitude - 96) * 0.15
                offset = width < 0 ? -damped : damped
                crossed = magnitude > threshold
            }
            .onEnded { value in
                if isHorizontal(value.translation), abs(value.translation.width) > threshold {
                    fired += 1
                    onQueue()
                }
                crossed = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { offset = 0 }
            }
    }

    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.6
    }
}

extension View {
    /// Swipe left or right on a row to add it to the play queue.
    func swipeToQueue(perform action: @escaping () -> Void) -> some View {
        modifier(SwipeToQueue(onQueue: action))
    }
}
