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

    func testReadyPathOpensSessionsAndChatWithoutCrashing() {
        let app = XCUIApplication()
        app.launchArguments = ["HERMEX_WATCH_SCREENSHOT_FIXTURE"]
        app.launch()

        XCTAssertTrue(app.staticTexts["Stand-up notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Sessions"].exists)
        XCTAssertTrue(app.buttons["Open chat"].exists)

        app.buttons["Sessions"].tap()
        XCTAssertTrue(app.navigationBars["Sessions"].waitForExistence(timeout: 3)
            || app.staticTexts["Weekend plan"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Weekend plan"].exists)
        XCTAssertTrue(app.staticTexts["PR review"].exists)

        app.staticTexts["Weekend plan"].tap()
        XCTAssertTrue(
            app.buttons["Speak to Hermex"].waitForExistence(timeout: 5)
                || app.staticTexts["Speak"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Send"].exists)
    }

    func testPlusCreatesAndOpensANewSession() {
        let app = XCUIApplication()
        app.launchArguments = ["HERMEX_WATCH_SCREENSHOT_FIXTURE", "HERMEX_WATCH_SCREENSHOT_PAGE=sessions"]
        app.launch()

        XCTAssertTrue(app.navigationBars["Sessions"].waitForExistence(timeout: 5)
            || app.staticTexts["Weekend plan"].waitForExistence(timeout: 5))
        let create = app.buttons["createSession"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(
            app.navigationBars["New session"].waitForExistence(timeout: 5)
                || app.buttons["Speak to Hermex"].waitForExistence(timeout: 5)
                || app.buttons["Send"].waitForExistence(timeout: 5)
        )
    }
}
