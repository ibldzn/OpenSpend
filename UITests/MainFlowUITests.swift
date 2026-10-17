import XCTest

/// Walks the main flow from a clean install and keeps a screenshot per step.
final class MainFlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    func testOnboardingAccountAndFirstExpense() {
        shot("01-onboarding")
        app.buttons["Skip"].tap()
        shot("02-onboarding-notifications")
        app.buttons["Continue without notifications"].tap()

        XCTAssertTrue(app.staticTexts["Create your first account"].waitForExistence(timeout: 5))
        shot("03-account-type")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Local'")).firstMatch.tap()
        let name = app.textFields["Account name"]
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.tap()
        name.typeText("Personal")
        shot("04-account-name")
        app.buttons["Create Account"].tap()

        let add = app.buttons["Add Expense"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        shot("05-home-empty")
        add.tap()

        let title = app.textFields["What is the expense about?"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap()
        title.typeText("Morning coffee")
        let amount = app.textFields["0"]
        amount.tap()
        amount.typeText("4.5")
        app.buttons["Food"].firstMatch.tap()
        app.buttons["Card"].firstMatch.tap()
        shot("06-new-expense")
        app.buttons["Save Expense"].tap()

        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Morning coffee'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("Food · Card"), "manual category/payment picks must survive Smart Suggestions")
        shot("07-home-with-expense")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        shot("08-settings")
    }

    /// Captures the main screens with sample data, for design review.
    func testDemoScreens() {
        app.terminate()
        app.launchArguments = ["-uiTesting", "-seedDemo"]
        app.launch()

        let coffee = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Morning coffee'")).firstMatch
        XCTAssertTrue(app.buttons["Add Expense"].waitForExistence(timeout: 5))
        sleep(1)
        shot("10-home")
        // Coordinate taps prove the pill really receives touches, then assert the selection moved.
        app.buttons["Week"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        sleep(1)
        XCTAssertTrue(app.buttons["Week"].isSelected, "Week pill should be selected after a tap")
        shot("11-home-week")
        app.buttons["Month"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

        // Lists only keep visible rows; scroll until the expense appears (needed at large text).
        for _ in 0..<6 where !coffee.isHittable { app.swipeUp() }
        XCTAssertTrue(coffee.waitForExistence(timeout: 3))
        coffee.tap()
        sleep(1)
        shot("16-edit-expense")
        app.swipeUp()
        shot("17-edit-expense-more")
        app.buttons["Cancel"].tap()
        app.swipeUp()
        sleep(1)
        shot("12-home-transactions")

        app.buttons["Account: Personal"].tap()
        sleep(1)
        shot("13-account-menu")
        app.buttons["Manage Accounts"].tap()
        sleep(1)
        shot("14-manage-accounts")
        app.buttons["Done"].tap()

        app.buttons["Search"].tap()
        app.typeText("coffee")
        sleep(1)
        shot("15-search")
        // Closing the active search field (iOS shows Close or Cancel) closes the screen.
        let close = app.buttons.matching(NSPredicate(format: "label IN {'Close', 'Cancel'}")).firstMatch
        if close.exists { close.tap() } else { app.buttons["Done"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["Add Expense"].waitForExistence(timeout: 3), "search should close in one tap")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        sleep(1)
        shot("18-settings")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Personal'")).firstMatch.tap()
        sleep(1)
        shot("19-account-settings")
        app.buttons["Categories"].tap()
        sleep(1)
        shot("20-categories")
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
