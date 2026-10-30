import Foundation
import Observation

/// Таймер сна: через N минут или в конце текущего трека.
enum SleepOption: Hashable {
    case off, minutes(Int), endOfTrack
}

/// Состояние воспроизведения: очередь, текущий трек, режимы. Звук — через AudioEngine.
@MainActor
@Observable
final class PlayerModel {
    enum RepeatMode: String, CaseIterable {
        case off, all, one
    }

    private(set) var queue: [Track] = []
    private(set) var currentIndex: Int?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    /// Текущий трек качается, звука ещё нет — для индикатора в мини-плеере.
    private(set) var isDownloading = false

    /// Трек не скачан — в движке чужой звук, длины нет.
    var duration: TimeInterval { currentTrack?.download == .local ? engine.duration : 0 }
    var currentTrack: Track? { currentIndex.map { queue[$0] } }

    var volume: Float {
        didSet { engine.volume = volume; defaults.set(volume, forKey: Keys.volume) }
    }
    /// Скорость одна на всё приложение.
    private(set) var rate: Float
    var shuffle: Bool {
        didSet { rebuildOrder(); defaults.set(shuffle, forKey: Keys.shuffle) }
    }
    var repeatMode: RepeatMode {
        didSet { defaults.set(repeatMode.rawValue, forKey: Keys.repeatMode) }
    }

    /// Между запусками не сохраняется.
    var sleep: SleepOption = .off {
        didSet {
            if case .minutes(let m) = sleep { sleepDeadline = Date().addingTimeInterval(Double(m) * 60) } else { sleepDeadline = nil }
        }
    }
    private(set) var sleepDeadline: Date?

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private let downloader: Downloader
    @ObservationIgnored private let defaults: UserDefaults
    /// Порядок обхода индексов queue: прямой или перемешанный (текущий — первым).
    @ObservationIgnored private var order: [Int] = []
    @ObservationIgnored private var timer: Timer?
    /// Удалась ли хоть одна загрузка с начала последнего play(queue:startingAt:).
    @ObservationIgnored private var didLoad = false
    /// Загрузки в полёте по url: один url не качаем дважды. true — скачан.
    @ObservationIgnored private var downloads: [URL: Task<Bool, Never>] = [:]
    /// Ожидание загрузки текущего трека; новый выбор трека его отменяет.
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    /// Позиция последнего сохранения: тик пишет, когда уехали на 5 с.
    @ObservationIgnored private var lastPersistedAt: TimeInterval = -5

    private enum Keys {
        static let volume = "volume"
        static let rate = "rate"
        static let shuffle = "shuffle"
        static let repeatMode = "repeatMode"
        static let playback = "playback"
    }

    init(engine: AudioEngine, downloader: Downloader = FileDownloader(), defaults: UserDefaults = .standard) {
        self.engine = engine
        self.downloader = downloader
        self.defaults = defaults
        volume = defaults.object(forKey: Keys.volume) as? Float ?? 1
        rate = defaults.object(forKey: Keys.rate) as? Float ?? 1
        shuffle = defaults.bool(forKey: Keys.shuffle)
        repeatMode = RepeatMode(rawValue: defaults.string(forKey: Keys.repeatMode) ?? "") ?? .off
        engine.volume = volume
        engine.rate = rate
        engine.onFinished = { [weak self] in self?.trackFinished() }
    }

    // MARK: - Управление

    private static let rates: [Float] = [1, 1.25, 1.5, 2, 0.75]

    func cycleRate() {
        let next = Self.rates.firstIndex(of: rate).map { Self.rates[($0 + 1) % Self.rates.count] } ?? Self.rates[0]
        rate = next
        engine.rate = next
        defaults.set(next, forKey: Keys.rate)
    }

    func play(queue: [Track], startingAt index: Int) {
        guard queue.indices.contains(index) else { return }
        self.queue = queue
        currentIndex = index
        rebuildOrder()
        didLoad = false
        if !playTrack(index) {
            step(by: 1, wrap: true)
            // Ни один трек не открылся — указывать не на что, движок держит старый трек.
            if !didLoad { currentIndex = nil }
        }
    }

