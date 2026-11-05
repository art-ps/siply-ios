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
    var appFolder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    func track(at url: URL) async -> Track? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let isCloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        // Как tagsOnDemand: SMB, Яндекс.Диск, флешка — только имя, иначе провайдер качает файлы целиком.
        // Пути сравниваем с развёрнутыми симлинками: /private то есть, то нет.
        if !isCloud, !url.resolvingSymlinksInPath().path.hasPrefix(appFolder.resolvingSymlinksInPath().path + "/") {
            var t = Track(url: url)
            t.download = .onDemand
            t.artwork = LibraryScanner.coverFile(in: url.deletingLastPathComponent())
            return t
        }
        // Не скачанный — серая строка без чтения тегов: файла на диске нет.
        if DownloadState.of(url) == .remote {
            var t = Track(url: url)
            t.download = .remote
            t.artwork = LibraryScanner.coverFile(in: url.deletingLastPathComponent())
            return t
        }
        return await LibraryScanner.loadTrack(url)
    }
}
