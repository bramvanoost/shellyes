import Foundation
import Observation
import ShellYesEngine

enum Difficulty: String, Codable, CaseIterable {
    case easy, normal, hard

    /// Discipline for each AI seat, as `[seat 1, seat 2]`.
    ///
    /// This replaces a single `modifier` that shifted both seats by
    /// ±0.15 off one base. That model could not work, and shipped
    /// broken in 1.2: `ai.ts` / `AI.swift` derive ambition from
    /// `round(4 - discipline * 3.5)`, which quantises the knob into
    /// three bands (≤0.357 holds out for 3-coin shells, ≤0.786 banks
    /// 2-coin, above that banks anything). A ±0.15 nudge mostly lands
    /// inside one band and changes nothing, and where it does cross a
    /// boundary it crosses only one.
    ///
    /// Worse, strength is not monotone in discipline at a three-seat
    /// table. Holding out pays when there are two rivals to steal from,
    /// so the middle band outscores the top one. Easy's seat 2 sat at
    /// 0.70 and Normal's at 0.85 — which made Easy's opponent the
    /// *stronger* of the two. Measured over 20,000 games: Easy won
    /// 38.2% of the time against Normal's 39.7%. Easy was harder.
    ///
    /// These pairs are tuned against Bram's targets: Easy above 60,
    /// then roughly 50 / 40 percent human win rate. Verified
    /// monotone at low, mid and high player skill rather than at one
    /// assumed skill. 20,000 games per cell, mid-skill column:
    /// 65.2 / 51.7 / 41.0.
    ///
    /// Easy is negative on purpose. The knob is documented 0...1, but
    /// neither engine clamps it, and below zero it keeps meaning
    /// something: `bustCeiling = 0.75 - discipline * 0.6` climbs past
    /// 0.75 until it passes 1.0 at about -0.417, where the AI will
    /// never stop for risk again. The tier term saturates immediately
    /// (`min(ceiling, ...)` caps it), so the bust ceiling is the only
    /// thing moving down here. At 0.00, both seats already at the
    /// floor of the documented range, Easy only reached 58.6%, which
    /// played as a coin flip rather than as Easy.
    ///
    /// The lever is stepped, not smooth: `bustProb` is
    /// `(pickedFaces / 6) ^ diceInHand`, a discrete set, so the
    /// ceiling only bites when it crosses one of those values. Below
    /// zero there are three distinct settings, 0.00 / -0.20 / -0.417,
    /// and -0.20 is worth almost all of what -0.417 buys. Nudging
    /// to -0.25 does nothing at all.
    ///
    /// Re-tune with `sim/difficulty.ts`, not by nudging a number and
    /// hoping. A pair that reads as "weaker" often is not.
    var seatDiscipline: [Double] {
        switch self {
        case .easy:   return [0.00, 0.00]
        case .normal: return [0.20, 0.00]
        case .hard:   return [0.20, 0.50]
        }
    }

    /// How far the *player's* dice are bent, and nobody else's. The
    /// mass is shared over the three high faces and taken from the
    /// three low ones, so each of 4, 5 and the coin gains `luck / 3`;
    /// see `faceWeights` in `src/engine.ts` for the shape.
    ///
    /// Easy used to buy its whole win rate by making the bots greedy,
    /// at -0.20 a seat. That works — it measured 65.1% — but greedy
    /// bots fail 56% of their turns, and a table where the opponents
    /// bust on every other turn reads as broken rather than as easy.
    /// Bram played it and said so. Easy is now 0.00 a seat, where they
    /// fail 49%, and the difference comes back to the player as dice.
    ///
    /// Nothing above Easy gets any. Normal and Hard roll the same fair
    /// dice they always did, so a score posted on those boards means
    /// exactly what it used to.
    ///
    /// The odds the app quotes know about this: `bustChance`,
    /// `expectedRollGain` and `keepOptions` in `Odds.swift` all take
    /// the same number. A handicap the explanation screen could not
    /// see would make every figure it prints a lie.
    var luck: Double {
        switch self {
        case .easy:            return 0.05
        case .normal, .hard:   return 0
        }
    }
}

@MainActor
@Observable
final class GameStore {
    static let humanSeat = 0
    static let jonesSeat = 1
    static let bot03Seat = 2

    /// Which entry of `Difficulty.seatDiscipline` each AI seat reads.
    /// The human sits at 0, so the two AI seats are 1 and 2.
    private static let disciplineIndex: [Int: Int] = [
        jonesSeat: 0,
        bot03Seat: 1,
    ]

    enum AIEvent: Equatable {
        // `isFinal` flags claims that emptied the supply — the very
        // last shell of the tide. The banner uses it to swap copy
        // ("X claimed the last shell.") and the game view uses it to
        // gate the tally-screen presentation behind a banner tap.
        case took(actor: String, shell: Int, isFinal: Bool)
        case stole(actor: String, victim: String, shell: Int, isFinal: Bool)
        case bust(actor: String, burned: Int?)

