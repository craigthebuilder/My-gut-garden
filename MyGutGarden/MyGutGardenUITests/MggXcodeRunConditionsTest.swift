//
//  MggXcodeRunConditionsTest.swift
//  MyGutGardenUITests — replicate Xcode-Run conditions (2026-07-17). Both of
//  the owner's AttributeGraph freezes happened in debugger-attached Xcode
//  runs; plain test runs never reproduced them. Xcode injects the Main Thread
//  Checker into Run builds — inject it here too, then churn the You surface
//  (the wedge site) hard: tab flips, the gas-comfort dialog, sheet open/close.
//

import XCTest

final class MggXcodeRunConditionsTest: XCTestCase {

    func testYouSurfaceUnderMainThreadChecker() throws {
        let app = XCUIApplication()
        let mtc = "/Applications/Xcode.app/Contents/Developer/usr/lib/libMainThreadChecker.dylib"
        if FileManager.default.fileExists(atPath: mtc) {
            app.launchEnvironment["DYLD_INSERT_LIBRARIES"] = mtc
        }
        app.launchArguments += ["--mgg-reset-auth"]
        app.launch()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25))
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
        XCTAssertTrue(youTab.waitForExistence(timeout: 20))
        if app.staticTexts["How did you feel? (directional — no wrong answer)"].waitForExistence(timeout: 6) {
            app.buttons["Great"].tap(); sleep(2)
        }

        // Churn: the re-render pressure that historically triggered the wedge.
        for round in 1...6 {
            youTab.tap()
            XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8),
                          "FROZE on You (round \(round))")
            app.tabBars.buttons["Today"].tap()
            usleep(400_000)
        }

        // Gas-comfort dialog under the same conditions.
        youTab.tap()
        let gas = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Gas comfort'")).firstMatch
        XCTAssertTrue(gas.waitForExistence(timeout: 8), "gas row missing")
        let dialog = app.sheets["Gas comfort"]
        for _ in 0..<8 {
            if dialog.exists { break }
            if gas.isHittable { gas.tap() }
            sleep(1)
        }
        XCTAssertTrue(dialog.waitForExistence(timeout: 4), "gas dialog did not open")
        let current = app.buttons.matching(NSPredicate(format: "label CONTAINS '✓'")).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 4)); current.tap()

        // Final responsiveness sweep.
        for _ in 1...3 {
            app.tabBars.buttons["Today"].tap()
            youTab.tap()
        }
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8), "unresponsive after churn")
    }
}
