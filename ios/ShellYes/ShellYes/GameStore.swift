import Foundation
import Observation
import ShellYesEngine

enum Difficulty: String, Codable, CaseIterable {
    case easy, normal, hard

    var modifier: Double {
        switch self {
        case .easy: return -0.15
        case .normal: return 0
        case .hard: return 0.15
        }
    }
}

@MainActor
@Observable
final class GameStore {
    static let humanSeat = 0
    static let jonesSeat = 1
    static let bot03Seat = 2

    private let baseDiscipline: [Int: Double] = [
        jonesSeat: 0.30,
        bot03Seat: 0.85,
    ]

    enum AIEvent: Equatable {
        // `isFinal` flags claims that emptied the supply — the very
        // last shell of the tide. The banner uses it to swap copy
        // ("X claimed the last shell.") and the game view uses it to
        // gate the tally-screen presentation behind a banner tap.
        case took(actor: String, shell: Int, isFinal: Bool)
        case stole(actor: String, victim: String, shell: Int, isFinal: Bool)
        case bust(actor: String, burned: Int?)
    }

    private(set) var state: State
    private(set) var aiEvent: AIEvent? = nil
    @ObservationIgnored private var aiEventContinuation: CheckedContinuation<Void, Never>?
    private var rng: Mulberry32
    private let settings: SettingsStore

    /// Context for `game_abandoned`, so a rage quit is distinguishable
    /// from a phone call. Score and shells alone could not tell the
    /// two apart: quitting seconds after a bust and quitting two
    /// minutes after a bank looked identical.
    ///
    /// The clock starts when the game does — `noteGameStarted()`, called
    /// from the same place `game_started` fires — not when the store is
    /// built, which for the first game of a session would otherwise
    /// bill however long the player sat on the splash.
    @ObservationIgnored private var gameStartedAt = Date()
    @ObservationIgnored private var turnsTaken = 0
    @ObservationIgnored private var lastTurnOutcome = "none"

    /// Pool the two AI seats draw from on each new game. Uppercase so
    /// the existing `.capitalized` display calls (Scoreboard, banners)
    /// render them as title-case. Mellow first names, mixed gender, no
    /// gimmicks — fits the "soft maths, golden light" tone.
    private static let aiNamePool = [
        "KAI", "MARINA", "HAZEL", "REEF", "SASHA", "COCO",
        "BAY", "SAGE", "JONAS", "SANDY", "WREN", "MARLOW",
    ]

    private static func freshPlayerIds() -> [String] {
        let shuffled = aiNamePool.shuffled()
        return ["YOU", shuffled[0], shuffled[1]]
    }

    init(seed: UInt32, settings: SettingsStore) {
        self.rng = Mulberry32(seed: seed)
        self.settings = settings
        self.state = initialState(playerIds: Self.freshPlayerIds())
    }

    convenience init(settings: SettingsStore) {
        self.init(seed: UInt32.random(in: 1...UInt32.max), settings: settings)
    }

    var scores: [Int] { score(state) }
    var setAsideSum: Int { state.setAside.reduce(0) { $0 + $1.value } }
    var isHumanTurn: Bool { state.current == Self.humanSeat }
    var isOver: Bool { state.phase == .over }

    var canRoll: Bool {
        state.phase == .roll && state.diceInHand > 0 && isHumanTurn
    }

    var canBank: Bool {
        state.phase == .roll && !state.setAside.isEmpty && isHumanTurn
    }

    /// Non-empty only when the engine has parked in `.chooseBank`. The
    /// player must pick one of these to advance the turn — there's no
    /// auto-resolve from this state.
    var bankChoices: [BankOption] {
        state.phase == .chooseBank ? bankOptions(state) : []
    }

    var bankActionLabel: String {
        guard canBank else { return "Keep" }
        // Peek at what STOP would offer. Single-option → label it concretely.
        // Multi-option → "Choose…", because the engine will ask before
        // committing.
        let preview = bankOptions(state)
        if preview.count > 1 { return "Choose…" }
        if case .steal(let i, _) = preview.first {
            let name = state.players[i].id.capitalized
            return "Take \(name)'s shell"
        }
        return "Keep"
    }

    /// True only when the imminent bank is unambiguously a steal — i.e.
    /// stealing is the only legal option. Used to drive the steal-tinted
    /// button treatment. When the player has both steal and center on
    /// offer, the button stays neutral until they pick.
    var isStealOpportunity: Bool {
        guard canBank else { return false }
        let preview = bankOptions(state)
        return preview.count == 1 && {
            if case .steal = preview[0] { return true }
            return false
        }()
    }

