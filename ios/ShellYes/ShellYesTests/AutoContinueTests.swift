import XCTest
@testable import ShellYes

/// Which outcome banners auto-continue is allowed to dismiss.
///
/// The setting says whether the feature is on; this says what it may
/// touch. One carve-out now, and it is about where the banner leads
/// rather than about whose move it was: the shell that ends the game.
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

    /// Your own moment leaves on the same countdown as a bot's.
    ///
    /// It used to wait for a tap, on the reasoning that a thing you did
    /// is a thing you should get to look at. In practice a player with
    /// auto-continue on had asked not to tap, and being made to tap for
    /// their own claim and not for anyone else's read as the setting
    /// half working. The banner still shows its draining wave and a tap
    /// still dismisses early, so nothing is taken away — the 2.2s
    /// (3.74s on Slow) just runs without being asked to.
    func test_yourOwnClaim_autoContinues() {
        XCTAssertTrue(GameStore.AIEvent.took(actor: "You", shell: 28, isFinal: false).autoContinues)
        XCTAssertTrue(
            GameStore.AIEvent.stole(actor: "You", victim: "Sandy", shell: 28, isFinal: false)
                .autoContinues
        )
        XCTAssertTrue(GameStore.AIEvent.bust(actor: "You", burned: 33).autoContinues)
    }

    /// Casing is not a rule any more, but the actor name must not start
    /// mattering again by accident.
    func test_actorNameNoLongerDecidesAnything() {
        for actor in ["You", "you", "YOU", "Sandy", "sandy"] {
            XCTAssertTrue(
                GameStore.AIEvent.took(actor: actor, shell: 28, isFinal: false).autoContinues,
                "\(actor) should auto-continue like everyone else"
            )
            XCTAssertTrue(GameStore.AIEvent.bust(actor: actor, burned: 33).autoContinues)
        }
    }

    /// The tally is waiting behind the last shell. Nobody gets dropped
    /// into the end of a game without touching the screen — including
    /// the player who claimed it.
    func test_theShellThatEndsTheGame_waitsForATap() {
        XCTAssertFalse(GameStore.AIEvent.took(actor: "Sandy", shell: 28, isFinal: true).autoContinues)
        XCTAssertFalse(
            GameStore.AIEvent.stole(actor: "Sandy", victim: "You", shell: 28, isFinal: true)
                .autoContinues
        )
        XCTAssertFalse(GameStore.AIEvent.took(actor: "You", shell: 28, isFinal: true).autoContinues)
        XCTAssertFalse(
            GameStore.AIEvent.stole(actor: "You", victim: "Sandy", shell: 28, isFinal: true)
                .autoContinues
        )
    }
}
