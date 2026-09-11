import Observation
import XCTest
@testable import HermexWatchRoot

@MainActor
final class WatchRootModelTests: XCTestCase {
    func testStartsInSetupRequiredState() {
        let model = WatchRootModel()

        XCTAssertEqual(model.state, .setupRequired)
    }

    func testExplicitTransitionsExposeOnlyConnectionState() {
        let model = WatchRootModel()

        model.beginConnecting()
        XCTAssertEqual(model.state, .connecting)

        model.markUnavailable()
        XCTAssertEqual(model.state, .unavailable)
    }

    func testStateMutationNotifiesObservationTracking() {
        let model = WatchRootModel()
        let changed = expectation(description: "state observation changed")

        withObservationTracking {
            _ = model.state
        } onChange: {
            changed.fulfill()
        }

        model.beginConnecting()

        wait(for: [changed], timeout: 0.1)
    }

    func testSetupRequiredPresentationCopyIsTruthful() {
        let model = WatchRootModel()

        XCTAssertEqual(model.primaryMessage, "Set up on iPhone")
    }
}
