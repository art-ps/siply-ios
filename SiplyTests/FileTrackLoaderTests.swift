import XCTest
@testable import Siply

final class FileTrackLoaderTests: XCTestCase {
    func testFileOutsideAppFolderIsOnDemandByName() async {
        let app = TempDir(), other = TempDir()
        let file = other.file("03 Глава.mp3", Data("garbage".utf8))
        let t = await FileTrackLoader(appFolder: app.url).track(at: file)
        XCTAssertEqual(t?.download, .onDemand)
        XCTAssertEqual(t?.title, "03 Глава")
    }

    func testFileInsideAppFolderIsLoaded() async throws {
        let app = TempDir()
        let file = app.dir("sub").appendingPathComponent("a.wav")
        try AudioFixtures.writeWav(to: file)
        let t = await FileTrackLoader(appFolder: app.url).track(at: file)
        XCTAssertEqual(t?.download, .local)
        XCTAssertGreaterThan(t?.duration ?? 0, 0)
    }

    func testMissingFileIsNil() async {
        let app = TempDir()
        let t = await FileTrackLoader(appFolder: app.url).track(at: app.url.appendingPathComponent("nope.mp3"))
        XCTAssertNil(t)
    }
}
