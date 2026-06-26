//
//  MggFlowScreenshots.swift
//  MyGutGardenUITests — runtime click-through of the Phase 1 app. Signs in as a
//  pre-seeded onboarded user against the live backend, walks the Thrive surfaces,
//  and writes a screenshot per step into the runner's Documents (pulled by the
//  host afterwards). Not a CI gate — a verification aid.
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

        // 1) Auth gate
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25), "auth gate did not appear")
        snap("01-auth-gate")

        email.tap()
        email.typeText("ui-test@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5))
        pw.tap()
        pw.typeText("UiTest-12345!")
        app.buttons["Sign in"].tap()

        // 2) Leaving the auth gate (onboarded user → mode tabs)
        XCTAssertTrue(email.waitForNonExistence(timeout: 35), "sign-in did not navigate away from the auth gate")
        sleep(5) // let profile + reference data load
        snap("02-thrive-home")

        // 3–5) Walk the tabs (each conditional so one missing tab won't abort)
        for (label, name) in [("Snap", "03-snap"), ("Garden", "04-guild-garden"), ("You", "05-you")] {
            let button = app.tabBars.buttons[label]
            if button.waitForExistence(timeout: 8) {
                button.tap()
                sleep(3)
                snap(name)
            }
        }
    }
}
