import SwiftUI

/// Экран папки: шапка, подпапки, треки.
struct FolderView: View {
    let folder: URL
    let source: Source
    let autoDownload: Bool   // пришли из серой подпапки — сразу качаем её нескачанное

    @Environment(PlayerModel.self) private var player
    @State private var subfolders: [URL] = []
    @State private var dimmedFolders: Set<URL> = []
    @State private var tracks: [Track] = []
    @State private var artwork: Data?
    @State private var loaded = false
    @State private var downloadError: String?
    @State private var inFlight: Set<URL> = []   // качаются по тапу: перечитывание папки не должно сбросить строку
    @State private var lastTapToken: UUID?        // автоплей после загрузки — только для последнего тапа

    init(folder: URL, source: Source, autoDownload: Bool = false) {
        self.folder = folder
        self.source = source
        self.autoDownload = autoDownload
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
                        let dimmed = dimmedFolders.contains(sub)
                        NavigationLink(value: FolderRoute(folder: sub, source: source, autoDownload: dimmed)) {
                            FolderRow(url: sub, dimmed: dimmed)
                        }
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
        .task(id: folder) {
            await reload()
            if autoDownload {
                for t in tracks where t.download == .remote {
                    try? FileManager.default.startDownloadingUbiquitousItem(at: t.url)
                }
            }
            await watchDownloads()
        }
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
        let onDemand = source.tagsOnDemand(for: folder)
        // Серость подпапки — без тегов, только статус скачивания прямых файлов.
        // Провайдер без iCloud-статуса серым не бывает — не дёргаем атрибуты каждого файла.
        dimmedFolders = onDemand ? [] : Set(subs.filter { sub in
            FolderRowState.isDimmed(tracks: LibraryScanner.audioFiles(in: sub).map { url in
                var t = Track(url: url)
                t.download = DownloadState.of(url)
                return t
            })
        })
        var loadedTracks = await LibraryScanner.tracks(in: folder, tagsOnDemand: onDemand)
        for i in loadedTracks.indices where inFlight.contains(loadedTracks[i].url) {
            loadedTracks[i].download = .downloading
        }
        tracks = loadedTracks
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
        let token = UUID()
        lastTapToken = token
        switch tracks[i].download {
        case .local:
            player.play(queue: tracks, startingAt: i)
        case .downloading:
            break
        case .remote, .onDemand:
            // .onDemand тянем сами: после загрузки появятся теги и обложка
            let before = tracks[i].download
            let currentAtTap = player.currentTrack?.url
            tracks[i].download = .downloading
            inFlight.insert(url)
            // Неструктурно: уйдём с экрана — файл всё равно докачается
            Task {
                do {
                    try await FileDownloader().download(url)
                    inFlight.remove(url)
                    var t = await LibraryScanner.loadTrack(url)
                    t.download = .local
                    // Пока качали, список мог перечитаться — ищем по url, не по индексу
                    guard let j = tracks.firstIndex(where: { $0.url == url }) else { return }
                    tracks[j] = t
                    player.markDownloaded(url)
                    // Пока качали, пользователь выбрал другое — не перебиваем
                    guard lastTapToken == token, player.currentTrack?.url == currentAtTap else { return }
                    player.play(queue: tracks, startingAt: j)
                } catch {
                    inFlight.remove(url)
                    if let j = tracks.firstIndex(where: { $0.url == url }) { tracks[j].download = before }
                    downloadError = url.lastPathComponent
                }
            }
        }
    }

    /// Пока есть нескачанные строки, раз в секунду смотрим статус: белеют после префетча плеера,
    /// next() или загрузки подпапки. Структурно — уйдём с экрана, опрос отменится.
    private func watchDownloads() async {
        guard !source.tagsOnDemand(for: folder) else { return }   // без iCloud-статуса опрашивать нечего
        func pending() -> [URL] {
            tracks.filter { $0.download == .remote || $0.download == .downloading }.map(\.url)
        }
        while !pending().isEmpty {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            for url in pending() {
                var u = url
                u.removeAllCachedResourceValues()   // иначе NSURL отдаёт закэшированный .notDownloaded
                guard DownloadState.of(u) == .local else { continue }
                var t = await LibraryScanner.loadTrack(u)
                t.download = .local
                guard let j = tracks.firstIndex(where: { $0.url == url }) else { continue }
                tracks[j] = t
                player.markDownloaded(url)
            }
        }
    }
}
