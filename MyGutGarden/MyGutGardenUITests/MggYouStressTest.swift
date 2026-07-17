//
//  MggYouStressTest.swift
//  MyGutGardenUITests — owner report (2026-07-17): "the app freezes and
//  crashes" around the You tab, on the same iPhone 17 Pro simulator where the
//  scripted happy-path passes. This test drives the You surface like a human:
//  answer the launch check-in, open/close every sheet, open the gas-comfort
//  menu, replay the tour, and switch tabs rapidly. A freeze surfaces as an
//  unresponsive-element timeout; a crash fails the test outright.
//

import XCTest

final class MggYouStressTest: XCTestCase {

    func testYouSurfaceEndToEnd() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25), "auth gate did not appear")
        email.tap(); email.typeText("ui-test@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("UiTest-12345!")
        app.buttons["Sign in"].tap()

        let youTab = app.tabBars.buttons["You"]
        for _ in 0..<10 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
            if youTab.exists { break }
            sleep(1)
        }
        XCTAssertTrue(youTab.waitForExistence(timeout: 20), "no tab bar")

        // If the daily check-in pop-up is up, ANSWER it (the human path) —
        // this also runs the guardian immediately after.
        if app.staticTexts["How did you feel? (directional — no wrong answer)"].waitForExistence(timeout: 6) {
            app.buttons["Great"].tap()
            sleep(2)
            // A guardian prompt may follow; close it via its visible buttons.
            for label in ["Not now", "Sounds good", "Keep my pace", "Got it", "No thanks"] {
                if app.buttons[label].exists { app.buttons[label].firstMatch.tap(); break }
            }
        }

        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8), "You page did not open")

        // 1. Daily check-in sheet: open, wait for content, close.
        app.buttons["Daily check-in"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 8), "check-in sheet did not open")
        sleep(2)                       // let its .task (prefs + meals) run
        XCTAssertTrue(app.buttons["Close"].isHittable, "check-in sheet froze")
        app.buttons["Close"].tap()

        // 2. Customize check-in: open + close.
        app.buttons["Customize check-in"].tap()
        sleep(2)
        for label in ["Done", "Close", "Save"] {
            if app.buttons[label].firstMatch.exists { app.buttons[label].firstMatch.tap(); break }
        }
        if app.buttons["Customize check-in"].waitForExistence(timeout: 4) == false {
            app.swipeDown()            // dismiss if still presented
        }

        // 3. Gas comfort menu: open it and pick the current value again.
        let gas = app.buttons["Gas comfort"].firstMatch
        if gas.exists {
            gas.tap()
            sleep(1)
            let first = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'balanced'")).firstMatch
            if first.exists { first.tap() } else { app.tap() }
        }

        // 4. Badges: open + close.
        XCTAssertTrue(app.buttons["Badges"].waitForExistence(timeout: 6), "You page lost after menu")
        app.buttons["Badges"].tap()
        sleep(2)
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown() }

        // 5. Foods you're keeping an eye on: open + close.
        app.buttons["Foods you're keeping an eye on"].tap()
        sleep(2)
        if app.buttons["Close"].exists { app.buttons["Close"].tap() } else { app.swipeDown() }

        // 6. Rapid tab switching (the freeze reported is around tab taps).
        for _ in 0..<3 {
            app.tabBars.buttons["Today"].tap()
            youTab.tap()
        }
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 6), "You page unresponsive after tab churn")

        // 7. Replay the intro tour from You (it walks to Today), then skip out.
        app.buttons["Replay the intro tour"].tap()
        if app.buttons["Skip"].waitForExistence(timeout: 8) {
            for _ in 0..<10 {
                if app.buttons["Skip"].exists { app.buttons["Skip"].tap(); usleep(400_000) } else { break }
            }
        }

        // Still alive and navigable?
        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 6), "app dead after tour replay")
    }
}
