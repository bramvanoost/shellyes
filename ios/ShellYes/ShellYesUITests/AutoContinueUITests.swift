import XCTest

/// Auto-continue, end to end: a bot's outcome banner leaves on its own
/// and nobody touches the screen.
///
/// The policy lives in a unit test (`AutoContinueTests`); what only a
/// running app can prove is the part in between — the countdown starts
/// when the banner appears and the banner is gone when it ends.
final class AutoContinueUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launch(autoContinue: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode", "-seed", "aiBanner",
            "-ching.autoContinue", autoContinue ? "YES" : "NO",
            // Fast pace so the dwell is the 2.2s floor, not 3.7s.
            "-ching.gameSpeed", "fast",
        ]
        app.launch()
        // The splash slides its buttons in. Tapping one while it is
        // still arriving does nothing at all, which is why the capture
        // suite waits this long before touching anything.
        Thread.sleep(forTimeInterval: 4)
        let newGame = app.buttons
            .matching(NSPredicate(format: "label ==[c] %@", "New Game"))
            .firstMatch
        XCTAssertTrue(newGame.waitForExistence(timeout: 20), "no New Game button")
        newGame.tap()

        // Proves the tap landed. Without this a missed tap reads later
        // as "the banner never appeared", which sends you looking in
        // the wrong place entirely.
        let roll = app.buttons
            .matching(NSPredicate(format: "label ==[c] %@", "Roll On"))
            .firstMatch
        XCTAssertTrue(roll.waitForExistence(timeout: 20), "never reached the board")
        return app
    }

    private func banner(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS[c] 'claimed a shell'"))
            .firstMatch
    }

    func test_anAIBannerLeavesOnItsOwn() throws {
        let app = launch(autoContinue: true)
        let note = banner(app)
        XCTAssertTrue(note.waitForExistence(timeout: 20), "the seeded banner never appeared")

        // From here nothing is tapped. 2.2s of countdown plus slack for
        // the fade and a loaded CI machine.
        let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: note)
        wait(for: [gone], timeout: 8)
    }

    /// The other half of the claim: with the setting off, the banner is
    /// still sitting there waiting for a tap.
    func test_withTheSettingOff_theBannerWaits() throws {
        let app = launch(autoContinue: false)
        let note = banner(app)
        XCTAssertTrue(note.waitForExistence(timeout: 20), "the seeded banner never appeared")

        Thread.sleep(forTimeInterval: 6)
        XCTAssertTrue(note.exists, "the banner dismissed itself with auto-continue off")
    }
}
