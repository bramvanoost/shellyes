import XCTest

/// Captures the App Store screenshots.
///
/// Each shot gets its own launch. Board states are seeded through the
/// DEBUG-only `-seed` launch argument rather than the ladybug menu,
/// because tapping that menu would leave its button visible in the
/// corner of every capture. `-screenshotMode` hides it.
///
/// Run on a 6.9" device (iPhone 17 Pro Max, 1320x2868) with
/// `-parallel-testing-enabled NO`; the cloned simulators the parallel
/// runner spawns fail to launch the test runner.
///
/// Attachments land in the .xcresult; export them with
/// `xcrun xcresulttool export attachments`.
@MainActor
final class ScreenshotTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// `.stampButton()` uppercases its title, and that carries into the
    /// accessibility label, so match case-insensitively rather than
    /// hard-coding the rendered casing at every call site.
    private func button(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label ==[c] %@", label))
            .firstMatch
    }

    private func tap(_ app: XCUIApplication, _ label: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        let element = button(app, label)
        XCTAssertTrue(element.waitForExistence(timeout: 15),
                      "no button labelled \(label)", file: file, line: line)
        element.tap()
    }

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Animations here are long and deliberate (splash slide-in, roll
    /// settle, banner entrance, the counting ceremony), so the captures
    /// need to wait them out rather than race them.
    private func settle(_ seconds: TimeInterval = 1.8) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func launch(seed: String? = nil, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshotMode"]
        if let seed { app.launchArguments += ["-seed", seed] }
        app.launchArguments += extra
        app.launch()
        settle(4.0)
        return app
    }

    /// Enters a game and waits for the board to settle.
    private func startGame(_ app: XCUIApplication) {
        tap(app, "New Game")
        XCTAssertTrue(button(app, "Roll On").waitForExistence(timeout: 15),
                      "board never appeared")
        settle(3.0)
    }

    func testSplash() throws {
        let app = launch()
        shoot("01-splash")
    }

    func testHowToPlay() throws {
        let app = launch()
        tap(app, "How to Play")
        settle()
        shoot("02-how-to-play")
    }

    func testBoardAndRoll() throws {
        let app = launch()
        startGame(app)
        shoot("03-board")

        tap(app, "Roll On")
        settle(3.0)
        shoot("04-roll")
    }

    func testSeededVaults() throws {
        let app = launch(seed: "vaults")
        startGame(app)
        shoot("05-vaults")
    }

    func testSeededSteal() throws {
        let app = launch(seed: "steal")
        startGame(app)
        settle(1.5)
        shoot("06-steal")
    }

    func testSeededTally() throws {
        let app = launch(seed: "tally")
        startGame(app)
        settle(4.0)
        shoot("07-tally")
    }

    /// The splash with a mid-table standing under the Leaderboards
    /// button. The simulator has no Game Center account, so the rank
    /// is handed in by launch argument.
    func testSplashStanding() throws {
        _ = launch(extra: ["-standings", "mid"])
        shoot("08-splash-standing")
    }

    /// The same line at rank one: crown, gold, Top Banana.
    func testSplashTopBanana() throws {
        _ = launch(extra: ["-standings", "top"])
        shoot("09-splash-top-banana")
    }

    /// The one-time offer to leave Easy, on the tally where it appears.
    /// `-forceDifficultyNudge` stands in for the ten finished games
    /// its real gate wants.
    func testDifficultyNudge() throws {
        let app = launch(seed: "tally", extra: ["-forceDifficultyNudge"])
        startGame(app)
        // The card animates in a beat after the New Game button, which
        // itself waits out the whole counting ceremony. Waiting on the
        // element beats guessing at the total.
        let headline = app.staticTexts["deeper water?"]
        let appeared = headline.waitForExistence(timeout: 25)
        // Let the card finish fading in before the shutter.
        settle(1.2)
        shoot("10-difficulty-nudge")
        XCTAssertTrue(appeared, "nudge card never appeared")
    }
}
