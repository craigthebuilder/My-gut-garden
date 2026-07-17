//
//  MggYouTabTest.swift
//  MyGutGardenUITests — reproduce two owner reports (2026-07-17):
//  1. "the notification that my keystones are blooming appears even though I've
//     already seen it a million times" — the launch recompute re-celebrated
//     already-persisted district unlocks (in-memory `previously` is empty at
//     launch), so every open replayed "New district unlocked!".
//  2. "there's a bug when I try to click on the you tab" — the celebration /
//     check-in scrims covered the tab bar, so the tap dismissed a modal
//     instead of switching tabs.
//  Uses ui-test (tier-2, 4 districts unlocked weeks ago — the owner's state).
//

import XCTest

final class MggYouTabTest: XCTestCase {

    func testNoRepeatUnlockCelebrationAndYouTabOpens() throws {
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

        // 1. Districts were unlocked weeks ago — launching must NOT re-celebrate.
        XCTAssertFalse(app.staticTexts["New district unlocked!"].waitForExistence(timeout: 4),
                       "district unlock re-celebrated on launch (already seen long ago)")

        // 2. If the daily check-in pop-up is due (ui-test had a meal yesterday),
        //    leave it ON SCREEN — the strongest version of the next assertion.
        //    (It only fires when yesterday had meals, so it's best-effort here;
        //    MggYouStressTest covers the answer path.)
        _ = app.staticTexts["How did you feel? (directional — no wrong answer)"].waitForExistence(timeout: 6)

        // 3. One tap on You must switch tabs — even with a modal showing, shell
        //    modals never cover the tab bar.
        youTab.tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 6),
                      "You page did not open on the first tap of the You tab (modal blocked it)")
    }
}
