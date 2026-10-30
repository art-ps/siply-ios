import Foundation

/// Открытие файла из Files / Share sheet.
@MainActor
enum FileOpener {
    /// Файл внутри известного источника → очередь = папка; иначе — один трек. Возвращает маршрут папки для навигации или nil.
    static func open(_ url: URL, store: SourceStore, player: PlayerModel) async -> FolderRoute? {
        let file = url.standardizedFileURL
        let owner = store.sources.first { source in
            guard let root = store.url(of: source) else { return false }
            return file.path.hasPrefix(root.standardizedFileURL.path + "/")
        }
        guard let source = owner else {
            // Вне источников iOS дал доступ только к этому файлу; stop не зовём
            _ = url.startAccessingSecurityScopedResource()
            player.play(queue: [await LibraryScanner.loadTrack(url)], startingAt: 0)
            return nil
        }
        let folder = file.deletingLastPathComponent()
        let tracks = await LibraryScanner.tracks(in: folder, tagsOnDemand: source.tagsOnDemand(for: folder))
        // Неиграемого файла в очереди нет — плеер не трогаем, папку всё равно открываем
        if let i = tracks.firstIndex(where: { $0.url.standardizedFileURL == file }) {
            player.play(queue: tracks, startingAt: i)
        }
        return FolderRoute(folder: folder, source: source)
    }
}
