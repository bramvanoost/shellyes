import XCTest
@testable import ShellYesEngine

/// Mirrors `tests/odds.test.ts` case for case. The numbers are the
/// contract between the two engines; the parity harness proves they
/// agree, these prove they are right.
final class OddsTests: XCTestCase {

    // MARK: - bustChance

    func testBustChanceIsZeroWithNothingPicked() {
        XCTAssertEqual(bustChance(pickedCount: 0, diceInHand: 8), 0)
    }

    func testBustChanceIsOneInSixForOneDieOverOneDeadFace() {
        XCTAssertEqual(bustChance(pickedCount: 1, diceInHand: 1), 1.0 / 6.0, accuracy: 1e-12)
    }

    func testBustChanceCompoundsAcrossDice() {
        XCTAssertEqual(bustChance(pickedCount: 3, diceInHand: 2), 0.25, accuracy: 1e-12)
    }

    func testBustChanceIsCertainOnceEveryFaceIsSpent() {
        XCTAssertEqual(bustChance(pickedCount: 6, diceInHand: 4), 1)
    }

    // MARK: - expectedRollGain

    func testExpectedRollGainIsMeanBestFaceForOneFreshDie() {
        // Faces 1-5 score their pips, the coin scores 5: (1+2+3+4+5+5)/6.
        XCTAssertEqual(
            expectedRollGain(pickedFaces: [], diceInHand: 1),
            20.0 / 6.0,
            accuracy: 1e-12
        )
    }

    func testExpectedRollGainIsZeroWhenEveryFaceIsSpent() {
        let all: [Face] = [.one, .two, .three, .four, .five, .coin]
        XCTAssertEqual(expectedRollGain(pickedFaces: all, diceInHand: 5), 0)
    }

    func testExpectedRollGainIsZeroWithNoDiceLeft() {
        XCTAssertEqual(expectedRollGain(pickedFaces: [.one], diceInHand: 0), 0)
    }

    func testExpectedRollGainCountsOnlyLiveFaces() {
        // One die, coin already picked: the coin's 5 becomes a blank,
        // so the mean is (1+2+3+4+5+0)/6.
        XCTAssertEqual(
            expectedRollGain(pickedFaces: [.coin], diceInHand: 1),
            15.0 / 6.0,
            accuracy: 1e-12
        )
    }

    func testExpectedRollGainStaysInsideItsCeiling() {
        let ev = expectedRollGain(pickedFaces: [], diceInHand: 8)
        XCTAssertGreaterThan(ev, 0)
        XCTAssertLessThan(ev, 40)
    }

    func testExpectedRollGainFallsAsDiceLeaveTheHand() {
        let many = expectedRollGain(pickedFaces: [.coin], diceInHand: 6)
        let few = expectedRollGain(pickedFaces: [.coin], diceInHand: 2)
        XCTAssertGreaterThan(many, few)
    }

    // MARK: - keepOptions

    func testKeepOptionsIsEmptyBeforeAnythingIsRolled() {
        XCTAssertTrue(keepOptions(initialState(playerIds: ["P0", "P1"])).isEmpty)
    }

    func testKeepOptionsDescribesEachTakeableFaceOnce() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.coin, .three, .three, .three, .two, .two, .one, .one]

        let options = keepOptions(s)
        XCTAssertEqual(options.map { $0.face }, [.one, .two, .three, .coin])

        let threes = try! XCTUnwrap(options.first { $0.face == .three })
        XCTAssertEqual(threes.count, 3)
        XCTAssertEqual(threes.gain, 9)
        XCTAssertEqual(threes.diceLeft, 5)
        XCTAssertFalse(threes.securesPearl)

        let coin = try! XCTUnwrap(options.first { $0.face == .coin })
        XCTAssertEqual(coin.gain, 5)
        XCTAssertTrue(coin.securesPearl)
    }

    func testKeepOptionsPricesOneTwoAgainstThreeThrees() {
        // Bram's worked example. Three 3s score nine now but spend
        // three dice; the lone 2 scores two and keeps them, so the
        // dice that stay in hand can still come back as 5s or coins.
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.rolled = [.two, .three, .three, .three, .one, .one, .one, .one]

        let options = keepOptions(s)
        let two = try! XCTUnwrap(options.first { $0.face == .two })
        let three = try! XCTUnwrap(options.first { $0.face == .three })

        XCTAssertLessThan(two.gain, three.gain)
        XCTAssertGreaterThan(two.diceLeft, three.diceLeft)
        XCTAssertGreaterThan(two.expectedRollGain, three.expectedRollGain)
        XCTAssertLessThan(two.bustChance, three.bustChance)
    }

    func testKeepOptionsSkipsFacesAlreadySetAside() {
        var s = initialState(playerIds: ["P0", "P1"])
        s.phase = .pick
        s.setAside = [.coin, .coin]
        s.pickedFaces = [.coin]
        s.diceInHand = 6
        s.rolled = [.four, .four, .four, .four, .four, .four]

        XCTAssertFalse(keepOptions(s).contains { $0.face == .coin })
    }
}
