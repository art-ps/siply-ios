import XCTest
@testable import Siply

@MainActor
final class SearchIndexTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tmp: TempDir!
    private var appFolder: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SiplySearchIndexTests")!
        defaults.removePersistentDomain(forName: "SiplySearchIndexTests")
        tmp = TempDir()
        appFolder = tmp.dir("App")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SiplySearchIndexTests")
        super.tearDown()
    }

    private func makeStore() -> SourceStore { SourceStore(defaults: defaults, appFolder: appFolder) }

    private func touch(_ rel: String) {
        let u = appFolder.appendingPathComponent(rel)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data().write(to: u)
    }

    func testFindsByFileAndFolderName() async {
        touch("Кино/Курю.mp3"); touch("Кино/01.mp3"); touch("Other/Song.flac"); touch("Other/Кино 2.mp3")
        let index = SearchIndex(store: makeStore())
        let hits = await index.search("кино")
        XCTAssertEqual(hits.map(\.url.lastPathComponent), ["Кино", "Кино 2.mp3"])   // Курю.mp3 внутри Кино — не по имени файла
        XCTAssertEqual(hits.map(\.isFolder), [true, false])
        let song = await index.search("song")
        XCTAssertEqual(song.map(\.url.lastPathComponent), ["Song.flac"])
    }

    func testHiddenAndNonAudioSkipped() async {
        touch(".hidden/x.mp3"); touch("notes.txt"); touch("x.mp3")
        let index = SearchIndex(store: makeStore())
        let x = await index.search("x")
        XCTAssertEqual(x.map(\.url.lastPathComponent), ["x.mp3"])
        let notes = await index.search("notes")
        XCTAssertTrue(notes.isEmpty)
    }

    func testUnavailableSourceSkipped() async {
        touch("a.mp3")
        let second = tmp.dir("Second")
        _ = tmp.file("Second/ab.mp3")
        makeStore().add(folder: second)
        try! FileManager.default.removeItem(at: second)
        let store = makeStore()
        XCTAssertEqual(store.sources.count, 2)
        let hits = await SearchIndex(store: store).search("a")
        XCTAssertEqual(hits.map(\.url.lastPathComponent), ["a.mp3"])
        XCTAssertEqual(hits.first?.source, store.sources[0])
    }

    func testSecondQueryDoesNotWalkAgain() async {
        touch("a.mp3")
        let index = SearchIndex(store: makeStore())
        _ = await index.search("a")
        _ = await index.search("b")
        XCTAssertEqual(index.walkCount, 1)
        index.invalidate()
        _ = await index.search("a")
        XCTAssertEqual(index.walkCount, 2)
    }

    func testBlankQueryReturnsNothingWithoutWalking() async {
        touch("a.mp3")
        let index = SearchIndex(store: makeStore())
        let hits = await index.search("  ")
        XCTAssertTrue(hits.isEmpty)
        XCTAssertEqual(index.walkCount, 0)
    }

    func testLimit200() async {
        for i in 1...250 { touch("many/a\(i).mp3") }
        let hits = await SearchIndex(store: makeStore()).search("a")
        XCTAssertEqual(hits.count, 200)
    }
}
