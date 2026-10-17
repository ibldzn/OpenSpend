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
        app.navigationBars.buttons["Add"].tap()

        XCTAssertTrue(app.staticTexts["Morning coffee"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Food · Card"].exists, "manual category/payment picks must survive Smart Suggestions")
        shot("07-home-with-expense")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        shot("08-settings")
    }

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
