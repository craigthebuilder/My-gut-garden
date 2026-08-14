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
        app.launchArguments += ["--mgg-reset-auth"]
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

        // Fiber moved OFF Today into the dashboard detail (owner, 2026-07-17);
        // Field guide + Garden explore rows were removed too. (Absence checks —
        // unaffected by any covering scrim.)
        XCTAssertFalse(app.staticTexts["Your fiber"].waitForExistence(timeout: 3),
                       "'Your fiber' should no longer be on the Today page")
        XCTAssertFalse(app.buttons["Field guide"].exists,
                       "'Field guide' explore row should be gone from Today")

        // Open the dashboard detail (the "Your dashboard" hero card). A launch
        // pop-up (daily check-in / celebration / guardian — all dismiss on a tap
        // outside their card) can appear a beat after launch and cover the card,
        // so interleave tap-outside with the tap until the detail opens.
        let dashBtn = app.buttons["Your dashboard"].firstMatch
        for _ in 0..<14 {
            if app.navigationBars["Your dashboard"].exists { break }
            // Clear a launch overlay via its own button first (answering the
            // check-in / accepting a celebration / declining a guardian nudge),
            // then, once clear, open the dashboard.
            var acted = false
            for label in ["Great", "Lovely", "Keep my pace", "Not now", "Not yet", "Got it"] {
                if app.buttons[label].exists { app.buttons[label].firstMatch.tap(); acted = true; break }
            }
            if !acted { if dashBtn.isHittable { dashBtn.tap() } }
            usleep(500_000)
        }
        XCTAssertTrue(app.navigationBars["Your dashboard"].waitForExistence(timeout: 8),
                      "did not open the dashboard detail")

        // DURABLE assertion (order-independent): ui-test is a veteran who hit 30
        // in a past week, so the goal MUST be unlocked — the dashboard's fiber
        // section must NOT show the locked "Your goal is coming" state. If the
        // ever-hit-30 unlock regressed, a veteran stays baseline_pending → fails.
        XCTAssertTrue(app.staticTexts["Your fiber"].waitForExistence(timeout: 8),
                      "dashboard did not show the 'Your fiber' section")
        XCTAssertFalse(app.staticTexts["Your goal is coming"].waitForExistence(timeout: 4),
                       "fiber goal still locked for a user who already hit 30 in a past week")
        let shot2 = XCTAttachment(screenshot: app.screenshot())
        shot2.name = "dashboard-fiber-section"; shot2.lifetime = .keepAlways; add(shot2)
    }
}
