import XCTest
@testable import Siply

@MainActor
final class SourceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tmp: TempDir!
    private var appFolder: URL!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SiplySourceStoreTests")!
        defaults.removePersistentDomain(forName: "SiplySourceStoreTests")
        tmp = TempDir()
        appFolder = tmp.dir("App")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SiplySourceStoreTests")
        super.tearDown()
    }

    private func makeStore() -> SourceStore { SourceStore(defaults: defaults, appFolder: appFolder) }

    func testAppFolderIsFirstAndOnly() {
        let store = makeStore()
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(store.sources[0].kind, .appFolder)
        XCTAssertEqual(store.sources[0].name, "Siply")
        XCTAssertEqual(store.url(of: store.sources[0]), appFolder)
    }

    func testAddPersistsAndRestores() {
        let music = tmp.dir("Music")
        makeStore().add(folder: music)
        let store = makeStore()
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertEqual(store.sources[1].name, "Music")
        XCTAssertEqual(store.url(of: store.sources[1])?.standardizedFileURL, music.standardizedFileURL)
        XCTAssertEqual(store.sources[0].id, makeStore().sources[0].id)
    }

    func testAddSameFolderTwiceKeepsOne() {
        let store = makeStore()
        let music = tmp.dir("Music")
        store.add(folder: music)
        store.add(folder: music)
        XCTAssertEqual(store.sources.count, 2)
    }

    func testRemoveDeletesFromListAndDefaults() {
        let store = makeStore()
        store.add(folder: tmp.dir("Music"))
        store.remove(store.sources[1])
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(makeStore().sources.count, 1)
    }

    func testRemoveAppFolderIsNoop() {
        let store = makeStore()
        store.remove(store.sources[0])
        XCTAssertEqual(store.sources.count, 1)
        XCTAssertEqual(makeStore().sources.count, 1)
    }

    func testBrokenBookmarkIsUnavailableNotCrash() {
        let broken = Source(id: UUID(), name: "Broken", kind: .bookmark(Data([1, 2, 3])))
        defaults.set(try! JSONEncoder().encode([broken]), forKey: "sources")
        let store = makeStore()
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertNil(store.url(of: store.sources[1]))
        XCTAssertFalse(store.isAvailable(store.sources[1]))
    }

    func testDeletedFolderIsUnavailable() {
        let music = tmp.dir("Music")
        makeStore().add(folder: music)
        try! FileManager.default.removeItem(at: music)
        let store = makeStore()
        XCTAssertEqual(store.sources.count, 2)
        XCTAssertFalse(store.isAvailable(store.sources[1]))
    }

    func testRefreshRecoversFolderThatReappeared() throws {
        let music = tmp.dir("Music")
        makeStore().add(folder: music)
        try FileManager.default.removeItem(at: music)
        let store = makeStore()   // запуск с вытащенной флешкой: bookmark не разрешился
        XCTAssertFalse(store.isAvailable(store.sources[1]))
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let revision = store.revision
        store.refresh()
        XCTAssertTrue(store.isAvailable(store.sources[1]))
        XCTAssertEqual(store.revision, revision + 1)
    }

    func testRenameTrimsAndPersists() {
        let store = makeStore()
        store.add(folder: tmp.dir("Music"))
        store.rename(store.sources[1], to: "  Книги ")
        XCTAssertEqual(store.sources[1].name, "Книги")
        XCTAssertEqual(makeStore().sources[1].name, "Книги")
    }

    func testRenameToBlankIsNoop() {
        let store = makeStore()
        store.add(folder: tmp.dir("Music"))
        store.rename(store.sources[1], to: "   ")
        XCTAssertEqual(store.sources[1].name, "Music")
    }

    func testUUIDNamedFolderIsCalledPapka() {
        let store = makeStore()
        store.add(folder: tmp.dir(UUID().uuidString))
        XCTAssertEqual(store.sources[1].name, "Папка")
    }
}
