import Foundation
import Observation

struct Source: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable { case appFolder, bookmark(Data) }
    let id: UUID
    var name: String
    var kind: Kind
}

/// Куда навигировать: папка внутри источника. Используется NavigationStack, поиском и FileOpener.
struct FolderRoute: Hashable {
    let folder: URL
    let source: Source
    var autoDownload: Bool = false   // из серой подпапки: FolderView сразу ставит её файлы на загрузку
}

/// Список источников: своя папка приложения (всегда первая) + папки пользователя по bookmark'ам.
@MainActor @Observable
final class SourceStore {
    private(set) var sources: [Source]
    var pendingRoute: FolderRoute?   // просьба открыть папку (из onOpenURL); SourcesView забирает и обнуляет
    /// Растёт на каждый refresh(): доступность читается с диска, наблюдать больше нечего.
    private(set) var revision = 0

    private let defaults: UserDefaults
    private let appFolder: URL
    private let key = "sources"
    private var resolved: [UUID: URL] = [:]
    // Фиксированный id, чтобы источник «Siply» не менялся между запусками
    private let appSource = Source(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                                   name: "Siply", kind: .appFolder)

    init(defaults: UserDefaults = .standard,
         appFolder: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) {
        self.defaults = defaults
        self.appFolder = appFolder
        let saved = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([Source].self, from: $0) } ?? []
        sources = [appSource] + saved.filter { $0.kind != .appFolder }
        for source in sources { restore(source) }
    }

    func add(folder url: URL) {
        let std = url.standardizedFileURL
        if sources.contains(where: { self.url(of: $0)?.standardizedFileURL == std }) { return }
        _ = url.startAccessingSecurityScopedResource()   // false для не-scoped папок — не ошибка; stop не зовём
        guard let data = try? url.bookmarkData() else { return }
        let source = Source(id: UUID(), name: displayName(of: url), kind: .bookmark(data))
        resolved[source.id] = url
        sources.append(source)
        save()
    }

    func remove(_ source: Source) {
        guard source.kind != .appFolder else { return }
        sources.removeAll { $0.id == source.id }
        resolved[source.id] = nil
        save()
    }

    func rename(_ source: Source, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let i = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[i].name = name
        save()
    }

    /// Флешку вставили обратно — заново разрешаем bookmark'и; без перезапуска приложения.
    func refresh() {
        for source in sources { restore(source) }
        revision += 1
    }

    func url(of source: Source) -> URL? {
        switch source.kind {
        case .appFolder: appFolder
        case .bookmark: resolved[source.id]
        }
    }

    func isAvailable(_ source: Source) -> Bool {
        guard let url = url(of: source) else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - private

    private func restore(_ source: Source) {
        guard case .bookmark(let data) = source.kind else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
        else { return }
        _ = url.startAccessingSecurityScopedResource()
        resolved[source.id] = url
        if stale, let fresh = try? url.bookmarkData(),
           let i = sources.firstIndex(where: { $0.id == source.id }) {
            sources[i].kind = .bookmark(fresh)
            save()
        }
    }

    private func save() {
        let own = sources.filter { $0.kind != .appFolder }
        if let data = try? JSONEncoder().encode(own) { defaults.set(data, forKey: key) }
    }

    /// Корень тома — имя тома, корни системных провайдеров — как в Файлах, иначе имя папки.
    private func displayName(of url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.volumeURLKey, .volumeNameKey])
        if let volume = values?.volume, volume.standardizedFileURL == url.standardizedFileURL,
           let name = values?.volumeName { return name }
        // iOS 26: корень провайдера «На iPhone» лежит в папке с UUID-именем — такое имя пользователю не показываем
        if UUID(uuidString: url.lastPathComponent) != nil { return "Папка" }
        switch url.lastPathComponent {
        case "com~apple~CloudDocs": return "iCloud Drive"
        case "File Provider Storage": return "На iPhone"   // ponytail: корень любого провайдера; сторонние тоже назовутся так
        default: return url.lastPathComponent
        }
    }
}

extension Source {
    /// Теги по запросу: не своя папка и не iCloud (SMB, Яндекс.Диск, флешка) — чтобы провайдер не качал файлы целиком.
    func tagsOnDemand(for folder: URL) -> Bool {
        kind != .appFolder && (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) != true
    }
}
