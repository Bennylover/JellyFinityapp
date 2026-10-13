import CryptoKit
import UIKit

/// Two-level (memory + disk) image cache. Pictures you've seen once load instantly and keep
/// showing without a connection; files already on this device are read straight from disk.
final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private let session: URLSession
    private let refreshAfter: TimeInterval = 7 * 24 * 3600
    private let lock = NSLock()
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ImageStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.totalCostLimit = 80_000_000
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: configuration)
    }

    func cachedInMemory(_ url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    func image(for url: URL) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }
        if url.isFileURL {
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            memory.setObject(image, forKey: key, cost: 1_000_000)
            return image
        }
        let file = diskURL(for: url)
        if let fresh = freshDiskImage(at: file) {
            memory.setObject(fresh, forKey: key, cost: 1_000_000)
            return fresh
        }
        // One shared download per picture: it keeps going (and fills the cache) even if the
        // view that asked for it scrolls away, and duplicate views don't hit the server twice.
        return await sharedDownload(url, file: file).value
    }

    private func sharedDownload(_ url: URL, file: URL) -> Task<UIImage?, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight[url.absoluteString] { return existing }
        let task = Task.detached(priority: .userInitiated) { [self] () -> UIImage? in
            var result = await download(url, saveTo: file)
            if result == nil {
                // Offline or the server is slow: an old copy is better than nothing.
                result = UIImage(contentsOfFile: file.path)
            }
            if let result { memory.setObject(result, forKey: url.absoluteString as NSString, cost: 1_000_000) }
            finish(url)
            return result
        }
        inFlight[url.absoluteString] = task
        return task
    }

    private func finish(_ url: URL) {
        lock.lock()
        inFlight[url.absoluteString] = nil
        lock.unlock()
    }

    /// Warms the disk cache for pictures we want available later (cast portraits, for example).
    func prefetch(_ urls: [URL]) async {
        for url in urls where !url.isFileURL {
            _ = await image(for: url)
        }
    }

    private func freshDiskImage(at file: URL) -> UIImage? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < refreshAfter else { return nil }
        return UIImage(contentsOfFile: file.path)
    }

    /// Tries up to three times; a freshly cleaned server can be slow to resize pictures.
    private func download(_ url: URL, saveTo file: URL) async -> UIImage? {
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(from: url)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let image = UIImage(data: data) {
                    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try? data.write(to: file, options: .atomic)
                    return image
                }
                NSLog("ImageStore: HTTP %d for %@", status, url.absoluteString)
                if status == 404 || status == 401 || status == 403 { return nil }
            } catch {
                if (error as? URLError)?.code == .cancelled { return nil }
                NSLog("ImageStore: %@ for %@", error.localizedDescription, url.absoluteString)
            }
            try? await Task.sleep(for: .seconds(Double(attempt + 1)))
        }
        return nil
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }
}
