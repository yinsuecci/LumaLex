import XCTest
@testable import LumaLex

final class PlaybackModeTests: XCTestCase {
    func testSequentialStopsAtEnd() {
        XCTAssertEqual(PlaybackMode.sequential.nextIndex(after: 0, count: 2), 1)
        XCTAssertNil(PlaybackMode.sequential.nextIndex(after: 1, count: 2))
    }
    func testRepeatModes() {
        XCTAssertEqual(PlaybackMode.repeatOne.nextIndex(after: 1, count: 2), 1)
        XCTAssertEqual(PlaybackMode.repeatAll.nextIndex(after: 1, count: 2), 0)
        XCTAssertEqual(PlaybackMode.repeatAll.nextIndex(after: 0, count: 1), 0)
        XCTAssertNil(PlaybackMode.repeatAll.nextIndex(after: 0, count: 0))
    }
}
