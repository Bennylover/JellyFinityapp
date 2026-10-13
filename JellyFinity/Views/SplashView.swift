import SwiftUI

/// Brief branded intro shown on launch while the saved session is restored.
struct SplashView: View {
    var onFinish: () -> Void

    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false
    @State private var glow = false

    var body: some View {
        ZStack {
            Color("LaunchBackground").ignoresSafeArea()
            backdrop
            VStack(spacing: 18) {
                logo
                wordmark
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("JellyFinity")
        .task { await run() }
    }

    private var backdrop: some View {
        theme.gradient
            .opacity(revealed ? 0.22 : 0)
            .blur(radius: 60)
            .scaleEffect(glow ? 1.15 : 0.9)
            .ignoresSafeArea()
    }

    private var logo: some View {
        Image("JellyLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 132, height: 132)
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
            .shadow(color: theme.accent.opacity(0.35), radius: glow ? 28 : 8, y: 10)
            .scaleEffect(revealed || reduceMotion ? 1 : 0.82)
            .opacity(revealed ? 1 : 0)
    }

    private var wordmark: some View {
        VStack(spacing: 4) {
            Text("JellyFinity")
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(theme.gradient)
            Text("Your library, everywhere")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed || reduceMotion ? 0 : 12)
    }

    private func run() async {
        let reveal: Animation = reduceMotion ? .easeOut(duration: 0.3) : .spring(duration: 0.7, bounce: 0.3)
        withAnimation(reveal) { revealed = true }
        if !reduceMotion {
            withAnimation(.easeInOut(duration: 1.2).delay(0.2)) { glow = true }
        }
        try? await Task.sleep(for: .milliseconds(1400))
        onFinish()
    }
}

#Preview {
    SplashView(onFinish: {})
}
