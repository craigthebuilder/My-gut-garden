//
//  MggCheckInFormTest.swift
//  MyGutGardenUITests — drive the daily check-in form end-to-end the way a
//  human does (owner report 2026-07-17: freeze/crash around the You tab):
//  You → Daily check-in → Log a new check-in → add an entry in every visible
//  section → pick a time → save; then reopen an existing day (edit/prefill
//  path). Any hang or crash in these flows fails loudly here.
//

import XCTest

final class MggCheckInFormTest: XCTestCase {

    func testNewAndEditCheckInFlows() throws {
        let app = XCUIApplication()
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

        // A one-time celebration (e.g. "Your fiber goal is ready") can cover the
        // page on first sign-in after an unlock — dismiss it before interacting.
        if app.buttons["Lovely"].waitForExistence(timeout: 3) { app.buttons["Lovely"].tap() }

        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 8))

        // You → Daily check-in (history sheet). Retry through any lingering
        // overlay so the tap lands on the row, not a scrim.
        let daily = app.buttons["Daily check-in"].firstMatch
        for _ in 0..<5 {
            if app.buttons["Log a new check-in"].exists { break }
            if daily.isHittable { daily.tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap() }
            usleep(500_000)
        }
        let logNew = app.buttons["Log a new check-in"]
        XCTAssertTrue(logNew.waitForExistence(timeout: 10), "history sheet did not open")

        // → New check-in form.
        logNew.tap()
        XCTAssertTrue(app.staticTexts["Today's check-in"].waitForExistence(timeout: 10),
                      "new check-in form did not open")

        // Dump what the form offers (for the log), then drive it.
        let addButtons = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add ' AND label ENDSWITH ' entry'"))
        print("PROBE form add-buttons: \((0..<min(addButtons.count, 10)).map { addButtons.element(boundBy: $0).label })")

        // Add one entry per section (tap every visible "+").
        for i in 0..<min(addButtons.count, 6) {
            let b = addButtons.element(boundBy: i)
            if b.exists && b.isHittable { b.tap(); usleep(300_000) }
        }

        // Open the first time menu ("Add a time") and pick a time (shows a DatePicker).
        let timeMenu = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Add a time'")).firstMatch
        if timeMenu.waitForExistence(timeout: 3) {
            timeMenu.tap()
            let pick = app.buttons["Pick a time…"]
            if pick.waitForExistence(timeout: 4) { pick.tap(); sleep(1) }
        }

        // Save.
        let save = app.buttons["Save check-in"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 6), "no Save button on the form")
        save.tap()

        // Back on the history sheet; today's row should exist now.
        XCTAssertTrue(logNew.waitForExistence(timeout: 15), "form did not dismiss after save (hang?)")

        // Edit path: open the most recent day (prefill from persisted entries).
        let dayRow = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Tap to view' OR label CONTAINS 'stool' OR label CONTAINS 'mood'")).firstMatch
        XCTAssertTrue(dayRow.waitForExistence(timeout: 8), "no day rows in history")
        dayRow.tap()
        XCTAssertTrue(app.staticTexts["Edit check-in"].waitForExistence(timeout: 10),
                      "edit form did not open (prefill hang/crash?)")
        let close = app.buttons["Close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), "edit form has no Close")
        close.tap()

        // The history sheet itself needs an exit — this is the known missing-Close
        // defect; once fixed, Close must exist here too.
        XCTAssertTrue(logNew.waitForExistence(timeout: 6))
        let historyClose = app.buttons["Close"].firstMatch
        XCTAssertTrue(historyClose.waitForExistence(timeout: 4),
                      "check-in history sheet has no Close button (trap: no visible way out)")
        historyClose.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 6), "did not return to You")
    }
}
