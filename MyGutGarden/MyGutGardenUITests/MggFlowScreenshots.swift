//
//  MggFlowScreenshots.swift
//  MyGutGardenUITests — runtime click-through of the SINGLE-MODE app against
//  the live backend. Two flows:
//    A) a FRESH user (fable-e2e@…, admin-created, never onboarded) walks the
//       whole intake — goals, basics (activity menu row), reaction chips +
//       food search, checks + the "Thanks for telling us" modal — lands on
//       Today, and meets the spotlight intro tour (Next / Back / Skip).
//    B) the pre-seeded onboarded user (ui-test@…) runs the SAMPLE-MEAL snap
//       end-to-end (the recognize pipeline) and revisits the revamped Today.
//  Screenshots land in the runner's Documents; it is a crash-detection smoke
//  test + verification aid, not a CI gate.
//

import XCTest

final class MggFlowScreenshots: XCTestCase {

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? shot.pngRepresentation.write(to: docs.appendingPathComponent("\(name).png"))
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    @discardableResult
    private func tapIfExists(_ element: XCUIElement, timeout: TimeInterval = 4, settle: UInt32 = 1) -> Bool {
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        sleep(settle)
        return true
    }

    private func signIn(_ app: XCUIApplication, email: String, password: String) {
        let emailField = app.textFields["Email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 25), "auth gate did not appear")
        emailField.tap(); emailField.typeText(email)
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5)); pw.tap(); pw.typeText(password)
        app.buttons["Sign in"].tap()
        XCTAssertTrue(emailField.waitForNonExistence(timeout: 35), "sign-in did not leave the auth gate")
        // The system "Save Password?" sheet invisibly blocks every later tap and
        // can appear several seconds after the gate leaves — sweep until gone.
        for _ in 0..<8 {
            if app.buttons["Not Now"].exists { app.buttons["Not Now"].tap(); sleep(1); break }
            sleep(2)
            if !app.buttons["Not Now"].exists && (app.buttons["Begin"].isHittable
                || app.tabBars.buttons["Today"].isHittable) { break }
        }
    }

    /// Dismiss whatever soft overlay is up (password sheet, daily pop-up,
    /// celebration, coach). Overlays can stack, so sweep a few rounds.
    private func clearOverlays(_ app: XCUIApplication) {
        for _ in 0..<3 {
            var tapped = false
            for label in ["Not Now", "Great", "Close", "Lovely", "Skip", "Got it"]
            where app.buttons[label].exists && app.buttons[label].isHittable {
                app.buttons[label].tap(); sleep(1); tapped = true; break
            }
            if !tapped { break }
        }
    }

    // MARK: A — fresh-user onboarding + the spotlight intro tour

    func testA_OnboardingWalkthrough() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--mgg-reset-auth"]
        app.launch()

        signIn(app, email: "fable-e2e@mygutgarden.test", password: "FableE2e-12345!")
        sleep(3)

        // Welcome ("Grow a garden you can eat")
        snap(app, "A01-welcome")
        guard tapIfExists(app.buttons["Begin"], timeout: 10, settle: 2) else {
            // Already onboarded from a previous run: nothing more to walk here.
            snap(app, "A01b-already-onboarded")
            return
        }

        // Q1 goals
        tapIfExists(app.buttons["Ease bloating"])
        snap(app, "A02-goals")
        tapIfExists(app.buttons["Continue"], settle: 2)

        // Q2 basics: drive the Activity menu row to the two-word option.
        snap(app, "A03-basics-default")
        if tapIfExists(app.otherElements["Activity level"], timeout: 3)
            || tapIfExists(app.buttons["Activity level"], timeout: 2) {
            tapIfExists(app.buttons["Moderately active"], timeout: 4)
        }
        snap(app, "A04-basics-moderately-active")
        tapIfExists(app.buttons["Continue"], settle: 2)

        // Q3 baseline
        snap(app, "A05-baseline")
        tapIfExists(app.buttons["Continue"], settle: 2)

        // Q4 reaction chips + the expanded food search
        snap(app, "A06-flags-chips")
        tapIfExists(app.buttons["Lactose"])
        let search = app.textFields["e.g. lentils"]
        if search.waitForExistence(timeout: 4) {
            search.tap(); search.typeText("chicken")
            sleep(2)
            snap(app, "A07-flags-search-chicken")
            tapIfExists(app.buttons["Chicken"], timeout: 4)
        }
        snap(app, "A08-flags-list")
        tapIfExists(app.buttons["Continue"], settle: 2)

        // Q5 checks → the medical-only "Thanks for telling us" modal
        tapIfExists(app.buttons["IBD (Crohn's or colitis)"], timeout: 4)
            || tapIfExists(app.staticTexts["IBD (Crohn's or colitis)"], timeout: 2)
        tapIfExists(app.buttons["Continue"], settle: 2)
        snap(app, "A09-thanks-for-telling-us")
        tapIfExists(app.buttons["I understand, continue"], timeout: 4, settle: 2)

        // Q6 (2026-07-09): name your gut gardener → Continue with the default.
        snap(app, "A09b-name-gardener")
        tapIfExists(app.buttons["Continue"], timeout: 4, settle: 2)

        // Summary → Start growing → the 3-frame story → home + the intro tour
        snap(app, "A10-summary")
        tapIfExists(app.buttons["Start growing"], timeout: 6, settle: 4)

        // The intro story (why → catch → meet the gardener) plays before the
        // tour; skip/swipe through it until the tab bar appears.
        for _ in 0..<6 {
            if app.tabBars.buttons["Today"].exists { break }
            if app.buttons["Skip intro"].exists { app.buttons["Skip intro"].tap() }
            else if app.buttons["Let's grow"].exists { app.buttons["Let's grow"].tap() }
            else if app.buttons["Next"].exists { app.buttons["Next"].tap() }
            sleep(1)
        }
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 20),
                      "onboarding did not land on the tab bar")
        sleep(3)
        snap(app, "A11-intro-step1")
        if tapIfExists(app.buttons["Next"], timeout: 6, settle: 2) {
            snap(app, "A12-intro-step2")
            if tapIfExists(app.buttons["Back"], timeout: 3, settle: 2) {
                snap(app, "A13-intro-back-to-step1")
                tapIfExists(app.buttons["Next"], timeout: 3, settle: 2)
            }
            tapIfExists(app.buttons["Next"], timeout: 3, settle: 2)   // step 3 (walks to Snap tab)
            snap(app, "A14-intro-step3-snap-tab")
            tapIfExists(app.buttons["Skip"], timeout: 3, settle: 2)
        }

        // Fresh user: the LOCKED fiber line shows (owner round 2), but NO fiber
        // NUMBER may leak before the unlock (SPEC §10 / Fence 5).
        tapIfExists(app.tabBars.buttons["Today"], timeout: 5, settle: 2)
        clearOverlays(app)
        let numericFiber = app.staticTexts.matching(
            NSPredicate(format: "label MATCHES %@", ".*[0-9]+ */ *[0-9]+ *g.*"))
        XCTAssertEqual(numericFiber.count, 0, "a fiber NUMBER leaked onto Today before the unlock")
        XCTAssertTrue(app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'unlocks after'")).count > 0,
            "the locked fiber line should show pre-unlock")
        snap(app, "A15-today-fresh-locked-fiber")
    }

    // MARK: B — sample-meal snap end-to-end + the revamped Today

    func testB_SampleMealAndToday() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments += ["--mgg-reset-auth"]
        app.launch()

        signIn(app, email: "ui-test@mygutgarden.test", password: "UiTest-12345!")
        sleep(5)
        clearOverlays(app)
        snap(app, "B01-today-dashboard")

        // The reported regression: sample meal → recognize → logged insight.
        XCTAssertTrue(tapIfExists(app.tabBars.buttons["Snap"], timeout: 8, settle: 2))
        clearOverlays(app)
        XCTAssertTrue(tapIfExists(app.buttons["Use a sample meal"], timeout: 8, settle: 2),
                      "sample-meal entry point missing")
        snap(app, "B02-sample-preview")
        XCTAssertTrue(tapIfExists(app.buttons["Use this photo"], timeout: 6, settle: 2),
                      "preview accept (checkmark) missing")
        // recognizing → auto-log → insight. Poll for the spinner to clear.
        let recognizing = app.staticTexts["Reading your plate…"]
        _ = recognizing.waitForExistence(timeout: 4)
        XCTAssertTrue(recognizing.waitForNonExistence(timeout: 40),
                      "recognition never finished — the recognize pipeline is still failing")
        sleep(3)
        clearOverlays(app)
        snap(app, "B03-sample-result")

        // Back to Today: the dashboard should reflect the fresh meal.
        tapIfExists(app.tabBars.buttons["Today"], timeout: 6, settle: 3)
        clearOverlays(app)
        snap(app, "B04-today-after-snap")

        // Explore rows: Field guide + Garden route to their tabs.
        for (label, name) in [("Field Guide", "B05-fieldguide-tab"),
                              ("Garden", "B06-garden-tab"),
                              ("You", "B07-you-tab")] {
            if tapIfExists(app.tabBars.buttons[label], timeout: 5, settle: 2) {
                clearOverlays(app)
                snap(app, name)
            }
        }
    }
}
