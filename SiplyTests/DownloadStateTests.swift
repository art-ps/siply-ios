import XCTest
@testable import Siply

final class DownloadStateTests: XCTestCase {
    func testNotDownloadedIsRemote() {
        XCTAssertEqual(DownloadState(status: .notDownloaded), .remote)
    }

    func testCurrentIsLocal() {
        XCTAssertEqual(DownloadState(status: .current), .local)
    }

    func testDownloadedIsLocal() {
        XCTAssertEqual(DownloadState(status: .downloaded), .local)
    }

    func testNilIsLocal() {
        XCTAssertEqual(DownloadState(status: nil), .local)
    }

    func testOfLocalTempFileIsLocal() {
        let tmp = TempDir()
        let url = tmp.file("a.mp3", Data("x".utf8))
        XCTAssertEqual(DownloadState.of(url), .local)
    }
}
