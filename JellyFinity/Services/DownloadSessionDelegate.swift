import Foundation

enum DownloadEvent: Sendable {
    case progress(id: String, fraction: Double)
    case finished(id: String, fileName: String, bytes: Int64)
    case failed(id: String, message: String)
}

/// Receives URLSession download callbacks and moves finished files into permanent storage.
final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var handler: (@Sendable (DownloadEvent) -> Void)?
    private var lastSent: [String: Double] = [:]

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let id = downloadTask.taskDescription else { return }
        let guess = downloadTask.countOfBytesClientExpectsToReceive
        let expected = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : max(guess, 0)
        guard expected > 0 else { return }
        let fraction = min(Double(totalBytesWritten) / Double(expected), 0.99)
        guard fraction - (lastSent[id] ?? -1) >= 0.01 else { return }
        lastSent[id] = fraction
        handler?(.progress(id: id, fraction: fraction))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = downloadTask.taskDescription else { return }
        lastSent[id] = nil
        guard let http = downloadTask.response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            handler?(.failed(id: id, message: "The server refused the download."))
            return
        }
        let fileName = "\(DownloadStorage.safeName(id)).\(Self.fileExtension(for: http))"
        var destination = DownloadStorage.directory.appendingPathComponent(fileName)
        let manager = FileManager.default
        do {
            try? manager.removeItem(at: destination)
            try manager.moveItem(at: location, to: destination)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? destination.setResourceValues(values)
            let attributes = try? manager.attributesOfItem(atPath: destination.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            handler?(.finished(id: id, fileName: fileName, bytes: size))
        } catch {
            handler?(.failed(id: id, message: "There wasn't enough room to save this download."))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, let id = task.taskDescription else { return }
        lastSent[id] = nil
        if (error as NSError).code == NSURLErrorCancelled { return }
        handler?(.failed(id: id, message: "The download was interrupted. Check your connection and try again."))
    }

    private static func fileExtension(for response: HTTPURLResponse) -> String {
        if let name = response.suggestedFilename {
            let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
            if !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) { return ext }
        }
        switch response.mimeType?.lowercased() {
        case "audio/mpeg": return "mp3"
        case "audio/flac": return "flac"
        case "audio/mp4", "audio/x-m4a", "audio/aac": return "m4a"
        case "video/quicktime": return "mov"
        case "video/x-matroska": return "mkv"
        case let mime? where mime.hasPrefix("audio"): return "m4a"
        default: return "mp4"
        }
    }
}
