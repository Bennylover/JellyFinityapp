import SwiftUI

/// Remote artwork with a rich gradient fallback so cards always look intentional.
struct ArtworkView: View {
    let url: URL?
    let seed: Int
    let symbol: String
    var showsSymbol = true

    private var gradient: LinearGradient {
        let pair = SampleData.palettes[seed % SampleData.palettes.count]
        return LinearGradient(colors: [Color(hex: pair.0), Color(hex: pair.1)],
                              startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        Rectangle()
            .fill(gradient)
            .overlay {
                if showsSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 34, weight: .light))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .overlay {
                if let url {
                    CachedImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        }
                    }
                }
            }
            .clipped()
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.bold))
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}

struct ComingSoonView: View {
    @Environment(\.appTheme) private var theme
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(theme.accent.opacity(0.16))
                    .frame(width: 140, height: 140)
                Circle()
                    .fill(theme.gradient)
                    .frame(width: 88, height: 88)
                    .shadow(color: theme.accent.opacity(0.4), radius: 18, y: 8)
                Image(systemName: symbol)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.title2.weight(.bold))
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background.ignoresSafeArea())
    }
}
