import XCTest
@testable import Siply

final class FolderRowTests: XCTestCase {
    private func track(_ name: String, _ state: DownloadState) -> Track {
        var t = Track(url: URL(fileURLWithPath: "/tmp/\(name).mp3"))
        t.download = state
        return t
    }

    func testDimmedWhenAnyRemote() {
        XCTAssertTrue(FolderRowState.isDimmed(tracks: [track("a", .local), track("b", .remote)]))
        XCTAssertFalse(FolderRowState.isDimmed(tracks: [track("a", .local), track("b", .local)]))
        XCTAssertFalse(FolderRowState.isDimmed(tracks: []))
        XCTAssertFalse(FolderRowState.isDimmed(tracks: [track("a", .onDemand)]))
    }
}
