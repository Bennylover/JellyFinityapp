import SwiftUI

/// Plays a haptic only when the view is genuinely tapped (not when a scroll starts on top of it).
private struct TapHaptic: ViewModifier {
    let feedback: SensoryFeedback
    @State private var taps = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { taps += 1 })
            .sensoryFeedback(feedback, trigger: taps)
    }
}

extension View {
    /// Light tick for choosing an item.
    func selectionHaptic() -> some View {
        modifier(TapHaptic(feedback: .selection))
    }

    /// Firmer tap for primary actions such as Play.
    func playHaptic() -> some View {
        modifier(TapHaptic(feedback: .impact(weight: .medium)))
    }
}