        /// Whether auto-continue is allowed to dismiss this banner on
        /// its own. One carve-out: the shell that ends the game. The
        /// tally waits behind that banner, and being dropped into it
        /// without a tap reads as the game having moved on without you.
        ///
        /// Whose move it was used to matter too — your own claim, steal
        /// or bust waited for a tap on the reasoning that a thing you
        /// did is a thing you should get to look at. But a player with
        /// auto-continue on had already asked not to tap, and being made
        /// to tap for their own moment and not for anyone else's read as
        /// the setting half working. The banner still draws its draining
        /// wave and a tap still dismisses early, so the moment is
        /// offered rather than withheld.
        var autoContinues: Bool {
            switch self {
            case .took(_, _, let isFinal), .stole(_, _, _, let isFinal):
                return !isFinal
            case .bust:
                return true
            }
        }
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

    /// Whether this game has already been written to `AbandonGuard`.
    /// In memory rather than read back from defaults, so the common
    /// path — every action after the first — doesn't touch disk.
    @ObservationIgnored private var hasArmedAbandonGuard = false

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

    /// Optional so previews and unit tests can build a store without
    /// dragging a stats file in. A store without one still plays a
    /// correct game; it just can't file the loss when a game is thrown
    /// away, which is not a thing either of those does.
    private let stats: StatsStore?

    /// Injectable so tests can arm and disarm without writing to the
    /// player's real defaults.
    private let abandonGuard: AbandonGuard

    init(
        seed: UInt32,
        settings: SettingsStore,
        stats: StatsStore? = nil,
        abandonGuard: AbandonGuard = .shared
    ) {
        self.rng = Mulberry32(seed: seed)
        self.settings = settings
        self.stats = stats
        self.abandonGuard = abandonGuard
        self.state = initialState(playerIds: Self.freshPlayerIds())
    }

    convenience init(
        settings: SettingsStore,
        stats: StatsStore? = nil,
        abandonGuard: AbandonGuard = .shared
    ) {
        self.init(
            seed: UInt32.random(in: 1...UInt32.max),
            settings: settings,
            stats: stats,
            abandonGuard: abandonGuard
        )
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
        let seats = settings.difficulty.seatDiscipline
        // An unknown seat falls to the middle of the range rather than
        // crashing, the way `Leaderboard.score(forDifficulty:)` does:
        // a third AI added later should play a plausible game, not take
        // the app down before its entry exists.
        guard let index = Self.disciplineIndex[state.current],
              seats.indices.contains(index)
        else { return ShellYesEngine.Difficulty(discipline: 0.5) }
        return ShellYesEngine.Difficulty(discipline: seats[index])
    }

    /// Steps the engine, bending the dice when it is the human's turn
    /// on a difficulty that grants any. See `Difficulty.luck`.
    ///
    /// `LuckyRandom` wraps the game's one `Mulberry32` and the advanced
    /// base is handed back afterwards, so all three seats keep drawing
    /// from a single stream and a seed still replays the whole game.
    /// A second generator for the human would fork the sequence and
    /// make a saved seed meaningless.
    private func stepped(_ state: State, _ action: Action) -> State {
        let luck = settings.difficulty.luck
        guard luck > 0, state.current == Self.humanSeat else {
            return step(state: state, action: action, rng: &rng)
        }
        var lucky = LuckyRandom(base: rng, luck: luck)
        let next = step(state: state, action: action, rng: &lucky)
        rng = lucky.base
        return next
    }

    func apply(_ action: Action) {
        let old = state
        state = stepped(state, action)
        noteTurnOutcome(from: old)

        // The first action of a game is what makes it a game. Arm here
        // rather than at the deal, so opening New Game and backing out
        // without rolling costs nothing — and disarm the moment it ends
        // properly, so a finished game is never charged twice.
        if state.phase == .over {
            hasArmedAbandonGuard = false
            abandonGuard.disarm()
        } else if !hasArmedAbandonGuard {
            hasArmedAbandonGuard = true
            abandonGuard.arm(
                difficulty: settings.difficulty.rawValue,
                pace: settings.gameSpeed.rawValue
            )
        }
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
    /// Charges a game the player is walking out of, as the loss it is.
    ///
    /// Separate from `reportAbandonedGame` because the two ask
    /// different questions and the wrong one was nearly used for both.
    /// Telemetry asks "was this game *interesting* enough to report" —
    /// its `touched` bar wants a claimed shell or a disturbed beach.
    /// This asks "did the player act", which is a lower bar and the
    /// only correct one here: rolling once, seeing a bad roll and
    /// tapping Home claims nothing and disturbs nothing, and is exactly
    /// the quit the fix exists to charge for.
    ///
    /// Gated on `hasArmedAbandonGuard`, so it matches the launch-time
    /// path in `ShellYesApp` charge for charge. Walking out through
    /// Home has to cost the same as force-quitting or the cheaper
    /// version of the exploit stays free.
    ///
    /// Filed now rather than at the next launch because the game is
    /// being discarded here and the guard is about to be re-armed for
    /// its replacement.
    private func chargeAbandonedGame() {
        guard state.phase != .over, hasArmedAbandonGuard else { return }
        stats?.recordAbandonedGame(
            difficulty: settings.difficulty.rawValue,
            pace: settings.gameSpeed.rawValue
        )
        hasArmedAbandonGuard = false
        abandonGuard.disarm()
    }

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
        // Charge first, report second: the report reads `turnsTaken`
        // and the live state, and charging doesn't touch either, but
        // the order is the one that reads correctly — the game is lost,
        // then the loss is described.
        chargeAbandonedGame()
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
