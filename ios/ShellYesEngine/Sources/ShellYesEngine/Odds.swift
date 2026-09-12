import Foundation

// Exact odds for explanation mode. Pure: no I/O, no rng, no Date.
//
// Mirror of `src/odds.ts`, down to the order the multinomial walk adds
// its terms, so the two engines agree bit for bit under the parity
// harness. Change one, change both, then run `node parity/diff.mjs`.
//
// Scope is one roll of lookahead, deliberately. The full "play to the
// end optimally" value needs a search over every future keep, and the
// number it produces is less use to a player than "what does this roll
// cost me" — which is the question a keep decision actually asks.

/// One face the player could take from the current roll, with what it
/// costs and buys. `gain` is immediate, the rest is what the board
/// looks like afterwards.
public struct KeepOption: Codable, Sendable, Equatable {
    public let face: Face
    /// How many dice show this face.
    public let count: Int
    /// Value added to the set-aside sum by taking them. The coin
    /// scores 5, same as `Face.value`.
    public let gain: Int
    /// Dice still in hand after taking them.
    public let diceLeft: Int
    /// Chance the next roll shows nothing takeable, i.e. a bust.
    public let bustChance: Double
    /// Expected value the next roll adds, counting a bust as zero.
    public let expectedRollGain: Double
    /// True when this face is the coin, so taking it makes the pile
    /// bankable. Without one, stopping busts however high the sum.
    public let securesPearl: Bool

    public init(
        face: Face,
        count: Int,
        gain: Int,
        diceLeft: Int,
        bustChance: Double,
        expectedRollGain: Double,
        securesPearl: Bool
    ) {
        self.face = face
        self.count = count
        self.gain = gain
        self.diceLeft = diceLeft
        self.bustChance = bustChance
        self.expectedRollGain = expectedRollGain
        self.securesPearl = securesPearl
    }
}

/// Chance that a roll of `diceInHand` dice shows only faces already
/// picked, which is exactly the engine's bust condition.
///
/// Each die independently lands on one of the `pickedCount` dead faces
/// with probability `pickedCount / 6`, so the roll is dead with
/// probability `(pickedCount / 6) ^ diceInHand`. Exact, not sampled.
public func bustChance(pickedCount: Int, diceInHand: Int) -> Double {
    pow(Double(pickedCount) / 6.0, Double(diceInHand))
}

/// Expected value a single roll of `diceInHand` dice adds, given the
/// faces already spent.
///
/// Enumerates every distribution of the dice across the six faces with
/// its exact multinomial probability, then credits the best face
/// available in that roll. "Best" is the greedy rule a player reads as
/// obvious — highest `count * value` — not a search, so the number is
/// a floor on what careful play scores, not a ceiling.
///
/// A roll with no available face contributes zero, which is what folds
/// the bust case into the same number.
public func expectedRollGain(pickedFaces: [Face], diceInHand: Int) -> Double {
    guard diceInHand > 0 else { return 0 }
    let dead = Set(pickedFaces)
    var counts = [Int](repeating: 0, count: 6)
    var total = 0.0

    // Walk the compositions of `diceInHand` over six faces. At most
    // C(13,5) = 1287 of them for a full hand, so exhaustive is cheap.
    func walk(_ faceIndex: Int, _ remaining: Int) {
        if faceIndex == 5 {
            counts[5] = remaining
            total += multinomial(counts, dice: diceInHand) * bestGain(counts, dead: dead)
            return
        }
        for n in 0...remaining {
            counts[faceIndex] = n
            walk(faceIndex + 1, remaining - n)
        }
        counts[faceIndex] = 0
    }
    walk(0, diceInHand)
    return total
}

/// Every face the player could take from the roll on the table, with
/// the odds that follow it. Empty in any phase but `pick`, and empty
/// when the roll is dead — which is the bust the engine is about to
/// apply.
public func keepOptions(_ state: State) -> [KeepOption] {
    guard state.phase == .pick else { return [] }
    let dead = Set(state.pickedFaces)
    var options: [KeepOption] = []
    for face in Face.allCases {
        if dead.contains(face) { continue }
        let count = state.rolled.filter { $0 == face }.count
        if count == 0 { continue }
        let diceLeft = state.diceInHand - count
        let nextPicked = state.pickedFaces + [face]
        options.append(
            KeepOption(
                face: face,
                count: count,
                gain: count * face.value,
                diceLeft: diceLeft,
                bustChance: bustChance(pickedCount: nextPicked.count, diceInHand: diceLeft),
                expectedRollGain: expectedRollGain(pickedFaces: nextPicked, diceInHand: diceLeft),
                securesPearl: face == .coin
            )
        )
    }
    return options
}

/// Probability mass of one exact count vector under six fair dice:
/// `d! / (c0!...c5!) * (1/6)^d`.
private func multinomial(_ counts: [Int], dice: Int) -> Double {
    var coefficient = factorial(dice)
    for c in counts { coefficient /= factorial(c) }
    return coefficient * pow(1.0 / 6.0, Double(dice))
}

/// Best immediate gain from one rolled count vector, or zero when
/// every face in it has already been picked.
private func bestGain(_ counts: [Int], dead: Set<Face>) -> Double {
    var best = 0
    for i in 0..<6 {
        guard let face = Face(rawValue: i + 1) else { continue }
        if dead.contains(face) || counts[i] == 0 { continue }
        let gain = counts[i] * face.value
        if gain > best { best = gain }
    }
    return Double(best)
}

/// Eight dice is the whole game, so the table is nine entries long and
/// exact in a Double the entire way.
private let factorials: [Double] = [1, 1, 2, 6, 24, 120, 720, 5040, 40320]

private func factorial(_ n: Int) -> Double {
    factorials[n]
}
