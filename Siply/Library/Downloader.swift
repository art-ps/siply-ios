import UIKit

/// Скачивает файл на устройство и возвращается, когда он готов к чтению.
protocol Downloader: AnyObject {
    func download(_ url: URL) async throws
}

final class FileDownloader: Downloader {
    func download(_ url: URL) async throws {
        // Пока качаем, iOS не должна усыпить приложение.
        let task = await UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        defer { Task { @MainActor in UIApplication.shared.endBackgroundTask(task) } }

        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            while DownloadState.of(url) != .local {
                try await Task.sleep(for: .milliseconds(500))
            }
        } else {
            // Файловый провайдер подтягивает файл при координированном чтении.
            try await Task.detached { try Self.readFirstByte(url) }.value
        }
    }

    private static func readFirstByte(_ url: URL) throws {
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readURL in
            do {
                let handle = try FileHandle(forReadingFrom: readURL)
                defer { try? handle.close() }
                _ = try handle.read(upToCount: 1)
            } catch {
                readError = error
            }
        }
        if let error = coordinationError ?? readError { throw error }
    }
}
