//
//  MggFiberUnlockTest.swift
//  MyGutGardenUITests — audit fix (2026-07-17): the fiber goal must unlock for
//  anyone who has EVER hit a 30-plant week, not only in the current week.
//  ui-test hit 30 in a past week (garden already open, 4 districts) but stayed
//  baseline_pending. Signing in on the fixed build must fire the one-time
//  "Your fiber goal is ready" celebration, and Today must show the inline
//  fiber section. Screenshots Today for the moved-charts review.
//

import XCTest

final class MggFiberUnlockTest: XCTestCase {

    func testFiberGoalUnlocksForVeteranAndDashboardShowsFiber() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25))
        email.tap(); email.typeText("ui-test@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("UiTest-12345!")
        app.buttons["Sign in"].tap()

        for _ in 0..<10 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
            if app.tabBars.buttons["Today"].exists { break }
            sleep(1)
        }
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no tab bar")

        // Screenshot the landing (may be the one-time "Your fiber goal is ready"
        // celebration if this run is the first to unlock ui-test).
        let shot1 = XCTAttachment(screenshot: app.screenshot())
        shot1.name = "after-signin"; shot1.lifetime = .keepAlways; add(shot1)

        // Dismiss any celebration so it doesn't cover the page.
        for label in ["Lovely", "Close"] {
            if app.buttons[label].waitForExistence(timeout: 3) { app.buttons[label].firstMatch.tap(); break }
        }

        // DURABLE assertion (order-independent): ui-test is a veteran who hit 30
        // in a past week, so the goal MUST be unlocked — the Today fiber section
        // must NOT show the locked "Your goal is coming" state. If the ever-hit-30
        // unlock regressed, a veteran stays baseline_pending and this fails.
        XCTAssertTrue(app.staticTexts["Your fiber"].waitForExistence(timeout: 8),
                      "Today did not show the inline 'Your fiber' section")
        XCTAssertFalse(app.staticTexts["Your goal is coming"].waitForExistence(timeout: 4),
                       "fiber goal still locked for a user who already hit 30 in a past week")
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "today-fiber-section"; shot2.lifetime = .keepAlways; add(shot2)
    }
}
