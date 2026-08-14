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
        app.launchArguments += ["--mgg-reset-auth"]
        app.launch()

        // Two-step (2026-07-10): the landing's "Create account" navigates to a
        // DEDICATED create screen; the create screen's "Create account" submits.
        XCTAssertTrue(app.textFields["Email"].waitForExistence(timeout: 25), "auth gate did not appear")
        XCTAssertTrue(app.staticTexts["Relish"].exists, "did not start on the sign-in landing")
        app.buttons["Create account"].tap()   // → the create-account screen
        XCTAssertTrue(app.staticTexts["Create your account"].waitForExistence(timeout: 5),
                      "Create account did not open the dedicated create screen")

        let email = app.textFields["Email"]
        email.tap()
        email.typeText("carlosesber00+uisignup\(Int(Date().timeIntervalSince1970))@gmail.com")

        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5))
        pw.tap()
        pw.typeText("UiSignup-12345!")

        app.buttons["Create account"].firstMatch.tap()   // submit

        // Reached onboarding? Sweep the "Save Password?" sheet while waiting.
        var arrived = false
        for _ in 0..<20 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
            if app.buttons["Begin"].exists { arrived = true; break }
            sleep(1)
        }
        XCTAssertTrue(arrived, "Signup did not reach the onboarding welcome (Begin).")
    }
}
