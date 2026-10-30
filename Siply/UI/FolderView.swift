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
    @State private var isCloud = false
    @State private var folderActions: [URL: Set<FileAction>] = [:]   // считаем в фоне вместе с серостью
    @State private var watchKey = 0   // смена перезапускает опрос статусов
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
                        .contextMenu {
                            let actions = folderActions[sub] ?? []
                            if actions.contains(.download) {
                                Button("Скачать", systemImage: "icloud.and.arrow.down") { downloadFolder(sub) }
                            }
                            if actions.contains(.evict) {
                                Button("Удалить с устройства", systemImage: "xmark.icloud") { evictFolder(sub) }
                            }
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
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            let actions = FileAction.available(isUbiquitous: isCloud, state: track.download)
                            if actions.contains(.download) {
                                Button("Скачать", systemImage: "icloud.and.arrow.down") { download(track.url) }
                            }
                            if actions.contains(.evict) {
                                // не .destructive: файл остаётся в iCloud, действие обратимо
                                Button("Удалить с устройства", systemImage: "xmark.icloud") {
                                    Task { await evict([track.url]) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if !loaded && tracks.isEmpty && subfolders.isEmpty {
                ProgressView()   // iCloud может перечислять нескачанную папку десятки секунд
            } else if loaded && tracks.isEmpty && subfolders.isEmpty {
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
        }
        .task(id: watchKey) { await watchDownloads() }
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
        let folder = folder
        let onDemand = source.tagsOnDemand(for: folder)
        // Чтение папки — в фоне: iCloud может подтягивать содержимое каталога с сервера,
        // а FolderView на главном потоке, где любой блокирующий вызов замораживает экран.
        let subs = await Task.detached { FolderNode.subfolders(of: folder) }.value
        subfolders = subs
        let cloud = (try? folder.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
        isCloud = cloud
        // Серость подпапки — без тегов, только статус скачивания прямых файлов.
        // Провайдер без iCloud-статуса серым не бывает — не дёргаем атрибуты каждого файла.
        // Нескачанная папка целиком серая: внутрь не заходим, листинг ждал бы загрузку.
        let (dimmed, actions) = onDemand ? ([], [:]) : await Task.detached { () -> (Set<URL>, [URL: Set<FileAction>]) in
            var dimmed: Set<URL> = []
            var actions: [URL: Set<FileAction>] = [:]
            for sub in subs {
                let folderState = DownloadState.of(sub)
                let states = folderState == .remote ? [] : LibraryScanner.audioFiles(in: sub).map { DownloadState.of($0) }
                if folderState == .remote || FolderRowState.isDimmed(tracks: states.map { state in
                    var t = Track(url: sub)
                    t.download = state
                    return t
                }) { dimmed.insert(sub) }
                actions[sub] = FileAction.available(isUbiquitous: cloud, folderState: folderState, fileStates: states)
            }
            return (dimmed, actions)
        }.value
        dimmedFolders = dimmed
        folderActions = actions
        var loadedTracks = await LibraryScanner.tracks(in: folder, tagsOnDemand: onDemand)
        for i in loadedTracks.indices where inFlight.contains(loadedTracks[i].url) {
            loadedTracks[i].download = .downloading
        }
        tracks = loadedTracks
        let snapshot = loadedTracks
        artwork = await Task.detached { LibraryScanner.folderArtwork(for: folder, tracks: snapshot) }.value
        loaded = true
        watchKey += 1
    }

    private func download(_ url: URL) {
        do {
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            if let i = tracks.firstIndex(where: { $0.url == url }) { tracks[i].download = .downloading }
            watchKey += 1
        } catch {
            downloadError = url.lastPathComponent
        }
    }

    /// Убирает файлы с устройства (в iCloud остаются). Текущий трек пропускаем — он играет.
    private func evict(_ urls: [URL]) async {
        let targets = urls.filter { $0 != player.currentTrack?.url }
        let failed = await Task.detached {
            targets.filter { (try? FileManager.default.evictUbiquitousItem(at: $0)) == nil }
        }.value
        for url in targets where !failed.contains(url) {
            if let i = tracks.firstIndex(where: { $0.url == url }) {
                tracks[i] = Track(url: url)
                tracks[i].download = .remote
            }
            player.markEvicted(url)
        }
        if let url = failed.first { downloadError = url.lastPathComponent }
    }

    private func downloadFolder(_ sub: URL) {
        Task {
            // Файловые вызовы — в фоне: iCloud-атрибуты и листинг могут блокировать
            let failed = await Task.detached { () -> [URL] in
                let urls = DownloadState.of(sub) == .remote ? [sub]
                    : LibraryScanner.audioFiles(in: sub).filter { DownloadState.of($0) == .remote }
                return urls.filter { (try? FileManager.default.startDownloadingUbiquitousItem(at: $0)) == nil }
            }.value
            if let url = failed.first { downloadError = url.lastPathComponent }
            await reload()
        }
    }

    private func evictFolder(_ sub: URL) {
        Task {
            let urls = await Task.detached {
                LibraryScanner.audioFiles(in: sub).filter { DownloadState.of($0) == .local }
            }.value
            await evict(urls)
            await reload()
        }
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
