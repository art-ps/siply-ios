@testable import Siply
import Foundation

@MainActor
final class FakeTrackLoader: TrackLoader {
    var tracks: [URL: Track] = [:]          // чего нет — файла нет
    func track(at url: URL) async -> Track? { tracks[url] }
}
