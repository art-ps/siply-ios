import XCTest
@testable import Siply

@MainActor
final class PlayerModelTests: XCTestCase {
    private var engine: FakeAudioEngine!
    private var player: PlayerModel!
    private var defaults: UserDefaults!
    private var downloader: FakeDownloader!
    private var tracks = (1...4).map { Track(url: URL(fileURLWithPath: "/m/\($0).mp3")) }

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SiplyPlayerModelTests")!
        defaults.removePersistentDomain(forName: "SiplyPlayerModelTests")
        engine = FakeAudioEngine()
        downloader = FakeDownloader()
        player = PlayerModel(engine: engine, downloader: downloader, defaults: defaults)
    }

    override func tearDown() {
        // Висящие загрузки отпускаем — иначе continuation утечёт.
        downloader.requested.forEach(downloader.complete)
        super.tearDown()
    }

    private func remote(_ i: Int) { tracks[i].download = .remote }

    private func settle() async {
        for _ in 0..<3 { await Task.yield() }
    }

    func testPlayLoadsAndPlaysChosenTrack() {
        player.play(queue: tracks, startingAt: 1)
        XCTAssertEqual(engine.loaded, [tracks[1].url])
        XCTAssertTrue(engine.playing)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTrack, tracks[1])
    }

    func testPlayWithBadIndexDoesNothing() {
        player.play(queue: tracks, startingAt: 9)
        XCTAssertNil(player.currentTrack)
        XCTAssertFalse(player.isPlaying)
    }

    func testTogglePlayPause() {
        player.play(queue: tracks, startingAt: 0)
        player.togglePlayPause()
        XCTAssertFalse(player.isPlaying); XCTAssertFalse(engine.playing)
        player.togglePlayPause()
        XCTAssertTrue(player.isPlaying); XCTAssertTrue(engine.playing)
    }

    func testToggleWithoutQueueDoesNothing() {
        player.togglePlayPause()
        XCTAssertFalse(player.isPlaying)
    }

    func testFinishedAdvances() {
        player.play(queue: tracks, startingAt: 0)
        engine.finish()
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertTrue(player.isPlaying)
    }

    func testFinishedAtEndWithRepeatOffStopsOnLastTrack() {
        player.play(queue: tracks, startingAt: 3)
        engine.finish()
        XCTAssertEqual(player.currentTrack, tracks[3])
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(engine.playing)
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(player.currentTime, 0)
    }

    func testRepeatAllWrapsToFirst() {
        player.repeatMode = .all
        player.play(queue: tracks, startingAt: 3)
        engine.finish()
        XCTAssertEqual(player.currentTrack, tracks[0])
    }

    func testRepeatOneReplaysSame() {
        player.repeatMode = .one
        player.play(queue: tracks, startingAt: 2)
        engine.finish()
        XCTAssertEqual(player.currentTrack, tracks[2])
        XCTAssertEqual(engine.loaded, [tracks[2].url, tracks[2].url])
    }

    func testNextAtEndWrapsForUser() {
        player.play(queue: tracks, startingAt: 3)
        player.next()
        XCTAssertEqual(player.currentTrack, tracks[0])
        XCTAssertTrue(player.isPlaying)
    }

    func testPreviousAfterThreeSecondsRestartsTrack() {
        player.play(queue: tracks, startingAt: 2)
        engine.currentTime = 5
        player.previous()
        XCTAssertEqual(player.currentTrack, tracks[2])
        XCTAssertEqual(engine.currentTime, 0)
        XCTAssertEqual(engine.loaded.count, 1)
    }

    func testPreviousEarlyGoesToPreviousTrack() {
        player.play(queue: tracks, startingAt: 2)
        engine.currentTime = 1
        player.previous()
        XCTAssertEqual(player.currentTrack, tracks[1])
    }

    func testPreviousOnFirstWrapsToLast() {
        player.play(queue: tracks, startingAt: 0)
        player.previous()
        XCTAssertEqual(player.currentTrack, tracks[3])
    }

    func testSeekUpdatesEngineAndState() {
        player.play(queue: tracks, startingAt: 0)
        player.seek(to: 42)
        XCTAssertEqual(engine.currentTime, 42)
        XCTAssertEqual(player.currentTime, 42)
    }

    func testShuffleKeepsCurrentAndVisitsEveryTrackOnce() {
        player.play(queue: tracks, startingAt: 1)
        player.shuffle = true
        var seen = [player.currentTrack!]
        for _ in 0..<3 { engine.finish(); seen.append(player.currentTrack!) }
        XCTAssertEqual(seen.first, tracks[1])
        XCTAssertEqual(Set(seen), Set(tracks))
        engine.finish()
        XCTAssertFalse(player.isPlaying, "после обхода всех при repeat off — стоп")
    }

    func testShuffleOffRestoresFolderOrder() {
        player.play(queue: tracks, startingAt: 1)
        player.shuffle = true
        player.shuffle = false
        engine.finish()
        XCTAssertEqual(player.currentTrack, tracks[2])
    }

    func testUnreadableTrackIsSkipped() {
        engine.failing = [tracks[1].url]
        player.play(queue: tracks, startingAt: 0)
        engine.finish()
        XCTAssertEqual(player.currentTrack, tracks[2])
        XCTAssertTrue(player.isPlaying)
    }

    func testUnreadableStartTrackSkipsForward() {
        engine.failing = [tracks[0].url]
        player.play(queue: tracks, startingAt: 0)
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertTrue(player.isPlaying)
    }

    func testUnreadableStartAtEndWrapsToFirst() {
        engine.failing = [tracks[3].url]
        player.play(queue: tracks, startingAt: 3)
        XCTAssertEqual(player.currentTrack, tracks[0])
        XCTAssertTrue(player.isPlaying)
    }

    func testAllUnreadableStops() {
        engine.failing = Set(tracks.map(\.url))
        player.play(queue: tracks, startingAt: 0)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(engine.loaded, [])
        XCTAssertNil(player.currentTrack)
        player.togglePlayPause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(engine.playing)
    }

    func testCycleRepeat() {
        XCTAssertEqual(player.repeatMode, .off)
        player.cycleRepeat(); XCTAssertEqual(player.repeatMode, .all)
        player.cycleRepeat(); XCTAssertEqual(player.repeatMode, .one)
        player.cycleRepeat(); XCTAssertEqual(player.repeatMode, .off)
    }

    func testSettingsPersist() {
        player.volume = 0.3
        player.shuffle = true
        player.repeatMode = .one
        let again = PlayerModel(engine: FakeAudioEngine(), defaults: defaults)
        XCTAssertEqual(again.volume, 0.3)
        XCTAssertTrue(again.shuffle)
        XCTAssertEqual(again.repeatMode, .one)
    }

    func testVolumeDefaultsToOneAndReachesEngine() {
        XCTAssertEqual(player.volume, 1)
        player.volume = 0.5
        XCTAssertEqual(engine.volume, 0.5)
    }

    // MARK: - Скачивание

    func testPlayRemoteTrackDownloadsThenPlays() async {
        remote(0)
        player.play(queue: tracks, startingAt: 0)
        XCTAssertTrue(engine.loaded.isEmpty)
        XCTAssertTrue(player.isDownloading)
        XCTAssertEqual(downloader.requested, [tracks[0].url])
        downloader.complete(tracks[0].url)
        await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url])
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.isDownloading)
        XCTAssertEqual(player.currentTrack?.download, .local)
    }

    func testOnDemandTrackIsFetchedBeforePlay() async {
        tracks[0].download = .onDemand
        player.play(queue: tracks, startingAt: 0)
        XCTAssertEqual(downloader.requested, [tracks[0].url])
        XCTAssertTrue(engine.loaded.isEmpty)
        downloader.complete(tracks[0].url)
        await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url])
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.currentTrack?.download, .local)
    }

    func testOnDemandFetchFailureKeepsOnDemand() async {
        tracks[0].download = .onDemand
        downloader.failing = [tracks[0].url]
        player.play(queue: tracks, startingAt: 0)
        await settle()
        XCTAssertEqual(player.currentTrack?.download, .onDemand, "строка не сереет после сбоя провайдера")
    }

    func testPrefetchesNextOnDemand() {
        tracks[2].download = .onDemand
        player.play(queue: tracks, startingAt: 1)
        XCTAssertEqual(downloader.requested, [tracks[2].url])
    }

    func testPlayingPrefetchesNextRemote() {
        remote(2)
        player.play(queue: tracks, startingAt: 1)
        XCTAssertEqual(downloader.requested, [tracks[2].url])
        XCTAssertEqual(engine.loaded, [tracks[1].url])
    }

    func testPrefetchOnlyOneAhead() {
        remote(2); remote(3)
        player.play(queue: tracks, startingAt: 1)
        XCTAssertEqual(downloader.requested, [tracks[2].url])
    }

    func testNextToRemoteWaitsForDownload() async {
        remote(1)
        player.play(queue: tracks, startingAt: 0)
        XCTAssertEqual(downloader.requested, [tracks[1].url])
        player.next()
        XCTAssertEqual(engine.loaded, [tracks[0].url])
        XCTAssertTrue(player.isDownloading)
        XCTAssertEqual(player.duration, 0, "длина старого трека не показывается")
        downloader.complete(tracks[1].url)
        await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url, tracks[1].url])
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(downloader.requested, [tracks[1].url], "префетч не дублируется")
    }

    func testDownloadFailureLeavesTrackRemoteAndPlayerIdle() async {
        remote(0)
        downloader.failing = [tracks[0].url]
        player.play(queue: tracks, startingAt: 0)
        await settle()
        XCTAssertFalse(player.isDownloading)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTrack?.download, .remote)
        XCTAssertTrue(engine.loaded.isEmpty)
        player.next()
        XCTAssertEqual(engine.loaded, [tracks[1].url])
        XCTAssertTrue(player.isPlaying)
    }

    func testMarkDownloadedUpdatesQueue() {
        remote(2)
        player.play(queue: tracks, startingAt: 0)
        player.markDownloaded(tracks[2].url)
        XCTAssertEqual(player.queue[2].download, .local)
    }

    func testPlayAfterFailedDownloadRetriesInsteadOfResumingOldTrack() async {
        remote(1)
        downloader.failing = [tracks[1].url]
        player.play(queue: tracks, startingAt: 0)  // префетч t1 падает сразу
        player.next()                               // и ожидание t1 падает
        await settle()
        XCTAssertEqual(player.currentTrack?.url, tracks[1].url)
        XCTAssertFalse(player.isDownloading)
        downloader.failing = []
        player.togglePlayPause()
        XCTAssertEqual(downloader.requested, [tracks[1].url, tracks[1].url, tracks[1].url])
        XCTAssertFalse(engine.playing, "старый трек не возобновляется")
        XCTAssertTrue(player.isDownloading)
        downloader.complete(tracks[1].url)
        await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url, tracks[1].url])
        XCTAssertTrue(engine.playing)
        XCTAssertTrue(player.isPlaying)
    }

    func testPreviousDuringDownloadStepsBack() {
        remote(1)
        player.play(queue: tracks, startingAt: 0)
        engine.currentTime = 10
        player.next()
        player.previous()
        XCTAssertEqual(player.currentTrack, tracks[0])
        XCTAssertEqual(engine.loaded, [tracks[0].url, tracks[0].url])
        XCTAssertFalse(player.isDownloading)
    }

    func testStaleDownloadCompletionDoesNotLoadOldTarget() async {
        remote(1); remote(2)
        player.play(queue: tracks, startingAt: 0)
        player.next()
        player.next()
        downloader.complete(tracks[1].url)
        await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url])
        XCTAssertEqual(player.currentTrack?.url, tracks[2].url)
        XCTAssertTrue(player.isDownloading)
        downloader.complete(tracks[2].url)
        await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url, tracks[2].url])
        XCTAssertTrue(player.isPlaying)
    }

    func testRateDefaultsToOneAndCycles() {
        XCTAssertEqual(player.rate, 1)
        var seen: [Float] = []
        for _ in 0..<5 { player.cycleRate(); seen.append(player.rate) }
        XCTAssertEqual(seen, [1.25, 1.5, 2, 0.75, 1])
        XCTAssertEqual(engine.rate, 1)
        XCTAssertEqual(defaults.float(forKey: "rate"), 1)
    }

    func testRatePersistsAndAppliesToEngine() {
        player.cycleRate()   // 1.25
        XCTAssertEqual(engine.rate, 1.25)
        let engine2 = FakeAudioEngine()
        let player2 = PlayerModel(engine: engine2, downloader: downloader, defaults: defaults)
        XCTAssertEqual(player2.rate, 1.25)
        XCTAssertEqual(engine2.rate, 1.25)
    }

    func testSleepMinutesSetsDeadlineAndPausesOnTick() throws {
        player.play(queue: tracks, startingAt: 0)
        let before = Date()
        player.sleep = .minutes(15)
        let deadline = try XCTUnwrap(player.sleepDeadline)
        XCTAssertEqual(deadline.timeIntervalSince(before), 15 * 60, accuracy: 1)
        player.tick(now: deadline.addingTimeInterval(-1))
        XCTAssertTrue(player.isPlaying)
        player.tick(now: deadline)
        XCTAssertFalse(player.isPlaying)
        XCTAssertFalse(engine.playing)
        XCTAssertEqual(player.sleep, .off)
        XCTAssertNil(player.sleepDeadline)
    }

    func testSleepOffClearsDeadline() {
        player.sleep = .minutes(30)
        player.sleep = .off
        XCTAssertNil(player.sleepDeadline)
    }

    func testSleepEndOfTrackStopsEvenWithRepeatOne() {
        player.play(queue: tracks, startingAt: 1)
        player.repeatMode = .one
        player.sleep = .endOfTrack
        engine.finish()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTrack, tracks[1])
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(engine.loaded, [tracks[1].url])   // не перезагружен
        XCTAssertEqual(player.sleep, .off)
    }

    // MARK: - Продолжение после перезапуска

    private func state() -> PlaybackState? {
        defaults.data(forKey: "playback").flatMap { try? JSONDecoder().decode(PlaybackState.self, from: $0) }
    }

    func testPauseSeekAndTrackChangePersistState() throws {
        XCTAssertNil(state())
        player.play(queue: tracks, startingAt: 1)
        engine.currentTime = 17
        player.seek(to: 17)
        player.togglePlayPause()
        let s = try XCTUnwrap(state())
        XCTAssertEqual(s.urls, tracks.map(\.url.path))
        XCTAssertEqual(s.currentIndex, 1)
        XCTAssertEqual(s.position, 17)
    }

    func testTickPersistsEveryFiveSeconds() {
        player.play(queue: tracks, startingAt: 0)
        engine.currentTime = 3; player.tick(now: Date())
        XCTAssertEqual(state()?.position, 0)        // смена трека сохранила 0, тик в 3 с — ещё нет
        engine.currentTime = 6; player.tick(now: Date())
        XCTAssertEqual(state()?.position, 6)
    }

    func testRestoreRebuildsQueuePausedAtPosition() async {
        player.play(queue: tracks, startingAt: 1)
        engine.currentTime = 17; player.seek(to: 17); player.togglePlayPause()
        let engine2 = FakeAudioEngine()
        let player2 = PlayerModel(engine: engine2, downloader: downloader, defaults: defaults)
        let loader = FakeTrackLoader(); for t in tracks { loader.tracks[t.url] = t }
        await player2.restore(using: loader)
        XCTAssertEqual(player2.queue, tracks)
        XCTAssertEqual(player2.currentTrack, tracks[1])
        XCTAssertEqual(player2.currentTime, 17)
        XCTAssertEqual(engine2.currentTime, 17)
        XCTAssertEqual(engine2.loaded, [tracks[1].url])
        XCTAssertFalse(engine2.playing)
        XCTAssertFalse(player2.isPlaying)
    }

    func testRestoreDropsMissingFilesAndGivesUpWithoutCurrent() async {
        player.play(queue: tracks, startingAt: 1); player.togglePlayPause()
        // текущего нет → пусто, ключ остаётся
        var player2 = PlayerModel(engine: FakeAudioEngine(), downloader: downloader, defaults: defaults)
        let loader = FakeTrackLoader(); loader.tracks[tracks[0].url] = tracks[0]
        await player2.restore(using: loader)
        XCTAssertNil(player2.currentTrack); XCTAssertTrue(player2.queue.isEmpty)
        XCTAssertNotNil(state())
        // нет третьего → очередь без него
        loader.tracks[tracks[1].url] = tracks[1]; loader.tracks[tracks[3].url] = tracks[3]
        player2 = PlayerModel(engine: FakeAudioEngine(), downloader: downloader, defaults: defaults)
        await player2.restore(using: loader)
        XCTAssertEqual(player2.queue, [tracks[0], tracks[1], tracks[3]])
        XCTAssertEqual(player2.currentTrack, tracks[1])
    }

    func testRestoreRemoteCurrentDownloadsOnPlay() async {
        player.play(queue: tracks, startingAt: 1)
        engine.currentTime = 17; player.seek(to: 17); player.togglePlayPause()
        let engine2 = FakeAudioEngine()
        let player2 = PlayerModel(engine: engine2, downloader: downloader, defaults: defaults)
        let loader = FakeTrackLoader(); for t in tracks { loader.tracks[t.url] = t }
        remote(1); loader.tracks[tracks[1].url] = tracks[1]
        await player2.restore(using: loader)
        XCTAssertEqual(player2.currentTrack?.url, tracks[1].url)
        XCTAssertTrue(engine2.loaded.isEmpty)
        XCTAssertEqual(player2.currentTime, 0)
        player2.togglePlayPause()
        XCTAssertEqual(downloader.requested, [tracks[1].url])
        downloader.complete(tracks[1].url); await settle()
        XCTAssertEqual(engine2.loaded, [tracks[1].url]); XCTAssertTrue(engine2.playing)
    }

    func testRestoreWithUnloadableCurrentKeepsQueue() async {
        player.play(queue: tracks, startingAt: 1); player.togglePlayPause()
        let engine2 = FakeAudioEngine(); engine2.failing = [tracks[1].url]
        let player2 = PlayerModel(engine: engine2, downloader: downloader, defaults: defaults)
        let loader = FakeTrackLoader(); for t in tracks { loader.tracks[t.url] = t }
        await player2.restore(using: loader)
        XCTAssertEqual(player2.currentTrack, tracks[1]); XCTAssertEqual(player2.currentTime, 0)
        player2.togglePlayPause()                         // обычный путь: битый пропущен, играет следующий
        XCTAssertEqual(engine2.loaded, [tracks[2].url])
    }

    func testPersistDuringDownloadStoresZeroPosition() {
        player.play(queue: tracks, startingAt: 0)
        engine.currentTime = 40
        remote(1); player.play(queue: tracks, startingAt: 1)   // playAfterDownload
        XCTAssertEqual(state()?.currentIndex, 1); XCTAssertEqual(state()?.position, 0)
    }

    func testPersistIsNoopOnEmptyQueue() {
        player.persist()
        XCTAssertNil(state())
    }

    func testRestoreDoesNotOverrideTrackChosenWhileLoading() async {
        player.play(queue: tracks, startingAt: 1); player.togglePlayPause()
        let engine2 = FakeAudioEngine()
        let player2 = PlayerModel(engine: engine2, downloader: downloader, defaults: defaults)
        let loader = FakeTrackLoader(); for t in tracks { loader.tracks[t.url] = t }
        loader.gated = true
        let restoring = Task { await player2.restore(using: loader) }
        await settle()
        player2.play(queue: tracks, startingAt: 0)   // например, «Поделиться → Siply» на холодном старте
        loader.release()
        await restoring.value
        XCTAssertEqual(player2.currentTrack, tracks[0])
        XCTAssertTrue(player2.isPlaying)
        XCTAssertEqual(engine2.loaded, [tracks[0].url])
    }

    func testMarkEvictedMakesTrackRemoteAndNextDownloadsIt() async {
        player.play(queue: tracks, startingAt: 0)
        downloader.requested = []
        player.markEvicted(tracks[1].url)
        XCTAssertEqual(player.queue[1].download, .remote)
        player.next()
        XCTAssertEqual(downloader.requested, [tracks[1].url])
        XCTAssertEqual(engine.loaded, [tracks[0].url])
        downloader.complete(tracks[1].url); await settle()
        XCTAssertEqual(engine.loaded, [tracks[0].url, tracks[1].url])
    }

    func testMarkEvictedIgnoresCurrentTrack() {
        player.play(queue: tracks, startingAt: 0)
        player.markEvicted(tracks[0].url)
        XCTAssertEqual(player.queue[0].download, .local)
        XCTAssertTrue(player.isPlaying)
    }
}
