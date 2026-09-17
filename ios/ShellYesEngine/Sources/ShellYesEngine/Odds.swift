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
/// Each die independently lands on a dead face with the total
/// probability of those faces, so the roll is dead with that total
/// raised to `diceInHand`. Exact, not sampled.
///
/// It takes the faces rather than a count because a bent die is not
/// bent evenly: `luck` moves mass from the 1 onto the coin, so which
/// faces are spent decides how dangerous the next roll is. Two dead
/// faces are not two dead faces when one of them is the coin. At
/// `luck` 0 every face is worth `1/6` again and this collapses to the
/// old `(pickedCount / 6) ^ diceInHand`.
public func bustChance(pickedFaces: [Face], diceInHand: Int, luck: Double = 0) -> Double {
    let dead = Set(pickedFaces)
    // The two certainties are returned exactly rather than summed to.
    // Six sixths do not add to 1 in binary, and a bust that is certain
    // has to read as 1, not as 0.9999999999999996.
    if dead.isEmpty { return 0 }
    if dead.count == Face.allCases.count { return 1 }
    var deadChance = 0.0
    for face in Face.allCases where dead.contains(face) {
        deadChance += faceChance(face, luck: luck)
    }
    return pow(deadChance, Double(diceInHand))
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
public func expectedRollGain(pickedFaces: [Face], diceInHand: Int, luck: Double = 0) -> Double {
    guard diceInHand > 0 else { return 0 }
    let dead = Set(pickedFaces)
    var counts = [Int](repeating: 0, count: 6)
    let chances = Face.allCases.map { faceChance($0, luck: luck) }
    var total = 0.0

    // Walk the compositions of `diceInHand` over six faces. At most
    // C(13,5) = 1287 of them for a full hand, so exhaustive is cheap.
    func walk(_ faceIndex: Int, _ remaining: Int) {
        if faceIndex == 5 {
            counts[5] = remaining
            total += multinomial(counts, dice: diceInHand, chances: chances)
                * bestGain(counts, dead: dead)
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
public func keepOptions(_ state: State, luck: Double = 0) -> [KeepOption] {
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
                bustChance: bustChance(
                    pickedFaces: nextPicked,
                    diceInHand: diceLeft,
                    luck: luck
                ),
                expectedRollGain: expectedRollGain(
                    pickedFaces: nextPicked,
                    diceInHand: diceLeft,
                    luck: luck
                ),
                securesPearl: face == .coin
            )
        )
    }
    return options
}

/// Probability mass of one exact count vector:
/// `d! / (c0!...c5!) * p0^c0 * ... * p5^c5`.
///
/// `chances` is one probability per face, which is `1/6` six times for
/// a fair die and something lopsided for a bent one.
private func multinomial(_ counts: [Int], dice: Int, chances: [Double]) -> Double {
    var coefficient = factorial(dice)
    for c in counts { coefficient /= factorial(c) }
    var mass = coefficient
    for i in 0..<counts.count { mass *= pow(chances[i], Double(counts[i])) }
    return mass
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
