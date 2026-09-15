import Foundation

public struct Difficulty: Sendable, Equatable {
    /// 0 = greedy, 1 = cautious. Signed, and deliberately unclamped:
    /// below 0 the bust ceiling keeps rising until it passes 1.0 at
    /// about -0.417, past which the AI never stops for risk. The app's
    /// Easy tier lives there. Mirrors `Difficulty` in src/ai.ts.
    public var discipline: Double
    public init(discipline: Double) {
        self.discipline = discipline
    }
}

public func decide(state: State, ai: Difficulty) -> Action {
    if state.phase == .pick {
        return .pick(face: pickFace(state))
    }
    if state.phase == .chooseBank {
        return .bank(target: chooseBankTarget(state))
    }
    if state.setAside.isEmpty {
        return .roll
    }
    return continueOrStop(state, ai: ai)
}

// AI policy when both steal and center are on the table:
//   1. If a center pick would empty the supply, take it — ending the
//      game on your turn is almost always the best move.
//   2. Otherwise prefer stealing, which mirrors the engine's old forced
//      behavior and keeps simulation outcomes close to the pre-change
//      baseline.
func chooseBankTarget(_ state: State) -> BankOption {
    let options = bankOptions(state)
    if state.centerTiles.count == 1,
       let gameEnding = options.first(where: { if case .center = $0 { return true } else { return false } }) {
        return gameEnding
    }
    if let steal = options.first(where: { if case .steal = $0 { return true } else { return false } }) {
        return steal
    }
    return options.first ?? .center(tile: state.centerTiles.last ?? 0)
}

func pickFace(_ state: State) -> Face {
    let candidates = Face.allCases.filter { face in
        !state.pickedFaces.contains(face) && state.rolled.contains(face)
    }
    let hasCoin = state.setAside.contains(.coin)
    if !hasCoin, candidates.contains(.coin) {
        return .coin
    }
    func valueOf(_ f: Face) -> Int {
        state.rolled.filter { $0 == f }.count * f.value
    }
    return candidates.reduce(candidates.first!) { best, f in
        valueOf(f) > valueOf(best) ? f : best
    }
}

func continueOrStop(_ state: State, ai: Difficulty) -> Action {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    let hasCoin = state.setAside.contains(.coin)
    guard hasCoin else { return .roll }

    guard let target = bestBankableTile(state, sum: sum) else { return .roll }

    let pickedCount = state.pickedFaces.count
    let bustProb = pow(Double(pickedCount) / 6.0, Double(state.diceInHand))

    // Bust tolerance shrinks sharply as discipline rises.
    // Greedy (0.0) tolerates up to 0.75, cautious (1.0) bails at 0.15.
    let bustCeiling = 0.75 - ai.discipline * 0.6
    if bustProb >= bustCeiling { return .stop }

    // Cap target tier by what's still reachable so we don't wait for tiles
    // that no longer exist.
    let ceiling: Int = state.centerTiles.isEmpty
        ? 4
        : tileCoins(state.centerTiles.last!)
    // Discipline narrows ambition: 0 holds out for 4-coin tiles, 1 banks any.
    let desiredTier = max(1, min(ceiling, Int((4.0 - ai.discipline * 3.5).rounded())))
    if tileCoins(target) >= desiredTier { return .stop }

    return .roll
}

func bestBankableTile(_ state: State, sum: Int) -> Int? {
    for i in state.players.indices where i != state.current {
        if let top = state.players[i].tiles.last, top == sum {
            return sum
        }
    }
    let available = state.centerTiles.filter { $0 <= sum }
    return available.max()
}