    var phaseHint: String {
        if !isHumanTurn && !isOver {
            return "\(state.players[state.current].id.capitalized) reads the tide…"
        }
        if isOver { return "The tide rolls back." }
        switch state.phase {
        case .roll:
            return state.setAside.isEmpty ? "Your turn. Deep breath." : "Roll on, or keep."
        case .pick:
            return "Pick what you'll keep."
        case .chooseBank:
            return "Steal, or claim the sand?"
        case .over:
            return "The tide rolls back."
        }
    }

    var burnedCount: Int {
        let totalInUse = state.centerTiles.count + state.players.reduce(0) { $0 + $1.tiles.count }
        return max(0, 16 - totalInUse)
    }

    static func safeCoins(_ safe: Int) -> Int {
        tileCoins(safe)
    }

    func canPick(_ face: Face) -> Bool {
        state.phase == .pick &&
            isHumanTurn &&
            !state.pickedFaces.contains(face) &&
            state.rolled.contains(face)
    }

    var currentAIDifficulty: ShellYesEngine.Difficulty? {
        guard !isHumanTurn else { return nil }
        let base = baseDiscipline[state.current] ?? 0.5
        let adjusted = max(0, min(1, base + settings.difficulty.modifier))
        return ShellYesEngine.Difficulty(discipline: adjusted)
    }

    func apply(_ action: Action) {
        let old = state
        state = step(state: state, action: action, rng: &rng)
        noteTurnOutcome(from: old)
    }

    /// Keeps just enough history for `game_abandoned` to say how the
    /// game was going when it was thrown away. `apply` is the single
    /// funnel for every state change, human and AI alike, so this sees
    /// all of them.
    ///
    /// Only turn-ending outcomes count. A pick or a roll is mid-turn
    /// and says nothing about how the game is going.
    private func noteTurnOutcome(from old: State) {
        let turnEnded = state.current != old.current || state.phase == .over
        guard turnEnded else { return }
        turnsTaken += 1

        let seat = old.current
        let gained = state.players[seat].tiles.count > old.players[seat].tiles.count
        let humanLostAShell = state.players[Self.humanSeat].tiles.count
            < old.players[Self.humanSeat].tiles.count

        if seat == Self.humanSeat {
            // A human bank and a human steal both grow the stack; only
            // a bust shrinks it. Either way the player did it to
            // themselves, which is the distinction that matters when
            // reading a quit.
            lastTurnOutcome = gained ? "bank" : "bust"
        } else {
            lastTurnOutcome = humanLostAShell ? "stolen_from" : "ai_turn"
        }
    }

    private static let aiPaceNanoseconds: UInt64 = 300_000_000
    /// Minimum time the QuietAICard stays on-screen for a single AI
    /// seat's whole turn. Without this floor, the engine resolves a
    /// turn in ~50ms and the card flashes 1-2 frames before the
    /// banner. 2.0s is long enough to read "making waves" + watch a
    /// wave cycle, short enough that two AI seats don't drag.
    private static let quietTurnDwell: Duration = .milliseconds(2000)

