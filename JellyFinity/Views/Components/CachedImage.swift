import SwiftUI

enum CachedImagePhase {
    case empty
    case success(Image)
    case failure

    var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }
}

/// Drop-in replacement for `AsyncImage` that remembers pictures on disk (see `ImageStore`).
struct CachedImage<Content: View>: View {
    let url: URL
    private let content: (CachedImagePhase) -> Content
    @State private var phase: CachedImagePhase

    init(url: URL, @ViewBuilder content: @escaping (CachedImagePhase) -> Content) {
        self.url = url
        self.content = content
        if let cached = ImageStore.shared.cachedInMemory(url) {
            _phase = State(initialValue: .success(Image(uiImage: cached)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                let alreadyShown = phase.image != nil
                if let loaded = await ImageStore.shared.image(for: url) {
                    let image = Image(uiImage: loaded)
                    if alreadyShown {
                        phase = .success(image)
                    } else {
                        withAnimation(.easeOut(duration: 0.25)) { phase = .success(image) }
                    }
                } else if !Task.isCancelled {
                    phase = .failure
                }
            }
    }
}
