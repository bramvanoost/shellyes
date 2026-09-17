public func initialState(playerIds: [String]) -> State {
    State(
        players: playerIds.map { Player(id: $0, tiles: []) },
        current: 0,
        centerTiles: Array(21...36),
        diceInHand: TOTAL_DICE,
        rolled: [],
        setAside: [],
        pickedFaces: [],
        phase: .roll
    )
}

public func score(_ state: State) -> [Int] {
    state.players.map { $0.tiles.reduce(0) { $0 + tileCoins($1) } }
}

public func step<R: ShellYesRandom>(state: State, action: Action, rng: inout R) -> State {
    if state.phase == .over { return state }
    switch action {
    case .roll:
        return applyRoll(state, rng: &rng)
    case .pick(let face):
        return applyPick(state, face: face)
    case .stop:
        return applyStop(state)
    case .bank(let target):
        return applyBank(state, target: target)
    }
}

// Enumerates every legal bank commitment from the current set-aside sum:
// each rival whose top tile matches exactly, plus the highest supply tile
// <= sum if one exists. Returns [] when banking would bust. Renderers
// should call this in the `chooseBank` phase to present the player's
// options.
public func bankOptions(_ state: State) -> [BankOption] {
    let sum = state.setAside.reduce(0) { $0 + $1.value }
    guard state.setAside.contains(.coin) else { return [] }
    var options: [BankOption] = []
    for i in state.players.indices where i != state.current {
        if let top = state.players[i].tiles.last, top == sum {
            options.append(.steal(playerIndex: i, tile: sum))
        }
    }
    let eligible = state.centerTiles.filter { $0 <= sum }
    if let top = eligible.max() {
        options.append(.center(tile: top))
    }
    return options
}

func applyPick(_ state: State, face: Face) -> State {
    guard state.phase == .pick else { return state }
    guard !state.pickedFaces.contains(face) else { return state }
    let taken = state.rolled.filter { $0 == face }
    guard !taken.isEmpty else { return state }
    var next = state
    next.setAside.append(contentsOf: taken)
    next.pickedFaces.append(face)
    next.diceInHand -= taken.count
    next.rolled = []
    next.phase = .roll
    if next.diceInHand == 0 {
        return tryBank(next)
    }
    return next
}

func tryBank(_ state: State) -> State {
    guard state.setAside.contains(.coin) else { return bust(state) }
    let options = bankOptions(state)
    if options.isEmpty { return bust(state) }
    // Single option = no choice to make. Multiple options park in
    // `chooseBank` and wait for the player's .bank action. Heckmeck rule:
    // stealing is always optional, never forced.
    if options.count == 1 { return commitBank(state, target: options[0]) }
    var next = state
    next.phase = .chooseBank
    return next
}

func commitBank(_ state: State, target: BankOption) -> State {
    switch target {
    case .steal(let playerIndex, let tile):
        var next = state
        next.players[playerIndex].tiles.removeLast()
        next.players[state.current].tiles.append(tile)
        return endTurn(next)
    case .center(let tile):
        var next = state
        next.centerTiles.removeAll { $0 == tile }
        next.players[state.current].tiles.append(tile)
        return endTurn(next)
    }
}

func applyBank(_ state: State, target: BankOption) -> State {
    guard state.phase == .chooseBank else { return state }
    guard bankOptions(state).contains(target) else { return state }
    return commitBank(state, target: target)
}

/// Most a die may be bent. At `1/6` the weakest face would never come
/// up at all, which is a different game rather than a kinder one.
public let maxLuck = 1.0 / 6.0

/// Chance one die shows `face`, given how far it is bent. Fair dice
/// (`luck` 0) give every face `1/6`. Mirror of `faceChance` in
/// `src/engine.ts`.
public func faceChance(_ face: Face, luck: Double = 0) -> Double {
    let moved = max(0, min(luck, maxLuck))
    if face == .coin { return 1.0 / 6.0 + moved }
    if face.rawValue == 1 { return 1.0 / 6.0 - moved }
    return 1.0 / 6.0
}

func rollDie<R: ShellYesRandom>(rng: inout R) -> Face {
    let n = Int(rng.next() * 6) + 1
    let clamped = max(1, min(6, n))
    return Face(rawValue: clamped)!
}

func applyRoll<R: ShellYesRandom>(_ state: State, rng: inout R) -> State {
    guard state.phase == .roll, state.diceInHand > 0 else { return state }
    let rolled = (0..<state.diceInHand).map { _ in rollDie(rng: &rng) }
    let hasNewFace = rolled.contains { !state.pickedFaces.contains($0) }
    if !hasNewFace {
        return bust(state)
    }
    var next = state
    next.rolled = rolled
    next.phase = .pick
    return next
}

func endTurn(_ state: State) -> State {
    if state.centerTiles.isEmpty {
        var s = state
        s.phase = .over
        s.rolled = []
        s.setAside = []
        s.pickedFaces = []
        s.diceInHand = 0
        return s
    }
    var s = state
    s.current = (state.current + 1) % state.players.count
    s.diceInHand = TOTAL_DICE
    s.rolled = []
    s.setAside = []
    s.pickedFaces = []
    s.phase = .roll
    return s
}

func bust(_ state: State) -> State {
    var players = state.players
    var centerTiles = state.centerTiles
    let me = players[state.current]
    if let top = me.tiles.last {
        players[state.current].tiles.removeLast()
        centerTiles.append(top)
        centerTiles.sort()
    }
    // Burn the highest remaining center tile so the supply depletes (CLAUDE.md).
    if !centerTiles.isEmpty {
        centerTiles.removeLast()
    }
    var s = state
    s.players = players
    s.centerTiles = centerTiles
    return endTurn(s)
}

func applyStop(_ state: State) -> State {
    guard state.phase == .roll else { return state }
    guard !state.setAside.isEmpty else { return state }
    return tryBank(state)
}