    func togglePlayPause() {
        // Пока качается — в движке старый трек, играть нечего.
        guard let cur = currentIndex, !isDownloading else { return }
        if isPlaying {
            engine.pause()
            isPlaying = false
            stopTimer()
            persist()
        } else if queue[cur].download != .local || !didLoad {
            // Загрузка не удалась или после перезапуска не открылся — в движке старый трек; заново.
            if !playTrack(cur) { step(by: 1, wrap: true) }
        } else {
            startPlaying()
        }
    }

    /// Пользовательский «следующий» — на краю очереди идёт по кругу.
    func next() { step(by: 1, wrap: true) }

    /// Больше 3 секунд от начала — перемотка в начало, иначе предыдущий трек.
    func previous() {
        if engine.currentTime > 3 { seek(to: 0); return }
        step(by: -1, wrap: true)
    }

    func seek(to time: TimeInterval) {
        engine.currentTime = time
        currentTime = time
        persist()
    }

    func cycleRepeat() {
        let all = RepeatMode.allCases
        repeatMode = all[(all.firstIndex(of: repeatMode)! + 1) % all.count]
    }

    /// Файл скачан (например, тапом по строке) — отметить во всей очереди.
    func markDownloaded(_ url: URL) { setDownload(.local, for: url) }

    // MARK: - Внутреннее

    private func trackFinished() {
        // «До конца трека» важнее повтора: тишина, трек остаётся текущим.
        if sleep == .endOfTrack { halt(); sleep = .off; return }
        if repeatMode == .one, let i = currentIndex, playTrack(i) { return }
        step(by: 1, wrap: repeatMode == .all)
    }

    /// Шаг по order с пропуском нечитаемых. wrap=false на краю → halt().
    private func step(by delta: Int, wrap: Bool) {
        guard let cur = currentIndex, let start = order.firstIndex(of: cur) else { return }
        var pos = start
        for _ in 0..<order.count {
            pos += delta
            if !order.indices.contains(pos) {
                guard wrap else { halt(); return }
                pos = (pos + order.count) % order.count
            }
            if playTrack(order[pos]) { return }
        }
        halt()
    }

    /// Сделать idx текущим и играть: локальный — сразу, удалённый и .onDemand — после загрузки.
    /// false — локальный не открылся, текущий не меняется.
    private func playTrack(_ idx: Int) -> Bool {
        downloadTask?.cancel()
        downloadTask = nil
        isDownloading = false
        if queue[idx].download != .local {
            playAfterDownload(idx)
            return true
        }
        guard load(idx) else { return false }
        currentIndex = idx
        persist()
        startPlaying()
        return true
    }

    /// Звука нет, пока трек не скачан; ошибка — плеер стоит, трек остаётся .remote / .onDemand.
    private func playAfterDownload(_ idx: Int) {
        currentIndex = idx
        // Как halt(): позиция старого трека не должна влиять на previous() и прогресс.
        engine.pause()
        engine.currentTime = 0
        isPlaying = false
        stopTimer()
        currentTime = 0
        isDownloading = true
        persist()
        let fetching = fetch(queue[idx].url)
        downloadTask = Task {
            let ok = await fetching.value
            // Отменили — состоянием уже владеет новый выбор трека.
            guard !Task.isCancelled else { return }
            isDownloading = false
            guard ok else { return }
            if load(idx) { startPlaying() } else { step(by: 1, wrap: true) }
        }
    }

    /// Пока играет — качаем следующий по order: между треками iOS усыпит приложение.
    private func prefetchNext() {
        guard let cur = currentIndex, let pos = order.firstIndex(of: cur) else { return }
        var next = pos + 1
        if next == order.count {
            guard repeatMode == .all else { return }
            next = 0
        }
        let track = queue[order[next]]
        if track.download == .remote || track.download == .onDemand { _ = fetch(track.url) }
    }

