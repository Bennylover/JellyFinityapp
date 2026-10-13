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

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ImageStore", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        memory.totalCostLimit = 80_000_000
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
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
        if let downloaded = await download(url, saveTo: file) {
            memory.setObject(downloaded, forKey: key, cost: 1_000_000)
            return downloaded
        }
        // Offline or the server is slow: an old copy is better than nothing.
        guard let stale = UIImage(contentsOfFile: file.path) else { return nil }
        memory.setObject(stale, forKey: key, cost: 1_000_000)
        return stale
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

    private func download(_ url: URL, saveTo file: URL) async -> UIImage? {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        return image
    }

    private func diskURL(for url: URL) -> URL {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest)
    }
}
