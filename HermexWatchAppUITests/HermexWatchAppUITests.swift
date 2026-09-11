import XCTest

final class HermexWatchAppUITests: XCTestCase {
    func testFirstRunShowsSetupWithoutFabricatedActivity() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["Hermex"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Set up on iPhone"].exists)
        XCTAssertFalse(app.staticTexts["Active session"].exists)
        XCTAssertFalse(app.staticTexts["1 activity"].exists)
    }
}
