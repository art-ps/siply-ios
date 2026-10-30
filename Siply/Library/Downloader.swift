import UIKit

/// Скачивает файл на устройство и возвращается, когда он готов к чтению.
protocol Downloader: AnyObject {
    func download(_ url: URL) async throws
}

/// Фоновая задача UIKit: завершается ровно один раз — по концу загрузки или по истечении времени.
@MainActor
private final class BackgroundTask {
    private var id = UIBackgroundTaskIdentifier.invalid

    static func begin() -> BackgroundTask {
        let task = BackgroundTask()
        task.id = UIApplication.shared.beginBackgroundTask { task.end() }
        return task
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

final class FileDownloader: Downloader {
    func download(_ url: URL) async throws {
        // Пока качаем, iOS не должна усыпить приложение.
        let background = await BackgroundTask.begin()
        defer { Task { @MainActor in background.end() } }

        if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            while DownloadState.of(url) != .local {
                // iCloud не справился (офлайн, файл удалён) — иначе строка висела бы в .downloading вечно.
                if let error = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingErrorKey]).ubiquitousItemDownloadingError {
                    throw error
                }
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
