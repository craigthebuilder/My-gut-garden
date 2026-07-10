//
//  MggGardenLockedTest.swift
//  MyGutGardenUITests — reproduce the owner report (2026-07-10): "the app
//  freezes when I click the garden but it's not unlocked yet". Signs in as the
//  onboarded (locked) e2e account and taps the Garden tab; the locked view must
//  appear (a freeze / blocked tap → this times out).
//

import XCTest

final class MggGardenLockedTest: XCTestCase {

    func testTapGardenWhileLocked() throws {
        let app = XCUIApplication()
        app.launch()

        // Sign in (onboarded account → straight to the tab bar, maybe a tour).
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25), "auth gate did not appear")
        email.tap(); email.typeText("fable-e2e@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("FableE2e-12345!")
        app.buttons["Sign in"].tap()

        // Sweep the iOS "Save Password?" sheet if it appears.
        for _ in 0..<8 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap(); break }
            if app.tabBars.buttons["Garden"].exists { break }
            sleep(1)
        }

        let garden = app.tabBars.buttons["Garden"]
        XCTAssertTrue(garden.waitForExistence(timeout: 20), "no tab bar / not onboarded")

        // Tap Garden until the locked view appears. A launch pop-up (daily
        // check-in / guardian) can cover the tab bar, so the first tap only
        // dismisses it; a coach step can also intercept. Tap outside first, then
        // the tab — a real freeze (the bug) never reaches the locked view.
        let locked = app.staticTexts["Your garden is taking root"]
        for _ in 0..<8 {
            if locked.exists { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()  // dismiss any scrim
            garden.tap()
            sleep(1)
        }
        XCTAssertTrue(locked.waitForExistence(timeout: 12),
                      "Garden tab did not show the locked view — blocked/frozen")

        // And prove the app is still responsive: switch away and back.
        app.tabBars.buttons["Today"].tap()
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 5),
                      "app unresponsive after Garden")
    }
}
