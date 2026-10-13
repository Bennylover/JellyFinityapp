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
        // Color.clear guarantees there's always a real view on screen, so the loading task
        // runs even while the content closure draws nothing (an empty view never "appears").
        ZStack {
            Color.clear.frame(width: 0, height: 0)
            content(phase)
        }
        .task(id: url) {
                await load()
            }
    }

    /// Loads the picture, and quietly tries again a few times if the server wasn't ready.
    private func load() async {
        let alreadyShown = phase.image != nil
        for attempt in 0..<4 {
            if let loaded = await ImageStore.shared.image(for: url) {
                let image = Image(uiImage: loaded)
                if alreadyShown {
                    phase = .success(image)
                } else {
                    withAnimation(.easeOut(duration: 0.25)) { phase = .success(image) }
                }
                return
            }
            if Task.isCancelled { return }
            if attempt < 3 { try? await Task.sleep(for: .seconds(4)) }
            if Task.isCancelled { return }
        }
        phase = .failure
    }
}
