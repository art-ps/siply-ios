@testable import Siply
import Foundation

@MainActor
final class FakeTrackLoader: TrackLoader {
    var tracks: [URL: Track] = [:]          // чего нет — файла нет
    /// true — ответы висят, пока тест не вызовет release().
    var gated = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func track(at url: URL) async -> Track? {
        if gated { await withCheckedContinuation { waiting.append($0) } }
        return tracks[url]
    }

    func release() {
        gated = false
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
