//
//  MggFlowScreenshots.swift
//  MyGutGardenUITests, runtime click-through of the Phase 2 app. Signs in as a
//  pre-seeded onboarded user against the live backend and walks the new surfaces
//  (Thrive Today/Check-in/Your-Foods, the daily check-in, then switches to
//  Survive and opens the logger), screenshotting each. It is a crash-detection
//  smoke test: visiting a surface loads its views, so a view that crashes on
//  appear fails the run. Not a CI gate, a verification aid.
//

import XCTest

final class MggFlowScreenshots: XCTestCase {

    func testClickThrough() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launch()

        func snap(_ name: String) {
            let shot = XCUIScreen.main.screenshot()
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? shot.pngRepresentation.write(to: docs.appendingPathComponent("\(name).png"))
            let att = XCTAttachment(screenshot: shot)
            att.name = name
            att.lifetime = .keepAlways
            add(att)
        }
        @discardableResult
        func tapTab(_ label: String) -> Bool {
            let b = app.tabBars.buttons[label]
            if b.waitForExistence(timeout: 6) { b.tap(); sleep(2); return true }
            return false
        }
        @discardableResult
        func tapButtonIfExists(_ label: String, timeout: TimeInterval = 4) -> Bool {
            let b = app.buttons[label]
            if b.waitForExistence(timeout: timeout) { b.tap(); sleep(2); return true }
            return false
        }
        func dismissSheet() {
            for label in ["Close", "Cancel", "Done", "Save check-in"] where app.buttons[label].exists {
                app.buttons[label].tap(); sleep(1); return
            }
            app.swipeDown(velocity: .fast); sleep(1)
        }

        // 1) Auth gate (hard asserts: this is the load-bearing path)
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25), "auth gate did not appear")
        snap("01-auth-gate")
        email.tap(); email.typeText("ui-test@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("UiTest-12345!")
        app.buttons["Sign in"].tap()
        XCTAssertTrue(email.waitForNonExistence(timeout: 35), "sign-in did not leave the auth gate")
        sleep(5) // profile + reference data load
        snap("02-thrive-home")

        // 2) Thrive: walk every tab present (incl. the new Check-in tab)
        for (label, name) in [("Snap", "03-thrive-snap"), ("Check-in", "04-thrive-checkin"),
                              ("Garden", "05-thrive-garden"), ("You", "06-thrive-you")] {
            if tapTab(label) { snap(name) }
        }

        // 3) Back to Today: the daily check-in + Your-Foods surfaces
        if tapTab("Today") {
            snap("07-thrive-today")
            if tapButtonIfExists("Log your daily check-in") { snap("08-thrive-daily-checkin"); dismissSheet() }
            // "Your foods" is a nav row (button or static text)
            let yf = app.buttons["Your foods"].exists ? app.buttons["Your foods"] : app.staticTexts["Your foods"]
            if yf.waitForExistence(timeout: 4) { yf.tap(); sleep(2); snap("09-thrive-your-foods")
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap(); sleep(1) }
            }
        }

        // 4) Switch to Survive (You → Go back to basics → confirm)
        if tapTab("You") {
            if tapButtonIfExists("Go back to basics (Survive)") {
                _ = tapButtonIfExists("Start Survive", timeout: 4)
                sleep(6)
                snap("10-survive-home")
            }
        }

        // 5) Survive: the logger + food surface (best-effort labels)
        _ = tapTab("Today")
        snap("11-survive-today")
        for label in ["Log tonight's check-in", "Log today's check-in", "Log your daily check-in"] {
            if tapButtonIfExists(label) { snap("12-survive-logger"); dismissSheet(); break }
        }
        for label in ["Foods you're checking", "Your foods", "Give your gut a break"] {
            let el = app.buttons[label].exists ? app.buttons[label] : app.staticTexts[label]
            if el.waitForExistence(timeout: 3) { el.tap(); sleep(2); snap("13-survive-\(label.prefix(8))")
                if app.navigationBars.buttons.firstMatch.exists { app.navigationBars.buttons.firstMatch.tap(); sleep(1) }
            }
        }
        snap("14-final")
    }
}