    func runAIIfNeeded(reduceMotion: Bool) async {
        let factor = settings.gameSpeed.factor
        let pace = UInt64(Double(Self.aiPaceNanoseconds) * factor)
        // Quiet mode holds each AI seat's *whole turn* at a fixed
        // dwell BEFORE running the engine, so Tine-shaped players see
        // the QuietAICard breathe with the right name pinned for the
        // full 2s before the outcome banner punches in. Dwelling
        // AFTER `apply()` would yield to MainActor with `state.current`
        // already advanced, and the UI would flash the next seat (or
        // the human's DiceStage) under the dwell. Reduce-motion still
        // skips events entirely — without a banner to gate, the dwell
        // would just be dead air.
        let quiet = settings.quietAITurns && !reduceMotion
        var dwelledForSeat: Int? = nil
        var sfxStarted = false
        defer { GameSFX.shared.stopAIPlayingPattern() }
        while !isOver, let ai = currentAIDifficulty {
            if !sfxStarted {
                sfxStarted = true
                GameSFX.shared.startAIPlayingPattern()
            }
            if quiet, dwelledForSeat != state.current {
                dwelledForSeat = state.current
                try? await Task.sleep(for: Self.quietTurnDwell)
            }
            let oldState = state
            let oldCurrent = oldState.current
            let action = decide(state: state, ai: ai)
            apply(action)
            let turnEnded = state.current != oldCurrent || isOver
            let event: AIEvent? = (!reduceMotion && turnEnded)
                ? turnEndEvent(from: oldState, oldCurrent: oldCurrent)
                : nil
            // Last-shell claim: present the banner synchronously with the
            // apply so the view never observes (isOver = true, aiEvent = nil).
            // That race would let the tally fullScreenCover flash up
            // between apply and the banner. Skip the pacing sleep too —
            // there's no next AI turn to pace into.
            if isOver {
                GameSFX.shared.stopAIPlayingPattern()
                sfxStarted = false
                if let event {
                    if case .took = event { GameSFX.shared.playAIClaim() }
                    if case .stole(_, let victim, _, _) = event,
                       victim.lowercased() == "you" {
                        GameSFX.shared.playPlayerShellLoss()
                    }
                    await presentAIEvent(event)
                }
                return
            }
            if !quiet && !reduceMotion {
                try? await Task.sleep(nanoseconds: pace)
            }
            if let event {
                // Ticks represent rolling/choosing — pause while the
                // outcome banner is up, resume when the next AI seat
                // takes the wheel on the following iteration.
                GameSFX.shared.stopAIPlayingPattern()
                sfxStarted = false
                if case .took = event { GameSFX.shared.playAIClaim() }
                if case .stole(_, let victim, _, _) = event,
                   victim.lowercased() == "you" {
                    GameSFX.shared.playPlayerShellLoss()
                }
                await presentAIEvent(event)
            }
        }
    }

    private func turnEndEvent(from oldState: State, oldCurrent: Int) -> AIEvent? {
        let actorName = oldState.players[oldCurrent].id.capitalized
        let oldTiles = oldState.players[oldCurrent].tiles
        let newTiles = state.players[oldCurrent].tiles
        let isFinal = state.phase == .over
        if newTiles.count > oldTiles.count, let newShell = newTiles.last {
            for i in oldState.players.indices where i != oldCurrent {
                if state.players[i].tiles.count < oldState.players[i].tiles.count {
                    let victim = oldState.players[i].id.capitalized
                    return .stole(actor: actorName, victim: victim, shell: newShell, isFinal: isFinal)
                }
            }
            return .took(actor: actorName, shell: newShell, isFinal: isFinal)
        }
        // Bust — find the burned shell by diffing total supply (center +
        // every player's stack). Tile numbers are unique 21-36, so the
        // single missing entry is the one the bank ate.
        let oldSet = Set(oldState.centerTiles + oldState.players.flatMap { $0.tiles })
        let newSet = Set(state.centerTiles + state.players.flatMap { $0.tiles })
        let burned = oldSet.subtracting(newSet).first
        return .bust(actor: actorName, burned: burned)
    }

