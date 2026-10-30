import XCTest
@testable import Siply

@MainActor
final class FileOpenerTests: XCTestCase {
    private var dir: TempDir!
    private var store: SourceStore!
    private var player: PlayerModel!

    override func setUp() async throws {
        try await super.setUp()
        let defaults = UserDefaults(suiteName: "SiplyFileOpenerTests")!
        defaults.removePersistentDomain(forName: "SiplyFileOpenerTests")
        dir = TempDir()
        for name in ["01 A.wav", "02 B.wav", "03 C.wav"] {
            try AudioFixtures.writeWav(to: dir.url.appendingPathComponent(name))
        }
        _ = dir.file("04 Bad.mp3", Data("garbage".utf8))
        try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("sub"),
                                                withIntermediateDirectories: true)
        store = SourceStore(defaults: defaults, appFolder: dir.url)
        player = PlayerModel(engine: FakeAudioEngine(), defaults: defaults)
    }

    func testOpenInsideSourcePlaysWholeFolder() async {
        let route = await FileOpener.open(dir.url.appendingPathComponent("02 B.wav"), store: store, player: player)
        XCTAssertEqual(player.queue.map { $0.url.lastPathComponent }, ["01 A.wav", "02 B.wav", "03 C.wav"])
        XCTAssertEqual(player.currentTrack?.url.lastPathComponent, "02 B.wav")
        XCTAssertEqual(route, FolderRoute(folder: dir.url.standardizedFileURL, source: store.sources[0]))
    }

    func testOpenOutsideSourcesPlaysSingle() async throws {
        let other = TempDir()
        let file = other.url.appendingPathComponent("x.wav")
        try AudioFixtures.writeWav(to: file)
        let route = await FileOpener.open(file, store: store, player: player)
        XCTAssertEqual(player.queue.count, 1)
        XCTAssertEqual(player.currentTrack?.url.lastPathComponent, "x.wav")
        XCTAssertNil(route)
    }

    func testOpenMatchesNonStandardizedURL() async {
        let odd = dir.url.appendingPathComponent("sub/../02 B.wav")
        _ = await FileOpener.open(odd, store: store, player: player)
        XCTAssertEqual(player.currentTrack?.url.lastPathComponent, "02 B.wav")
    }

    func testOpenMatchesPrivateSymlinkPrefix() async throws {
        // На устройстве /var — симлинк на /private/var, в середине пути; здесь та же ситуация через свой симлинк
        let other = TempDir()
        let link = other.url.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dir.url.deletingLastPathComponent())
        let file = link.appendingPathComponent(dir.url.lastPathComponent).appendingPathComponent("02 B.wav")
        let route = await FileOpener.open(file, store: store, player: player)
        XCTAssertEqual(player.queue.count, 3)
        XCTAssertEqual(player.currentTrack?.url.lastPathComponent, "02 B.wav")
        XCTAssertEqual(route?.source, store.sources[0])
    }

    func testAppDeclaresAudioDocumentTypes() {
        let types = (Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []
        let utis = Set(types.flatMap { $0["LSItemContentTypes"] as? [String] ?? [] })
        XCTAssertEqual(utis, ["public.mp3", "public.mpeg-4-audio", "public.aac-audio", "org.xiph.flac",
                              "com.microsoft.waveform-audio", "public.aiff-audio", "public.aifc-audio",
                              "com.apple.coreaudio-format"])
        XCTAssertEqual(Bundle.main.infoDictionary?["LSSupportsOpeningDocumentsInPlace"] as? Bool, true)
    }
}
