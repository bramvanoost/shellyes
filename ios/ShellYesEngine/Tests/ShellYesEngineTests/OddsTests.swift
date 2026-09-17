import XCTest
@testable import ShellYesEngine

/// Mirrors `tests/odds.test.ts` case for case. The numbers are the
/// contract between the two engines; the parity harness proves they
/// agree, these prove they are right.
final class OddsTests: XCTestCase {

    // MARK: - bustChance

    func testBustChanceIsZeroWithNothingPicked() {
        XCTAssertEqual(bustChance(pickedFaces: [], diceInHand: 8), 0)
    }

    func testBustChanceIsOneInSixForOneDieOverOneDeadFace() {
        XCTAssertEqual(bustChance(pickedFaces: [.one], diceInHand: 1), 1.0 / 6.0, accuracy: 1e-12)
    }

    func testBustChanceCompoundsAcrossDice() {
        XCTAssertEqual(bustChance(pickedFaces: [.one, .two, .three], diceInHand: 2), 0.25, accuracy: 1e-12)
    }

    func testBustChanceIsCertainOnceEveryFaceIsSpent() {
        XCTAssertEqual(bustChance(pickedFaces: Face.allCases, diceInHand: 4), 1)
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

/// The Easy handicap: a die bent toward the coin, and the odds that
/// have to know about it. Mirror of the `luck` cases in
/// `tests/odds.test.ts` — change one, change both.
final class LuckyDiceTests: XCTestCase {

    func test_faceChance_spreadsTheBonusOverTheThreeHighFaces() {
        for face in [Face.four, .five, .coin] {
            XCTAssertEqual(faceChance(face, luck: 0.06), 1.0 / 6.0 + 0.02, accuracy: 1e-12)
        }
        for face in [Face.one, .two, .three] {
            XCTAssertEqual(faceChance(face, luck: 0.06), 1.0 / 6.0 - 0.02, accuracy: 1e-12)
        }
    }

    func test_faceChance_neverBendsPastTheCap() {
        // Asking for more than the cap is clamped, not honoured: at
        // 0.5 the low faces already never come up.
        for face in [Face.one, .two, .three] {
            XCTAssertEqual(faceChance(face, luck: 5), 0, accuracy: 1e-12)
        }
        for face in [Face.four, .five, .coin] {
            XCTAssertEqual(faceChance(face, luck: 5), 1.0 / 3.0, accuracy: 1e-12)
        }
    }

    func test_faceChance_sumsToOneHoweverFarItIsBent() {
        for luck in [0, 0.05, 0.2, 0.5] {
            let total = Face.allCases.reduce(0.0) { $0 + faceChance($1, luck: luck) }
            XCTAssertEqual(total, 1, accuracy: 1e-12)
        }
    }

    /// The point of taking faces rather than a count: spending the
    /// coin is more dangerous on a bent die than spending the 1, and
    /// on a fair one they are the same.
    func test_bustChance_dependsOnWhichFaceWasSpent() {
        let spentCoin = bustChance(pickedFaces: [.coin], diceInHand: 2, luck: 0.05)
        let spentOne = bustChance(pickedFaces: [.one], diceInHand: 2, luck: 0.05)
        XCTAssertGreaterThan(spentCoin, spentOne)

        XCTAssertEqual(
            bustChance(pickedFaces: [.coin], diceInHand: 2),
            bustChance(pickedFaces: [.one], diceInHand: 2),
            accuracy: 1e-12
        )
    }

    func test_bustChance_atZeroLuckIsTheFairFormula() {
        XCTAssertEqual(
            bustChance(pickedFaces: [.one, .two, .three], diceInHand: 3),
            pow(0.5, 3),
            accuracy: 1e-12
        )
    }

    /// A kinder die is worth more per roll, which is the whole point
    /// of granting one.
    func test_expectedRollGain_risesWithLuck() {
        let fair = expectedRollGain(pickedFaces: [], diceInHand: 4)
        let bent = expectedRollGain(pickedFaces: [], diceInHand: 4, luck: 0.05)
        XCTAssertGreaterThan(bent, fair)
    }

    /// Bent or not, a roll with every face spent is worth nothing.
    func test_expectedRollGain_isZeroWhenEveryFaceIsSpent() {
        XCTAssertEqual(
            expectedRollGain(pickedFaces: Face.allCases, diceInHand: 5, luck: 0.05),
            0
        )
    }

    /// The remap has to roll the distribution it advertises and spend
    /// exactly one draw per die, or a seed would stop replaying.
    func test_luckyRandom_rollsTheDistributionItAdvertises() {
        var lucky = LuckyRandom(base: Mulberry32(seed: 99), luck: 0.06)
        var counts = [Int](repeating: 0, count: 7)
        let rolls = 240_000
        for _ in 0..<rolls {
            counts[Int(lucky.next() * 6) + 1] += 1
        }
        for face in Face.allCases {
            XCTAssertEqual(
                Double(counts[face.rawValue]) / Double(rolls),
                faceChance(face, luck: 0.06),
                accuracy: 0.005,
                "face \(face.rawValue) came up at the wrong rate"
            )
        }
    }

    func test_luckyRandom_atZeroIsTheFairStream() {
        var fair = Mulberry32(seed: 7)
        var lucky = LuckyRandom(base: Mulberry32(seed: 7), luck: 0)
        for _ in 0..<500 {
            XCTAssertEqual(lucky.next(), fair.next())
        }
    }
}