    /// Загрузка url; уже идущую не дублируем. Состояние в очереди — по url, индексы могли смениться.
    private func fetch(_ url: URL) -> Task<Bool, Never> {
        if let task = downloads[url] { return task }
        // Сбой вернёт прежнее состояние: .onDemand не должен посереть
        let before = queue.first { $0.url == url }?.download == .onDemand ? DownloadState.onDemand : .remote
        setDownload(.downloading, for: url)
        // immediate — запрос уходит синхронно, до возврата из play/next.
        let task = Task.immediate {
            defer { downloads[url] = nil }
            do {
                try await downloader.download(url)
                setDownload(.local, for: url)
                return true
            } catch {
                if !(error is CancellationError) {
                    NSLog("Siply: не удалось скачать %@: %@", url.lastPathComponent, "\(error)")
                }
                setDownload(before, for: url)
                return false
            }
        }
        // Ошибка могла прийти синхронно — задача уже завершена, не запоминаем.
        if queue.contains(where: { $0.url == url && $0.download == .downloading }) {
            downloads[url] = task
        }
        return task
    }

    private func setDownload(_ state: DownloadState, for url: URL) {
        for i in queue.indices where queue[i].url == url { queue[i].download = state }
    }

    private func load(_ idx: Int) -> Bool {
        do {
            try engine.load(queue[idx].url)
            currentTime = 0
            didLoad = true
            return true
        } catch {
            NSLog("Siply: не удалось открыть %@: %@", queue[idx].url.lastPathComponent, "\(error)")
            return false
        }
    }

    private func startPlaying() {
        engine.play()
        isPlaying = true
        startTimer()
        prefetchNext()
    }

    /// Конец очереди: остаёмся на текущем треке, в начале, на паузе.
    private func halt() {
        engine.pause()
        engine.currentTime = 0
        currentTime = 0
        isPlaying = false
        stopTimer()
        persist()
    }

    private func rebuildOrder() {
        let all = Array(queue.indices)
        guard shuffle, let cur = currentIndex else { order = all; return }
        order = [cur] + all.filter { $0 != cur }.shuffled()
    }

    private func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(now: Date()) }
        }
        // .common — чтобы прогресс не замирал, пока открыто меню.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Тик таймера: прогресс и срок таймера сна.
    func tick(now: Date) {
        currentTime = engine.currentTime
        if abs(currentTime - lastPersistedAt) >= 5 { persist() }
        if let deadline = sleepDeadline, now >= deadline, isPlaying {
            togglePlayPause()
            sleep = .off
        }
    }

    /// Сохранить очередь и позицию; зовёт и RootView при уходе в фон.
    func persist() {
        guard let cur = currentIndex, !queue.isEmpty else { return }
        // Пока качается — позиция в движке чужая.
        let state = PlaybackState(urls: queue.map(\.url.path), currentIndex: cur, position: isDownloading ? 0 : currentTime)
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Keys.playback)
        lastPersistedAt = currentTime
    }

    /// Поднять очередь после перезапуска: на паузе, на сохранённой позиции. Нет текущего файла — ничего не делаем.
    func restore(using loader: TrackLoader) async {
        guard let data = defaults.data(forKey: Keys.playback),
              let state = try? JSONDecoder().decode(PlaybackState.self, from: data),
              state.urls.indices.contains(state.currentIndex) else { return }
        let loaded = await withTaskGroup(of: (Int, Track?).self) { group in
            for (i, path) in state.urls.enumerated() {
                group.addTask { (i, await loader.track(at: URL(fileURLWithPath: path))) }
            }
            var result = [Track?](repeating: nil, count: state.urls.count)
            for await (i, t) in group { result[i] = t }
            return result
        }
        guard loaded[state.currentIndex] != nil else { return }
        // Индекс текущего сдвигается на число пропавших перед ним.
        let cur = loaded[..<state.currentIndex].compactMap { $0 }.count
        queue = loaded.compactMap { $0 }
        currentIndex = cur
        rebuildOrder()
        isPlaying = false
        isDownloading = false
        didLoad = false
        currentTime = 0
        if queue[cur].download == .local, load(cur) {
            engine.currentTime = state.position
            currentTime = state.position
        } else {
            currentTime = 0
            didLoad = false
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
