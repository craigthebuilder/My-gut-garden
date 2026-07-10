//
//  MggPlantTourTest.swift
//  MyGutGardenUITests — reproduce the owner report (2026-07-10): "the plant
//  field guide tour is broken if you click it from the today page." Root cause:
//  the "plants" coach hint mapped to the Today tab, so when the plants section
//  tour fired (in the Field Guide's Plant Garden) onNavigate yanked the user to
//  Today — away from the tour's own anchor. The fix gates onNavigate to the
//  intro tour only. This test opens Plant Garden and asserts the plants tour
//  card appears AND the user stays on Plant Garden (no yank).
//

import XCTest

final class MggPlantTourTest: XCTestCase {

    func testPlantTourFromToday() throws {
        let app = XCUIApplication()
        app.launch()

        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 25), "auth gate did not appear")
        email.tap(); email.typeText("fable-e2e@mygutgarden.test")
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText("FableE2e-12345!")
        app.buttons["Sign in"].tap()

        // Land on the shell. Sweep the Save-Password sheet while waiting.
        let fieldGuideTab = app.tabBars.buttons["Field Guide"]
        for _ in 0..<10 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap() }
            if fieldGuideTab.exists { break }
            sleep(1)
        }
        XCTAssertTrue(fieldGuideTab.waitForExistence(timeout: 20), "no tab bar")

        // Open the Field Guide tab. A launch pop-up (daily check-in / guardian)
        // can cover the tab bar so the first tap only dismisses it; retry, tapping
        // outside first, until the Field Guide menu ("Plant Garden" row) appears.
        let plantGardenRow = app.staticTexts["Plant Garden"].firstMatch
        for _ in 0..<12 {
            if plantGardenRow.exists { break }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()  // dismiss any scrim
            fieldGuideTab.tap()
            usleep(700_000)
        }
        XCTAssertTrue(plantGardenRow.waitForExistence(timeout: 8), "did not reach the Field Guide's Plant Garden row")
        plantGardenRow.tap()
        XCTAssertTrue(app.navigationBars["Plant Garden"].waitForExistence(timeout: 8),
                      "did not open the Plant Garden")

        // The plants tour presents its first card…
        XCTAssertTrue(app.staticTexts["Your plant field guide"].waitForExistence(timeout: 8),
                      "plants tour card did not appear")

        // …and it must NOT yank the user back to Today (the reported bug: the
        // "plants" hint was mapped to the Today tab, so onNavigate fired a tab
        // switch away from the tour's own anchor).
        XCTAssertTrue(app.navigationBars["Plant Garden"].exists,
                      "plants tour navigated away from Plant Garden (the yank bug)")
    }
}
