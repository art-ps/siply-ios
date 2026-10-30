import Foundation
import Observation

struct SearchHit: Identifiable, Hashable {
    let url: URL
    let isFolder: Bool
    let source: Source
    var id: URL { url }
}

/// Поиск по именам файлов и папок во всех источниках. Дерево обходится один раз
/// на первый непустой запрос и держится в памяти до invalidate().
// @Observable нужен только ради .environment(_:); наблюдаемых полей не добавляет.
@MainActor @Observable
final class SearchIndex {
    private struct Entry {
        let url: URL
        let isFolder: Bool
        let source: Source
    }

    private static let limit = 200

    @ObservationIgnored private let store: SourceStore
    @ObservationIgnored private var cache: [Entry]?
    @ObservationIgnored private var walkTask: Task<[Entry], Never>?
    private(set) var walkCount = 0

    init(store: SourceStore) { self.store = store }

    func search(_ query: String) async -> [SearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let entries = await loadEntries()
        var hits: [SearchHit] = []
        for e in entries where Self.matches(e, q) {
            hits.append(SearchHit(url: e.url, isFolder: e.isFolder, source: e.source))
            if hits.count == Self.limit { break }
        }
        return hits
    }

    /// Сброс кэша (pull-to-refresh). Результат уже идущего обхода отбрасывается.
    func invalidate() {
        cache = nil
        walkTask = nil
    }

    // MARK: - private

    private func loadEntries() async -> [Entry] {
        if let cache { return cache }
        if let walkTask { return await walkTask.value }
        let roots = store.sources.compactMap { s in
            store.isAvailable(s) ? store.url(of: s).map { (s, $0) } : nil
        }
        walkCount += 1
        let task = Task.detached { Self.walk(roots) }
        walkTask = task
        let result = await task.value
        // invalidate() во время обхода обнулил walkTask — не кладём устаревшее в кэш
        if walkTask == task {
            cache = result
            walkTask = nil
        }
        return result
    }

    private nonisolated static func walk(_ roots: [(Source, URL)]) -> [Entry] {
        var result: [Entry] = []
        for (source, root) in roots {
            guard let en = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            var part: [Entry] = []
            for case let url as URL in en {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir || LibraryScanner.audioExtensions.contains(url.pathExtension.lowercased()) {
                    part.append(Entry(url: url, isFolder: isDir, source: source))
                }
            }
            part.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
            result += part
        }
        return result
    }

    private nonisolated static func matches(_ e: Entry, _ q: String) -> Bool {
        let name = e.isFolder ? e.url.lastPathComponent : e.url.deletingPathExtension().lastPathComponent
        return name.localizedCaseInsensitiveContains(q)
    }
}
