import XCTest

/// Does the two-page share sheet actually snap?
///
/// The sheet is a vertical `ScrollView` with `.viewAligned` snapping
/// over two pages of deliberately different heights: the board is
/// 148pt shorter than the screen so the card's top edge peeks out
/// below it.
/// Unequal page heights are exactly where view-aligned snapping tends
/// to misbehave quietly, leaving a rest position halfway between the
/// two pages, and no amount of reading the code settles it. Only a real
/// gesture does, which is why this is a UI test and not a unit one.
///
/// Assertions deliberately avoid `stampButton` elements: that modifier
/// leaves an oversized accessibility frame, so `isHittable` on the
/// Share button is not evidence of anything. The plain text labels on
/// each page are.
@MainActor
final class ShareSheetPagingTests: XCTestCase {

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

    /// Case-insensitive, because `.textCase(.uppercase)` and
    /// `.stampButton()` both rewrite the rendered casing while the
    /// accessibility label keeps the source string.
    private func text(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        app.staticTexts
            .matching(NSPredicate(format: "label ==[c] %@", label))
            .firstMatch
    }

    private func openSheet() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-standings", "top",
            "-playerName", "Bram",
            "-shareCard", "weekly",
            // Without seeded rows the board is its empty state, which
            // is shorter and would not prove anything about where a
            // full page comes to rest.
            "-boardCard",
        ]
        app.launch()
        settle(4.0)
        return app
    }

    func testSheetOpensOnTheBoardAndSnapsBetweenPages() throws {
        let app = openSheet()

        let boardHeading = text(app, "easy · this week")
        let boardFootnote = text(app, "of 88 players")
        let toCard = text(app, "share your crown")
        let toBoard = text(app, "back to the board")

        // --- rest one: the board ---------------------------------
        XCTAssertTrue(boardHeading.waitForExistence(timeout: 15),
                      "the sheet never showed the board")
        shoot("paging-1-board")
        XCTAssertTrue(boardHeading.isHittable,
                      "sheet did not open on the board")
        XCTAssertTrue(toCard.isHittable,
                      "the way down to the card was not on screen")
        XCTAssertFalse(toBoard.isHittable,
                       "the card page was already on screen at rest one")

        // --- swipe up: the card ----------------------------------
        app.swipeUp()
        settle()
        shoot("paging-2-card")
        XCTAssertTrue(toBoard.isHittable,
                      "swiping up did not bring the card to rest")
        // The halfway detector. If the scroll stopped between pages,
        // the foot of the board card would still be on screen.
        XCTAssertFalse(boardFootnote.isHittable,
                       "the scroll came to rest between the two pages")
        XCTAssertFalse(boardHeading.isHittable,
                       "the board was still on screen after swiping to the card")

        // --- swipe down: the board again -------------------------
        app.swipeDown()
        settle()
        shoot("paging-3-board-again")
        XCTAssertTrue(boardHeading.isHittable,
                      "swiping down did not return to the board")
        XCTAssertFalse(toBoard.isHittable,
                       "the card was still on screen after swiping back")
    }

    /// The written affordances have to work as well as the gesture: on
    /// the card page a downward swipe is the system's sheet dismissal,
    /// so `back to the board` is the only way up that is ours.
    func testAffordancesMoveBetweenPages() throws {
        let app = openSheet()

        let boardHeading = text(app, "easy · this week")
        let toCard = text(app, "share your crown")
        let toBoard = text(app, "back to the board")

        XCTAssertTrue(toCard.waitForExistence(timeout: 15))
        toCard.tap()
        settle()
        XCTAssertTrue(toBoard.isHittable,
                      "share your crown did not move to the card")

        toBoard.tap()
        settle()
        XCTAssertTrue(boardHeading.isHittable,
                      "back to the board did not move to the board")
    }

    /// The peek is the affordance nobody can miss, so it has to be the
    /// one that works without reading: a tap on the card edge showing
    /// under the board brings the card up.
    func testTappingThePeekingCardBringsItUp() throws {
        let app = openSheet()

        let boardHeading = text(app, "easy · this week")
        let toBoard = text(app, "back to the board")
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Top Banana on Shell Yes"))
            .firstMatch

        XCTAssertTrue(boardHeading.waitForExistence(timeout: 15))
        XCTAssertTrue(card.waitForExistence(timeout: 5),
                      "the card was not reachable while the board was showing")

        card.tap()
        settle()
        XCTAssertTrue(toBoard.isHittable,
                      "tapping the peeking card did not bring it up")
        XCTAssertFalse(boardHeading.isHittable,
                       "the board was still on screen after tapping the card")
    }
}
