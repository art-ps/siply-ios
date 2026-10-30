import SwiftUI

/// Экран папки: шапка, подпапки, треки.
struct FolderView: View {
    let folder: URL
    let source: Source

    @Environment(PlayerModel.self) private var player
    @State private var subfolders: [URL] = []
    @State private var dimmedFolders: Set<URL> = []
    @State private var tracks: [Track] = []
    @State private var artwork: Data?
    @State private var loaded = false
    @State private var downloadError: String?

    init(folder: URL, source: Source) {
        self.folder = folder
        self.source = source
    }

    var body: some View {
        List {
            if !tracks.isEmpty || !subfolders.isEmpty {
                FolderHeader(artwork: artwork, name: folder.lastPathComponent, tracks: tracks,
                             play: playAll, shuffle: shuffleAll)
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 16, trailing: 16))
                    .listRowSeparator(.hidden)
            }
            if !subfolders.isEmpty {
                Section("Папки") {
                    ForEach(subfolders, id: \.self) { sub in
                        NavigationLink(value: FolderRoute(folder: sub, source: source)) {
                            FolderRow(url: sub, dimmed: dimmedFolders.contains(sub))
                        }
                        .simultaneousGesture(TapGesture().onEnded {
                            if dimmedFolders.contains(sub) { downloadAll(in: sub) }
                        })
                    }
                }
            }
            if !tracks.isEmpty {
                Section("Треки") {
                    ForEach(tracks) { track in
                        TrackRow(track: track, isCurrent: player.currentTrack?.url == track.url) {
                            tap(track.url)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if loaded && tracks.isEmpty && subfolders.isEmpty {
                EmptyFolderView(text: source.kind == .appFolder
                                ? "Скопируйте музыку в Files → На iPhone → Siply"
                                : "В папке нет музыки")
            }
        }
        .navigationTitle(folder.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: folder) { await reload() }
        .refreshable { await reload() }
        .alert("Не удалось скачать", isPresented: Binding(
            get: { downloadError != nil }, set: { if !$0 { downloadError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(downloadError ?? "")
        }
    }

    private func reload() async {
        let subs = FolderNode.subfolders(of: folder)
        subfolders = subs
        // Серость подпапки — без тегов, только статус скачивания прямых файлов
        dimmedFolders = Set(subs.filter { sub in
            FolderRowState.isDimmed(tracks: LibraryScanner.audioFiles(in: sub).map { url in
                var t = Track(url: url)
                t.download = DownloadState.of(url)
                return t
            })
        })
        tracks = await LibraryScanner.tracks(in: folder, tagsOnDemand: source.tagsOnDemand(for: folder))
        artwork = LibraryScanner.folderArtwork(for: folder, tracks: tracks)
        loaded = true
    }

    private func playAll() {
        player.shuffle = false
        player.play(queue: tracks, startingAt: 0)
    }

    private func shuffleAll() {
        player.shuffle = true
        player.play(queue: tracks, startingAt: Int.random(in: tracks.indices))
    }

    private func tap(_ url: URL) {
        guard let i = tracks.firstIndex(where: { $0.url == url }) else { return }
        switch tracks[i].download {
        case .local:
            player.play(queue: tracks, startingAt: i)
        case .downloading:
            break
        case .remote:
            tracks[i].download = .downloading
            Task {
                do {
                    try await FileDownloader().download(url)
                    var t = await LibraryScanner.loadTrack(url)
                    t.download = .local
                    // Пока качали, список мог перечитаться — ищем по url, не по индексу
                    guard let j = tracks.firstIndex(where: { $0.url == url }) else { return }
                    tracks[j] = t
                    player.markDownloaded(url)
                    player.play(queue: tracks, startingAt: j)
                } catch {
                    if let j = tracks.firstIndex(where: { $0.url == url }) { tracks[j].download = .remote }
                    downloadError = url.lastPathComponent
                }
            }
        }
    }

    /// Серая подпапка: качаем её не скачанные файлы в фоне, навигация идёт сразу.
    private func downloadAll(in sub: URL) {
        Task {
            for url in LibraryScanner.audioFiles(in: sub) where DownloadState.of(url) == .remote {
                try? await FileDownloader().download(url)
            }
        }
    }
}
