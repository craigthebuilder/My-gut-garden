//
//  MggTourEscapeTest.swift
//  MyGutGardenUITests — owner screenshot (2026-07-17): app freezes tapping the
//  You tab while the INTRO TOUR is active (dim up, spotlight on the check-in
//  button = last step, glass tab-lens frozen mid-slide). The garden-freeze fix
//  only ever tested escaping via the Garden tab at step 1. This reproduces the
//  owner's exact state: mid-tour, tap You once — the app must switch and stay
//  responsive, at step 1 AND at the last step.
//

import XCTest

final class MggTourEscapeTest: XCTestCase {

    func testTapYouDuringIntroTour() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25))
        email.tap(); email.typeText("fable-e2e@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("FableE2e-12345!")
        app.buttons["Sign in"].tap()

        for _ in 0..<8 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap(); break }
            if app.tabBars.buttons["Today"].exists { break }
            sleep(1)
        }
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20), "no tab bar")

        // If a first-run tour auto-fired, clear it so the test owns tour state.
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 6) { skip.tap(); sleep(1) }

        // Start the tour deliberately from You → Replay (no DB seed needed).
        let youTab = app.tabBars.buttons["You"]
        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8), "You did not open")
        app.buttons["Replay the intro tour"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "intro tour did not start")

        // SCENARIO A — step 1 (tour yanked us to Today): tap You once, mid-tour.
        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8),
                      "FROZE: You did not open when tapped during the intro tour (step 1)")
        XCTAssertFalse(skip.exists, "tour did not end after the user navigated away")

        // SCENARIO B — the owner's screenshot state: LAST step (checkin), then You.
        app.buttons["Replay the intro tour"].tap()
        XCTAssertTrue(skip.waitForExistence(timeout: 10), "replayed tour did not start")
        // Advance to the last step ("Got it" replaces "Next").
        for _ in 0..<10 {
            if app.buttons["Got it"].exists { break }
            let next = app.buttons["Next"].firstMatch
            if next.exists && next.isHittable { next.tap() }
            usleep(700_000)
        }
        XCTAssertTrue(app.buttons["Got it"].waitForExistence(timeout: 5),
                      "never reached the last tour step")

        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8),
                      "FROZE: You did not open when tapped on the LAST tour step (owner's state)")
        XCTAssertFalse(app.buttons["Skip"].exists, "tour still up after navigating away")

        // Still responsive? Bounce once.
        app.tabBars.buttons["Today"].tap()
        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 6), "app unresponsive after tour escape")
    }
}
