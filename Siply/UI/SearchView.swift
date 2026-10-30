import SwiftUI

/// Вкладка «Поиск»: имена файлов и папок по всем источникам, секции по источнику.
struct SearchView: View {
    @Environment(SearchIndex.self) private var index
    @Environment(PlayerModel.self) private var player
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var path: [FolderRoute] = []

    // Секции в порядке первого появления источника (hits уже упорядочены по источникам)
    private var sections: [(source: Source, hits: [SearchHit])] {
        var result: [(source: Source, hits: [SearchHit])] = []
        for hit in hits {
            if let i = result.firstIndex(where: { $0.source == hit.source }) {
                result[i].hits.append(hit)
            } else {
                result.append((hit.source, [hit]))
            }
        }
        return result
    }

    private var isEmptyResult: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty && hits.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(sections, id: \.source.id) { section in
                    Section(section.source.name) {
                        ForEach(section.hits) { hit in row(hit, in: section.hits) }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if isEmptyResult { ContentUnavailableView.search(text: query) }
            }
            .navigationTitle("Поиск")
            .searchable(text: $query, prompt: "Файлы и папки")
            .navigationDestination(for: FolderRoute.self) { FolderView(folder: $0.folder, source: $0.source, autoDownload: $0.autoDownload) }
            .task(id: query) {
                // debounce: смена запроса отменяет задачу до search
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                let found = await index.search(query)
                guard !Task.isCancelled else { return }   // запрос сменился, пока искали
                hits = found
            }
            .refreshable {
                index.invalidate()
                hits = await index.search(query)
            }
        }
    }

    @ViewBuilder
    private func row(_ hit: SearchHit, in sectionHits: [SearchHit]) -> some View {
        if hit.isFolder {
            NavigationLink(value: FolderRoute(folder: hit.url, source: hit.source)) {
                Label(hit.url.lastPathComponent, systemImage: "folder")
            }
        } else {
            TrackRow(track: track(for: hit), isCurrent: player.currentTrack?.url == hit.url) {
                // очередь — треки-хиты этого источника, теги не читаем
                let tracks = sectionHits.filter { !$0.isFolder }
                if let i = tracks.firstIndex(of: hit) {
                    player.play(queue: tracks.map(track(for:)), startingAt: i)
                }
            }
        }
    }

    /// Трек по имени файла с реальным статусом: нескачанное серое, плеер его докачает.
    private func track(for hit: SearchHit) -> Track {
        var t = Track(url: hit.url)
        t.download = DownloadState.of(hit.url)
        // как в LibraryScanner: .remote важнее, провайдер без iCloud-статуса — .onDemand
        if t.download == .local, hit.source.tagsOnDemand(for: hit.url.deletingLastPathComponent()) {
            t.download = .onDemand
        }
        return t
    }
}
