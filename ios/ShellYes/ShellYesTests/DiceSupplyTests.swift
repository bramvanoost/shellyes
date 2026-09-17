import XCTest
import ShellYesEngine
@testable import ShellYes

/// The dice supply invariant the dice tally row is drawn from.
///
/// `DiceStage` draws one slot per set-aside die plus one hollow slot per
/// die still in hand, so the row only reads correctly while those two
/// numbers sum to `TOTAL_DICE`. The engine holds that up; the view broke
/// it by freezing one of them and not the other during a bust, and drew
/// fifteen slots for an eight-die game.
///
/// These tests pin the engine half. The view half cannot be reached from
/// here — the freeze lives in SwiftUI `@State` — so this exists to make
/// the assumption explicit rather than to catch that bug again.
@MainActor
final class DiceSupplyTests: XCTestCase {

    private func makeStore(seed: UInt32 = 1) -> GameStore {
        GameStore(seed: seed, settings: SettingsStore())
    }

    func test_aFreshTurnHoldsTheWholeSupply() {
        let store = makeStore()

        XCTAssertEqual(store.state.diceInHand, TOTAL_DICE)
        XCTAssertTrue(store.state.setAside.isEmpty)
    }

    /// Picking moves dice from the hand to the set-aside pile and never
    /// invents or loses one. Several seeds, because which faces are
    /// available to pick is the random part.
    func test_setAsidePlusInHandAlwaysEqualsTheSupply() {
        for seed in UInt32(1)...UInt32(40) {
            let store = makeStore(seed: seed)

            for _ in 0..<12 {
                // Only the human's own turn is safe to drive by hand;
                // once it ends the seat changes and the supply resets.
                guard store.isHumanTurn, !store.isOver else { break }

                if store.state.phase == .roll {
                    store.apply(.roll)
                } else if let face = Face.allCases.first(where: { store.canPick($0) }) {
                    store.apply(.pick(face: face))
                } else {
                    break
                }

                guard store.isHumanTurn else { break }
                XCTAssertEqual(
                    store.state.setAside.count + store.state.diceInHand,
                    TOTAL_DICE,
                    "supply drifted on seed \(seed): "
                        + "\(store.state.setAside.count) set aside, "
                        + "\(store.state.diceInHand) in hand"
                )
            }
        }
    }

    /// A pick never takes more dice than the hand holds, which is the
    /// other way the sum could break.
    func test_theHandNeverGoesNegative() {
        for seed in UInt32(1)...UInt32(40) {
            let store = makeStore(seed: seed)

            for _ in 0..<12 {
                guard store.isHumanTurn, !store.isOver else { break }

                if store.state.phase == .roll {
                    store.apply(.roll)
                } else if let face = Face.allCases.first(where: { store.canPick($0) }) {
                    store.apply(.pick(face: face))
                } else {
                    break
                }

                XCTAssertGreaterThanOrEqual(store.state.diceInHand, 0, "seed \(seed)")
                XCTAssertLessThanOrEqual(store.state.diceInHand, TOTAL_DICE, "seed \(seed)")
            }
        }
    }
}