    private func presentAIEvent(_ event: AIEvent) async {
        aiEvent = event
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            aiEventContinuation = cont
        }
    }

    /// Display a turn event banner without blocking on a continuation —
    /// for the human's own actions, where there's no AI loop to pause.
    /// The view dismisses it via `dismissAIEvent()` on tap.
    func presentTurnEvent(_ event: AIEvent) {
        aiEvent = event
    }

    func dismissAIEvent() {
        guard aiEvent != nil else { return }
        aiEvent = nil
        let cont = aiEventContinuation
        aiEventContinuation = nil
        cont?.resume()
    }

    /// A full beach, taken from the engine rather than hardcoded so a
    /// change to the shell range can't silently turn every new game
    /// into a reported abandonment.
    private static let fullBeach = initialState(playerIds: []).centerTiles.count

    /// Reports the game being thrown away, if there was one. Called
    /// from `newGame` because that is the one funnel every discard
    /// goes through: Home, the settings restart, and New Game from the
    /// tally all land here. A game nobody has touched is not an
    /// abandonment, and a finished one is a `game_ended`, so both are
    /// filtered out.
    private func reportAbandonedGame() {
        guard state.phase != .over else { return }
        let claimed = state.players.reduce(0) { $0 + $1.tiles.count }
        let touched = claimed > 0 || state.centerTiles.count != Self.fullBeach
        guard touched else { return }

        Telemetry.shared.track("game_abandoned", props: [
            "my_score": score(state)[Self.humanSeat],
            "my_shells": state.players[Self.humanSeat].tiles.count,
            "shells_left": state.centerTiles.count,
            "difficulty": settings.difficulty.rawValue,
            "seconds_in": Int(Date().timeIntervalSince(gameStartedAt)),
            "turns": turnsTaken,
            "last_event": lastTurnOutcome,
        ])
    }

    /// Starts the abandonment clock. Called wherever `game_started`
    /// fires, so the two events describe the same stretch of time.
    func noteGameStarted() {
        gameStartedAt = Date()
        turnsTaken = 0
        lastTurnOutcome = "none"
    }

    func newGame() {
        reportAbandonedGame()
        noteGameStarted()
        rng = Mulberry32(seed: UInt32.random(in: 1...UInt32.max))
        state = initialState(playerIds: Self.freshPlayerIds())
        aiEvent = nil
        let cont = aiEventContinuation
        aiEventContinuation = nil
        cont?.resume()
    }

    #if DEBUG
    func setStateForTesting(_ s: State) {
        self.state = s
    }

    /// Gives every non-human seat two random tiles drawn from the centre
    /// pool. Lets you set up a board with stealable shells before tapping
    /// the steal-trigger.
    func debugSeedAIVaults() {
        let aiSeats = state.players.indices.filter { $0 != Self.humanSeat }
        for seat in aiSeats {
            for _ in 0..<2 {
                guard !state.centerTiles.isEmpty else { return }
                let idx = Int.random(in: 0..<state.centerTiles.count)
                let tile = state.centerTiles.remove(at: idx)
                state.players[seat].tiles.append(tile)
            }
        }
    }

    /// Fast-forwards the game to its end state: every seat gets a small
    /// fistful of shells (so the tally screen has something to count
    /// and a clear winner), the supply is emptied, and the phase flips
    /// to `.over`. Lets you verify the counting ceremony and winner
    /// presentation without playing a full hand.
    func debugForceGameOver() {
        // Hand the human a slightly larger pile so there's a believable
        // win to celebrate. AI seats get fewer / lower-value tiles.
        let plan: [(seat: Int, count: Int)] = state.players.indices.map { seat in
            (seat, seat == Self.humanSeat ? 4 : 2)
        }
        for (seat, count) in plan {
            for _ in 0..<count {
                guard !state.centerTiles.isEmpty else { break }
                let idx = Int.random(in: 0..<state.centerTiles.count)
                let tile = state.centerTiles.remove(at: idx)
                state.players[seat].tiles.append(tile)
            }
        }
        state.centerTiles.removeAll()
        state.rolled = []
        state.setAside = []
        state.pickedFaces = []
        state.diceInHand = 0
        state.phase = .over
    }

    /// Forces the engine into the `chooseBank` phase with both a steal
    /// and a center take legal, so the human sees the two-card chooser
    /// without having to dice their way into the scenario. The setup
    /// mirrors Bram's reported bug: rival holds 26, sand holds 25 only,
    /// dice locked sum to 26 — so picking the center actually ends the
    /// game.
    func debugTriggerBankChoice() {
        state.current = Self.humanSeat
        var rival: Int? = nil
        for i in state.players.indices where i != Self.humanSeat {
            rival = i; break
        }
        guard let r = rival else { return }
        state.players[r].tiles = [26]
        state.centerTiles = [25]
        // Coin = 5, so 5*5 + 1 = 26 across six locked dice.
        state.setAside = [.coin, .coin, .coin, .coin, .coin, .one]
        state.pickedFaces = [.coin, .one]
        state.rolled = []
        state.diceInHand = 0
        state.phase = .chooseBank
    }

    /// Moves the top tile from the first non-human seat with shells into
    /// the human's vault. If no non-human seat has any, seeds one with a
    /// mid-value tile first. Used to verify the steal animation without
    /// playing through a full hand.
    func debugTriggerSteal() {
        var victim: Int? = nil
        for i in state.players.indices where i != Self.humanSeat {
            if !state.players[i].tiles.isEmpty { victim = i; break }
        }
        if victim == nil {
            for i in state.players.indices where i != Self.humanSeat {
                state.players[i].tiles.append(25)
                victim = i
                break
            }
        }
        guard let v = victim, !state.players[v].tiles.isEmpty else { return }
        let tile = state.players[v].tiles.removeLast()
        state.players[Self.humanSeat].tiles.append(tile)
    }
    #endif
}
