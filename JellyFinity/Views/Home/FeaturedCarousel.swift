import SwiftUI

/// Home hero that cycles through several titles every 10 seconds.
struct FeaturedCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appTheme) private var theme
    let items: [MediaItem]
    @State private var index = 0

    private var current: MediaItem? {
        guard !items.isEmpty else { return nil }
        return items[min(index, items.count - 1)]
    }

    var body: some View {
        VStack(spacing: 10) {
            if let current {
                NavigationLink(value: current) { FeaturedHeroCard(item: current) }
                    .buttonStyle(.plain)
                    .id(current.id)
                    .transition(.opacity)
            }
            if items.count > 1 { dots }
        }
        .task(id: items.map(\.id)) { await rotate() }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(items.indices, id: \.self) { position in
                Capsule()
                    .fill(position == index ? theme.accent : Color.secondary.opacity(0.35))
                    .frame(width: position == index ? 18 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func rotate() async {
        index = 0
        guard items.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { return }
            let next = (index + 1) % items.count
            if reduceMotion {
                index = next
            } else {
                withAnimation(.easeInOut(duration: 0.8)) { index = next }
            }
        }
    }
}
