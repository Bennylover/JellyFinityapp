import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable, Sendable {
    case aurora, ember, jade

    var id: String { rawValue }

    var name: String {
        switch self {
        case .aurora: "Aurora"
        case .ember: "Ember"
        case .jade: "Jade"
        }
    }

    var tagline: String {
        switch self {
        case .aurora: "Violet dusk meets electric blue"
        case .ember: "Warm amber, cinema glow"
        case .jade: "Calm emerald, deep ocean"
        }
    }

    var accent: Color {
        switch self {
        case .aurora: Color(light: 0x7B4FD1, dark: 0x9D6BEB)
        case .ember: Color(light: 0xC84B16, dark: 0xF07236)
        case .jade: Color(light: 0x0B7F62, dark: 0x1FA37A)
        }
    }

    var secondary: Color {
        switch self {
        case .aurora: Color(light: 0x0082B8, dark: 0x2BB7EE)
        case .ember: Color(light: 0xB82A63, dark: 0xFF5F8F)
        case .jade: Color(light: 0x1E64A8, dark: 0x5AB4FF)
        }
    }

    var background: Color {
        switch self {
        case .aurora: Color(light: 0xF6F4FB, dark: 0x0E0B16)
        case .ember: Color(light: 0xFBF6F2, dark: 0x140D0A)
        case .jade: Color(light: 0xF2F7F5, dark: 0x08120F)
        }
    }

    var surface: Color {
        switch self {
        case .aurora: Color(light: 0xFFFFFF, dark: 0x1A1625)
        case .ember: Color(light: 0xFFFFFF, dark: 0x221714)
        case .jade: Color(light: 0xFFFFFF, dark: 0x12201B)
        }
    }

    var elevated: Color {
        switch self {
        case .aurora: Color(light: 0xECE6F8, dark: 0x262035)
        case .ember: Color(light: 0xF5E9E1, dark: 0x30211B)
        case .jade: Color(light: 0xE3EFEA, dark: 0x1B2D26)
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [accent, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Auto"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .aurora
}

extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255
        let g = CGFloat((hex >> 8) & 0xFF) / 255
        let b = CGFloat(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    init(light: UInt32, dark: UInt32) {
        let lightColor = UIColor(hex: light)
        let darkColor = UIColor(hex: dark)
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? darkColor : lightColor
        })
    }
}

struct CardSurface: ViewModifier {
    @Environment(\.appTheme) private var theme
    var radius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 6)
    }
}

extension View {
    func cardSurface(radius: CGFloat = 24) -> some View {
        modifier(CardSurface(radius: radius))
    }
}
