import SwiftUI
import UIKit

/// Gives the Mac (Catalyst) window a sensible minimum size. No-op on iPhone and iPad.
private struct MacWindowMinimumSize: ViewModifier {
    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content.onAppear {
            for scene in UIApplication.shared.connectedScenes {
                guard let windowScene = scene as? UIWindowScene else { continue }
                windowScene.sizeRestrictions?.minimumSize = CGSize(width: 900, height: 620)
            }
        }
        #else
        content
        #endif
    }
}

extension View {
    func macWindowMinimumSize() -> some View {
        modifier(MacWindowMinimumSize())
    }
}
