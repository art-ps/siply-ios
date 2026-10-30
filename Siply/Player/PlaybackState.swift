import Foundation

/// Что пережить перезапуск: очередь, текущий трек, позиция. Shuffle и повтор — в своих ключах.
struct PlaybackState: Codable, Equatable {
    var urls: [String]        // url.path
    var currentIndex: Int
    var position: TimeInterval
}

/// Трек по сохранённому пути; nil — файла больше нет.
protocol TrackLoader: Sendable {
    func track(at url: URL) async -> Track?
}

struct FileTrackLoader: TrackLoader {
    func track(at url: URL) async -> Track? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        // Не скачанный — серая строка без чтения тегов: файла на диске нет.
        if DownloadState.of(url) == .remote {
            var t = Track(url: url)
            t.download = .remote
            return t
        }
        return await LibraryScanner.loadTrack(url)
    }
}
