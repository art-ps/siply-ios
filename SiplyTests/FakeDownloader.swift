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
        requested.append(url)
        if failing.contains(url) { throw Failure() }
        precondition(waiting[url] == nil, "повторный download того же url, пока первый не завершён")
        await withCheckedContinuation { waiting[url] = $0 }
    }

    func complete(_ url: URL) {
        waiting.removeValue(forKey: url)?.resume()
    }
}
