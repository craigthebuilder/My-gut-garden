//
//  MggSignupTest.swift
//  MyGutGardenUITests — reproduce the owner report (2026-07-09): "I still am
//  not able to create an account outside the apple sign in." Drives the exact
//  auth-gate UI: fresh email → Create account → expect to land past the gate
//  (onboarding welcome). On failure, dump whatever error text the gate shows.
//

import XCTest

final class MggSignupTest: XCTestCase {

    func testEmailCreateAccount() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25), "auth gate did not appear")
        email.tap()
        email.typeText("carlosesber00+uisignup\(Int(Date().timeIntervalSince1970))@gmail.com")

        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5))
        pw.tap()
        pw.typeText("UiSignup-12345!")

        app.buttons["Create account"].tap()

        // The iOS "Save Password?" sheet invisibly blocks taps — sweep it.
        for _ in 0..<10 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap(); break }
            if app.buttons["Begin"].exists { break }
            sleep(1)
        }

        let arrived = app.buttons["Begin"].waitForExistence(timeout: 20)
        if !arrived {
            var seen: [String] = []
            for i in 0..<min(app.staticTexts.count, 30) {
                let t = app.staticTexts.element(boundBy: i).label
                if !t.isEmpty { seen.append(t) }
            }
            XCTFail("Signup did not reach onboarding. Gate shows: \(seen.joined(separator: " | "))")
        }
    }
}
