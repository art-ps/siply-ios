import XCTest
@testable import Siply

final class FileActionTests: XCTestCase {
    func testFileActions() {
        XCTAssertEqual(FileAction.available(isUbiquitous: false, state: .local), [])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, state: .local), [.evict])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, state: .remote), [.download])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, state: .downloading), [])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, state: .onDemand), [])
    }

    func testFolderActions() {
        XCTAssertEqual(FileAction.available(isUbiquitous: false, folderState: .local, fileStates: [.remote, .local]), [])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, folderState: .remote, fileStates: []), [.download])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, folderState: .local, fileStates: [.remote]), [.download])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, folderState: .local, fileStates: [.local]), [.evict])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, folderState: .local, fileStates: [.local, .remote]), [.download, .evict])
        XCTAssertEqual(FileAction.available(isUbiquitous: true, folderState: .local, fileStates: []), [])
    }
}
