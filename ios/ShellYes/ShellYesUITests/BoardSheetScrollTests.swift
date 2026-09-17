import XCTest

/// The two things about the board sheet that only a real gesture can
/// settle: that a board longer than its box scrolls its names without
/// the sheet paging away underneath, and that a plain rank gets one
/// page rather than a pager with a missing half.
///
/// The scroll one matters because the rows live inside the sheet's own
/// vertical pager. Two vertical scroll views stacked on each other is
/// exactly the arrangement where the wrong one takes the pan, and no
/// amount of reading `ViewThatFits` settles which.
@MainActor
final class BoardSheetScrollTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func settle(_ seconds: TimeInterval = 1.2) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func shoot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label ==[c] %@", label))
            .firstMatch
    }

    /// A row by its accessibility label, which is "20. Nim, 59".
    private func row(_ app: XCUIApplication, rank: Int) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(rank). "))
            .firstMatch
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-playerName", "Bram",
            "-boardCard",
        ] + extra
        app.launch()
        settle(4.0)
        return app
    }

    /// Twenty rows in a box that holds about ten. Swiping over the
    /// names has to move the names.
    func testALongBoardScrollsItsNamesInPlace() throws {
        let app = launch(["-standings", "top", "-shareCard", "weekly", "-boardRows", "20"])

        let boardHeading = text(app, "easy · this week")
        let toBoard = text(app, "back to the board")

        XCTAssertTrue(boardHeading.waitForExistence(timeout: 15),
                      "the sheet never showed the board")
        let deep = row(app, rank: 20)
        XCTAssertFalse(deep.isHittable,
                       "the last row was on screen before scrolling — the board is not long enough to prove anything")
        shoot("scroll-1-top-of-list")

        // Deliberately not `app.swipeUp()`. That starts at the centre
        // of the *screen*, which on this page is below the card, over
        // the sand the pager owns — so it pages the sheet, correctly,
        // and proves nothing about the list. The drag has to begin on
        // the names, which sit in the upper third.
        //
        // More than one pass because a flick moves the list by about a
        // drag's length, not to the end of it. Each pass re-checks that
        // the *sheet* has not moved, which is the half of this that can
        // actually regress.
        let onTheNames = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.30))
        let above = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12))
        for pass in 1...5 {
            onTheNames.press(forDuration: 0.05, thenDragTo: above)
            settle()
            XCTAssertTrue(boardHeading.isHittable,
                          "the sheet paged away instead of scrolling the list (swipe \(pass))")
            XCTAssertFalse(toBoard.isHittable,
                           "the swipe reached the card page instead of scrolling the rows (swipe \(pass))")
            if deep.isHittable { break }
        }
        shoot("scroll-2-scrolled")

        XCTAssertTrue(deep.isHittable,
                      "swiping over the names did not scroll the list to its end")
    }

    /// The card is still reachable from a long board: the rows take the
    /// swipe, so the written affordance is the way down and it has to
    /// work.
    func testTheCardIsStillReachableFromALongBoard() throws {
        let app = launch(["-standings", "top", "-shareCard", "weekly", "-boardRows", "20"])

        let toCard = text(app, "share your crown")
        let toBoard = text(app, "back to the board")

        XCTAssertTrue(toCard.waitForExistence(timeout: 15))
        XCTAssertTrue(toCard.isHittable,
                      "the way down to the card was pushed off screen by the long list")
        toCard.tap()
        settle()
        XCTAssertTrue(toBoard.isHittable,
                      "share your crown did not move to the card")
    }

    /// Below rank one there is nothing to crown, so there is no second
    /// page and no invitation to one.
    func testAPlainRankGetsTheBoardAndNothingElse() throws {
        let app = launch(["-standings", "mid", "-shareCard", "ranked"])

        let boardHeading = text(app, "easy · this week")
        let toCard = text(app, "share your crown")

        XCTAssertTrue(boardHeading.waitForExistence(timeout: 15),
                      "tapping a plain rank never showed the board")
        shoot("ranked-1-board-only")
        XCTAssertFalse(toCard.exists,
                       "a plain rank was offered a crown to share")

        app.swipeUp()
        settle()
        XCTAssertTrue(boardHeading.isHittable,
                      "the one-page sheet scrolled away to nothing")
        XCTAssertFalse(text(app, "back to the board").exists,
                       "a card page existed below a plain rank")
    }
}
