import Foundation
@testable import Siply

/// Загрузчик для тестов: download висит, пока тест не вызовет complete(url).
@MainActor
final class FakeDownloader: Downloader {
    struct Failure: Error {}

    var requested: [URL] = []
    var failing: Set<URL> = []
    private var waiting: [URL: CheckedContinuation<Void, Never>] = [:]

    func download(_ url: URL) async throws {
        if failing.contains(url) { throw Failure() }
        requested.append(url)
        await withCheckedContinuation { waiting[url] = $0 }
    }

    func complete(_ url: URL) {
        waiting.removeValue(forKey: url)?.resume()
    }
}
