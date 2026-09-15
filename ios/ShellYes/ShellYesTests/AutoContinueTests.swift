import XCTest
@testable import ShellYes

/// Which outcome banners auto-continue is allowed to dismiss.
///
/// The setting says whether the feature is on; this says what it may
/// touch. Two carve-outs, and both are about not taking a moment away
/// from the player: their own claim, and the shell that ends the game.
@MainActor
final class AutoContinueTests: XCTestCase {

    func test_aiClaim_autoContinues() {
        XCTAssertTrue(GameStore.AIEvent.took(actor: "Sandy", shell: 28, isFinal: false).autoContinues)
    }

    func test_aiSteal_autoContinues() {
        XCTAssertTrue(
            GameStore.AIEvent.stole(actor: "Sandy", victim: "You", shell: 28, isFinal: false)
                .autoContinues
        )
    }

    func test_aiBust_autoContinues() {
        XCTAssertTrue(GameStore.AIEvent.bust(actor: "Coco", burned: 33).autoContinues)
    }

    /// The player's own moment. They tap it away when they are done
    /// looking at it.
    func test_yourOwnClaim_waitsForATap() {
        XCTAssertFalse(GameStore.AIEvent.took(actor: "You", shell: 28, isFinal: false).autoContinues)
        XCTAssertFalse(
            GameStore.AIEvent.stole(actor: "You", victim: "Sandy", shell: 28, isFinal: false)
                .autoContinues
        )
        XCTAssertFalse(GameStore.AIEvent.bust(actor: "You", burned: 33).autoContinues)
    }

    /// The tally is waiting behind the last shell. Nobody gets dropped
    /// into the end of a game without touching the screen.
    func test_theShellThatEndsTheGame_waitsForATap() {
        XCTAssertFalse(GameStore.AIEvent.took(actor: "Sandy", shell: 28, isFinal: true).autoContinues)
        XCTAssertFalse(
            GameStore.AIEvent.stole(actor: "Sandy", victim: "You", shell: 28, isFinal: true)
                .autoContinues
        )
    }
}
