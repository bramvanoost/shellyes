import XCTest
@testable import ShellYes

/// `GameCenterEntry` decides what a tap on Leaderboards or Achievements
/// actually does. Only the "no finished games yet" branch is testable
/// here, and deliberately so: it runs before anything touches GameKit,
/// so these tests need neither a signed build nor an account.
@MainActor
final class GameCenterEntryTests: XCTestCase {

    func test_open_withNoFinishedGames_showsTheEmptySheet() {
        for pane in GameCenterSheet.Pane.allCases {
            let entry = GameCenterEntry()

            entry.open(pane, from: .home, hasPlayed: false)

            XCTAssertEqual(entry.emptyPane, pane)
            // Apple's sheet must stay shut: a player with no score has
            // nothing to see there, and opening it would also drag a
            // sign-in prompt into a first run.
            XCTAssertNil(entry.pane)
            XCTAssertFalse(entry.showsUnavailableAlert)
        }
    }

    func test_open_withNoFinishedGames_neverAsksToSignIn() {
        let entry = GameCenterEntry()

        // The unavailable alert is the tell: it can only be set by the
        // branch that asked GameKit for a sign-in sheet and got none.
        entry.open(.leaderboards, from: .settings, hasPlayed: false)

        XCTAssertFalse(entry.showsUnavailableAlert)
    }
}
