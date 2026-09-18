import SwiftUI
import ShellYesEngine

struct GameView: View {
    let store: GameStore
    let settings: SettingsStore
    let stats: StatsStore
    @Environment(\.accessibilityReduceMotion) private var iosReduceMotion
    @Environment(\.goHome) private var goHome
    @SwiftUI.State private var bustFlash: Bool = false
    @SwiftUI.State private var bustReason: BustReason = .rolled
    @SwiftUI.State private var burnedTile: Int? = nil
    /// The human's own top shell that returned to the supply on this
    /// bust. Distinct from `burnedTile` (which is the highest tile that
    /// then disappeared from the supply): the player needs to see both
    /// to understand a bust costs them a shell, not just the sand.
    @SwiftUI.State private var bustReturnedTile: Int? = nil
    @SwiftUI.State private var stolenFromIdx: Int? = nil
    /// Seat that just gained a stolen shell. While non-nil, the
    /// scoreboard is shown a copy of `players` with that seat's newest
    /// tile trimmed off, so the receiver's sparkle / pop-in fires AFTER
    /// the victim's smoke poof rather than at the same instant.
    @SwiftUI.State private var stealArrivalSeat: Int? = nil
    @SwiftUI.State private var bustProgress: CGFloat = 1.0
    @SwiftUI.State private var bustGeneration: Int = 0
    /// Fake roll values used to fill the dice slot for ~1s after a roll
    /// that produced a bust. Without this the bust banner punches in
    /// instantly — the engine clears `state.rolled` when the turn ends,
    /// so there's nothing for DiceStage to animate. Overriding the
    /// `rolled` prop with these values lets the player at least feel
    /// the dice land before "Oh, shell no" arrives.
    @SwiftUI.State private var bustAnimatedRoll: [Face]? = nil
    /// Snapshot of `centerTiles` from the moment before the bust-roll
    /// apply, held so the ShellsGrid doesn't visibly drop / receive
    /// shells during the fake-roll window. The state update plays out
    /// underneath the bust flash and is settled by the time the user	
    /// dismisses it.
    @SwiftUI.State private var bustFrozenCenterTiles: [Int]? = nil
    /// During the fake roll window, freeze the seat index that the
    /// scoreboard highlights + the bottom bar reads from. Without this,
    /// the next player's column glows and "Wren is playing…" appears
    /// before the bust banner does — the same spoiler as the tile
    /// leaving the grid.
    @SwiftUI.State private var bustFrozenCurrent: Int? = nil
    /// Likewise freeze the phase-hint copy so DiceStage doesn't read
    /// out "Wren reads the tide…" while the human's fake dice are
    /// still settling.
    @SwiftUI.State private var bustFrozenPhaseHint: String? = nil
    /// And freeze the locked dice / running sum. The engine clears
    /// `setAside` the instant the turn ends, so without this the hero
    /// number snaps to 0 while the fake dice are still tumbling — the
    /// player sees their total wiped before they're told they busted.
    @SwiftUI.State private var bustFrozenSetAside: [Face]? = nil
    /// Frozen alongside `bustFrozenSetAside`, and not optional for
    /// tidiness: the tally row draws one slot per set-aside die plus
    /// one per die in hand, and the engine guarantees those two sum
    /// to `TOTAL_DICE`. Freezing one without the other broke that
    /// sum on every bust — `endTurn` had already reset dice in hand
    /// to 8 while the row still drew the pre-bust set-aside dice, so
    /// the player saw fifteen slots for an eight-die game.
    @SwiftUI.State private var bustFrozenDiceInHand: Int? = nil
    /// And freeze every vault, because a bust returns the player's top
    /// shell to the sand the instant `apply` returns. Without this the
    /// shell vanishes off their stack a full `rollBustVisualDelay`
    /// before the banner says why — the bust is given away by the
    /// thing it costs, while the dice are still in the air. Same
    /// spoiler the four freezes above exist to prevent, on the one
    /// piece of state that reads as a punishment.
    @SwiftUI.State private var bustFrozenPlayers: [Player]? = nil
    private let bustHoldSeconds: Double = 8.0

    /// How much of an auto-continue wait is left, 1 down to 0. Drives
    /// the wave on the AI banner the same way `bustProgress` drives
    /// the one on the bust flash.
    @SwiftUI.State private var aiEventProgress: Double = 1

    /// Bumped every time a banner appears or is tapped away, so the
    /// timer belonging to a banner the player already dismissed can't
    /// come back and dismiss the next one.
    @SwiftUI.State private var aiEventGeneration = 0

    /// How long an AI seat's outcome stays up before it leaves on its
    /// own: 2.2s at the fast pace, stretched by the Pace setting a
    /// player who chose Slow already asked for. Long enough to read a
    /// name and a shell number, short enough that two bot seats in a
    /// row don't feel like a cutscene.
    private var autoContinueSeconds: Double { 2.2 * settings.gameSpeed.factor }

    /// Whether this banner leaves on its own. The setting decides
    /// whether the feature is on at all; which events qualify is the
    /// event's own business, so it can be tested without a screen.
    private func autoContinues(_ event: GameStore.AIEvent) -> Bool {
        settings.autoContinue && event.autoContinues
    }

    /// Runs one banner's countdown: reset the wave to full, drain it,
    /// and dismiss when it runs out. Mirrors `triggerBustFlash` —
    /// including the separate tick for the reset, so the start value
    /// isn't swept into the long animation.
    private func startAutoContinue(for event: GameStore.AIEvent) {
        aiEventGeneration += 1
        let generation = aiEventGeneration
        let seconds = autoContinueSeconds
        aiEventProgress = 1
        DispatchQueue.main.async {
            guard generation == aiEventGeneration else { return }
            withAnimation(.linear(duration: seconds)) {
                aiEventProgress = 0
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard generation == aiEventGeneration, store.aiEvent == event else { return }
            store.dismissAIEvent()
        }
    }
    /// How long the fake post-bust roll stays on screen before the
    /// flash takes over. Matches the dice animation duration roughly.
    private let rollBustVisualDelayNs: UInt64 = 1_000_000_000

    enum BustReason {
        case greedy   // tried to bank without a coin
        case rolled   // roll produced no new pickable face
        case stranded // picked the last die without a pearl: no dice left, no bank possible
    }
    @SwiftUI.State private var revealChrome: Bool = false
    @SwiftUI.State private var revealScoreboard: Bool = false
    @SwiftUI.State private var revealShells: Bool = false
    @SwiftUI.State private var revealStage: Bool = false
    @SwiftUI.State private var revealAction: Bool = false

    // Per-game counters, used as props on the `game_ended` telemetry
    // event. Reset on each new game.
    @SwiftUI.State private var gameStartTime: Date?
    @SwiftUI.State private var bustsThisGame: Int = 0
    #if DEBUG
    /// Debug-menu shortcut to the stats screen. A sheet rather than a
    /// nav push because Menu buttons can't drive the NavigationStack
    /// path from here.
    @SwiftUI.State private var debugShowStats: Bool = false
    #endif
    @SwiftUI.State private var stealsThisGame: Int = 0
    @SwiftUI.State private var biggestKeepThisGame: Int = 0
    /// Every shell the human claimed this game, for the Bookends
    /// achievement (21 and 36 in one game).
    @SwiftUI.State private var claimedShellsThisGame: Set<Int> = []
    /// True when the human's own claim emptied the sand and ended
    /// the game. Independent of whether they went on to win it.
    @SwiftUI.State private var endedByClaimingLastShell: Bool = false
    @SwiftUI.State private var gameEndedReported: Bool = false

    /// Seat index used by every UI element that highlights "whose turn
    /// is it". During the fake-roll bust window this stays pinned to
    /// the human seat so the scoreboard / action bar don't spoil the
    /// turn change ahead of the bust banner. While an AI/turn-end
    /// banner is up, the engine has already advanced `state.current`
    /// to the next seat — pin the scoreboard to the banner's actor so
    /// the active-seat highlight doesn't jump ahead of the modal.
    private var displayCurrent: Int {
        if let frozen = bustFrozenCurrent { return frozen }
        // While a stolen shell is staged, keep the receiver visually
        // active so the column's deactivation spring fires together
        // with the tile-arrival sparkle (one beat, not two).
        if let arrival = stealArrivalSeat { return arrival }
        if let actorSeat = aiEventActorSeat { return actorSeat }
        return store.state.current
    }

    /// Maps the active banner's actor name back to a seat index by
    /// matching against `players[].id.capitalized` (the same
    /// transform the banner's title line uses). Returns nil when
    /// there's no banner or the actor doesn't match a known seat —
    /// either way the scoreboard falls back to `state.current`.
    private var aiEventActorSeat: Int? {
        guard let event = store.aiEvent else { return nil }
        let actor: String
        switch event {
        case .took(let a, _, _): actor = a
        case .stole(let a, _, _, _): actor = a
        case .bust(let a, _): actor = a
        }
        return store.state.players.firstIndex { $0.id.capitalized == actor }
    }
    private var displayIsHumanTurn: Bool {
        displayCurrent == GameStore.humanSeat
    }
    private var displayPhaseHint: String {
        bustFrozenPhaseHint ?? store.phaseHint
    }

    /// Quiet-mode swap: hide the live DiceStage on AI turns when the
    /// setting is on. Bust-flash freezes pin the human's seat, so the
    /// frozen-current branch keeps the DiceStage visible during the
    /// fake-roll bust window (otherwise the QuietAICard would punch in
    /// the moment turn advances, ahead of the bust banner). Likewise,
    /// while an event banner is up we hold off so the card's entrance
    /// animation fires WHEN the banner dismisses, not invisibly
    /// underneath it.
    private var showQuietAICard: Bool {
        guard settings.quietAITurns else { return false }
        guard bustFrozenCurrent == nil else { return false }
        guard store.aiEvent == nil else { return false }
        return !store.isHumanTurn && !store.isOver
    }

    /// Players array with the steal-receiver's newest tile temporarily
    /// hidden (during the ~450ms staging window). The Scoreboard /
    /// VaultStack think the receiver hasn't gained yet, so their
    /// sparkle + insertion transition fires when the staging clears,
    /// after the victim's smoke poof has had time to land.
    private var displayedPlayers: [Player] {
        // The bust freeze wins: it is holding back a loss the player has
        // not been told about yet, and no steal can be staged inside
        // that window anyway.
        if let frozen = bustFrozenPlayers { return frozen }
        guard let seat = stealArrivalSeat else { return store.state.players }
        var players = store.state.players
        guard players.indices.contains(seat), !players[seat].tiles.isEmpty else {
            return store.state.players
        }
        players[seat].tiles.removeLast()
        return players
    }

    /// Locked dice as the player should see them right now: the live
    /// engine value, except during the post-bust fake-roll window where
    /// the pre-bust set-aside stays pinned.
    private var displayedSetAside: [Face] {
        bustFrozenSetAside ?? store.state.setAside
    }

    private var displayedDiceInHand: Int {
        bustFrozenDiceInHand ?? store.state.diceInHand
    }

    private func act(_ action: Action) {
        let humanSeat = GameStore.humanSeat
        let wasHumanTurn = store.isHumanTurn
        let beforeVault = store.state.players[humanSeat].tiles.count
        let hadCoinBefore = store.state.setAside.contains(.coin)
        // Snapshot the pool the bust logic will burn from: current center +
        // the player's top tile (which returns to center on bust).
        let beforeCenter = store.state.centerTiles
        let beforeTopVaultTile = store.state.players[humanSeat].tiles.last
        // Snapshot every player's stack so we can detect whose tile the
        // human claimed (steal vs centre take) after apply.
        let beforeTileCounts = store.state.players.map { $0.tiles.count }
        let beforePlayerIds = store.state.players.map { $0.id }
        // Snapshot for the post-roll-bust fake dice display.
        let beforePickedFaces = store.state.pickedFaces
        let beforeDiceInHand = store.state.diceInHand
        // Snapshot setAside count so we can compute how many dice of
        // the picked face were moved (for stats).
        let beforeSetAsideCount = store.state.setAside.count
        let beforeSetAside = store.state.setAside
        // Pre-apply snapshots used to freeze the player-turn cues so
        // they don't update ahead of the bust banner.
        let beforeCurrent = store.state.current
        let beforePhaseHint = store.phaseHint
        let beforePlayers = store.state.players

        store.apply(action)

        // Forced bust: after a pick the player has 0 dice left in hand AND
        // no pearl in set-aside. No valid move that isn't a bust, so the
        // engine takes the .stop for them. Reason is tagged .stranded so
        // the bust banner explains they were boxed in, not greedy.
        var forcedStop = false
        if wasHumanTurn && store.isHumanTurn && !store.isOver
            && store.state.diceInHand == 0
            && !store.state.setAside.isEmpty
            && !store.state.setAside.contains(.coin) {
            store.apply(.stop)
            forcedStop = true
        }

        // Detect end-of-turn outcomes for the human player — bust gets a flash;
        // bank/steal celebration is handled per-column (sparkles + steal pulse).
        // The turn has ended whenever the engine advanced `current` OR flipped
        // to `.over` (game-ending claim keeps current pinned to the human).
        var didBust = false
        let humanTurnEnded = wasHumanTurn
            && (store.state.current != beforeCurrent || store.isOver)
        if humanTurnEnded {
            let afterVault = store.state.players[humanSeat].tiles.count
            if afterVault <= beforeVault {
                if forcedStop {
                    bustReason = .stranded
                } else if case .stop = action, !hadCoinBefore {
                    bustReason = .greedy
                } else {
                    bustReason = .rolled
                }
                // The burned tile is the highest in (centerTiles + returned top).
                var pool = beforeCenter
                let didReturnTopTile = beforeTopVaultTile != nil && afterVault < beforeVault
                if didReturnTopTile, let returned = beforeTopVaultTile {
                    pool.append(returned)
                }
                burnedTile = pool.max()
                bustReturnedTile = didReturnTopTile ? beforeTopVaultTile : nil
                didBust = true
                // For "you rolled and the dice gave you nothing" busts,
                // fake a one-second dice roll so the player sees the
                // doomed faces land before the flash. Other bust reasons
                // (greedy stop, stranded post-pick) skip straight to flash.
                if case .roll = action, !forcedStop, !beforePickedFaces.isEmpty {
                    bustAnimatedRoll = (0..<beforeDiceInHand).map { _ in
                        beforePickedFaces.randomElement()!
                    }
                    bustFrozenCenterTiles = beforeCenter
                    bustFrozenCurrent = beforeCurrent
                    bustFrozenPhaseHint = beforePhaseHint
                    bustFrozenSetAside = beforeSetAside
                    bustFrozenDiceInHand = beforeDiceInHand
                    bustFrozenPlayers = beforePlayers
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: rollBustVisualDelayNs)
                        triggerBustFlash()
                        bustAnimatedRoll = nil
                        bustFrozenCenterTiles = nil
                        bustFrozenCurrent = nil
                        bustFrozenPhaseHint = nil
                        bustFrozenSetAside = nil
                        bustFrozenDiceInHand = nil
                        bustFrozenPlayers = nil
                    }
                } else {
                    triggerBustFlash()
                }
            } else {
                // Vault grew — successful bank or steal.
                GameSFX.shared.playBank()
                // Present a turn-note banner for the human's claim. Detect
                // steal by checking if another seat lost a tile this apply.
                if let claimed = store.state.players[humanSeat].tiles.last {
                    var victim: String? = nil
                    for i in beforeTileCounts.indices where i != humanSeat {
                        if store.state.players[i].tiles.count < beforeTileCounts[i] {
                            victim = beforePlayerIds[i].capitalized
                            break
                        }
                    }
                    // If this claim emptied the supply, the engine
                    // has already flipped `phase = .over`. Flag the
                    // banner as final so the copy switches to "you
                    // claimed the last shell." and the tally screen
                    // waits for the player to dismiss.
                    let isFinal = store.isOver
                    if let victim {
                        // Stage the receiver hold synchronously so the
                        // human column doesn't flicker active → inactive
                        // in the frame between engine state change and
                        // the onChange-driven detectSteal.
                        stealArrivalSeat = humanSeat
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            if stealArrivalSeat == humanSeat { stealArrivalSeat = nil }
                        }
                        store.presentTurnEvent(.stole(actor: "You", victim: victim, shell: claimed, isFinal: isFinal))
                    } else {
                        store.presentTurnEvent(.took(actor: "You", shell: claimed, isFinal: isFinal))
                    }
                    // Banked sum is the tile value claimed (engine maps
                    // setAside sum to the tile number).
                    stats.recordBank(sum: claimed, stoleATile: victim != nil)
                    if claimed > biggestKeepThisGame { biggestKeepThisGame = claimed }
                    if victim != nil { stealsThisGame += 1 }
                    claimedShellsThisGame.insert(claimed)
                    if isFinal { endedByClaimingLastShell = true }
                    Telemetry.shared.track("game_bank", props: [
                        "tile_value": claimed,
                        "stole_from_rival": victim != nil,
                    ])
                }
            }
            if didBust {
                stats.recordBust()
                bustsThisGame += 1
                Telemetry.shared.track("game_bust", props: [
                    "reason": String(describing: bustReason),
                    "lost_tile": beforeTopVaultTile ?? 0,
                    "burned_tile": burnedTile ?? 0,
                ])
            }
        }

        // Track every face the human picks so the "hot face" stat reflects
        // their actual play.
        if wasHumanTurn, case .pick(let face) = action {
            let added = max(0, store.state.setAside.count - beforeSetAsideCount)
            if added > 0 {
                stats.recordPicks(Array(repeating: face, count: added))
            }
        }

        let reduce = settings.reducedMotion || iosReduceMotion
        Task { @MainActor in
            // After a human bust, the AI loop must wait until the Oh-shell-no
            // banner is dismissed (tap or timer). Otherwise AI turns play out
            // underneath and their event banners stack on top of the bust.
            if didBust {
                // Hold the AI loop while the fake roll plays AND while
                // the flash is up. Combined into one poll so a brief
                // race between "fake roll clears" and "flash appears"
                // doesn't let the loop slip through.
                while bustAnimatedRoll != nil || bustFlash {
                    try? await Task.sleep(nanoseconds: 120_000_000)
                }
            }
            // Same gate for the human's claim banner — wait until the
            // "Nice, you claimed shell N!" note is tapped away before any
            // AI seat picks up the dice.
            while store.aiEvent != nil {
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
            await store.runAIIfNeeded(reduceMotion: reduce)
        }
    }

    /// Reset every transient UI flag, then ask the store for a fresh
    /// game. Without this, a pending bust flash or turn-note banner
    /// from the previous game leaks into the new one (the symptom: tap
    /// "New Game" from the tie screen and land on a live board with a
    /// stale modal still open).
    private func startNewGame() {
        resetTransientGameUI()
        store.dismissAIEvent()
        store.newGame()
        trackGameStarted(from: "tally")
    }

    /// One shape for every start, so `game_started` against
    /// `game_ended` is a clean funnel. `from` says which door the game
    /// came through; the settings the game is played on are recorded
    /// here rather than only at the end, so a player who abandons
    /// still tells us what they chose.
    private func trackGameStarted(from source: String) {
        store.noteGameStarted()
        Telemetry.shared.track("game_started", props: [
            "from": source,
            "difficulty": settings.difficulty.rawValue,
            "pace": settings.gameSpeed.rawValue,
            "quiet_ai": settings.quietAITurns,
            "auto_continue": settings.autoContinue,
            "games_played": stats.gamesPlayed,
        ])
    }

    /// Clears every per-game UI flag. Shared by "New Game" and the
    /// tally screen's Home exit — leaving these set would carry a
    /// stale flash or banner into whatever comes next.
    private func resetTransientGameUI() {
        bustFlash = false
        bustAnimatedRoll = nil
        bustFrozenCenterTiles = nil
        bustFrozenCurrent = nil
        bustFrozenPhaseHint = nil
        bustFrozenSetAside = nil
        bustFrozenDiceInHand = nil
        burnedTile = nil
        bustReturnedTile = nil
        stolenFromIdx = nil
        gameStartTime = Date()
        bustsThisGame = 0
        stealsThisGame = 0
        biggestKeepThisGame = 0
        claimedShellsThisGame = []
        endedByClaimingLastShell = false
        gameEndedReported = false
    }

    private func detectSteal(oldCounts: [Int], newCounts: [Int]) {
        guard oldCounts.count == newCounts.count else { return }
        for i in 0..<newCounts.count {
            if newCounts[i] < oldCounts[i] {
                let actor = (0..<newCounts.count).first { j in
                    j != i && newCounts[j] > oldCounts[j]
                }
                if let actor {
                    stolenFromIdx = i
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_400_000_000)
                        if stolenFromIdx == i { stolenFromIdx = nil }
                    }
                    // Hold the receiver's new tile back for ~450ms so the
                    // victim's poof + collapse plays solo first, then the
                    // sparkle + scale-in lands on the thief's stack.
                    stealArrivalSeat = actor
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 450_000_000)
                        if stealArrivalSeat == actor { stealArrivalSeat = nil }
                    }
                    // Canonical steal event — one per transfer, regardless
                    // of which seat thieved. The existing game_bank event
                    // still carries `stole_from_rival` for backward compat
                    // on dashboards, but game_steal is the single source of
                    // truth and covers the AI-steals-from-human case the
                    // bank event couldn't see.
                    let players = store.state.players
                    let tileValue = players.indices.contains(actor)
                        ? (players[actor].tiles.last ?? 0)
                        : 0
                    Telemetry.shared.track("game_steal", props: [
                        "actor": players.indices.contains(actor) ? players[actor].id : "unknown",
                        "victim": players.indices.contains(i) ? players[i].id : "unknown",
                        "tile_value": tileValue,
                        "actor_was_human": actor == GameStore.humanSeat,
                        "victim_was_human": i == GameStore.humanSeat,
                    ])
                }
                return
            }
        }
    }

    #if DEBUG
    /// Applies the launch-argument seed requested by `ScreenshotTests`.
    /// Runs after the intro animation so the captures show a settled
    /// board rather than one still sliding into place.
    private func applyScreenshotSeed() async {
        guard let seed = ScreenshotMode.seed else { return }
        try? await Task.sleep(nanoseconds: 400_000_000)
        store.debugSeedAIVaults()
        switch seed {
        case .vaults:
            break
        case .steal:
            try? await Task.sleep(nanoseconds: 500_000_000)
            stealArrivalSeat = GameStore.humanSeat
            store.debugTriggerSteal()
        case .tally:
            try? await Task.sleep(nanoseconds: 500_000_000)
            store.debugForceGameOver()
        case .aiBanner:
            try? await Task.sleep(nanoseconds: 500_000_000)
            store.presentTurnEvent(.took(actor: "Sandy", shell: 28, isFinal: false))
        }
    }
    #endif

    private func runIntroAnimation() async {
        let reduce = settings.reducedMotion || iosReduceMotion
        if reduce {
            revealChrome = true
            revealScoreboard = true
            revealShells = true
            revealStage = true
            revealAction = true
            return
        }
        withAnimation(.easeOut(duration: 0.35)) { revealChrome = true }
        try? await Task.sleep(nanoseconds: 150_000_000)
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) { revealScoreboard = true }
        try? await Task.sleep(nanoseconds: 350_000_000)
        withAnimation(.easeOut(duration: 0.45)) { revealShells = true }
        try? await Task.sleep(nanoseconds: 650_000_000)
        withAnimation(.easeOut(duration: 0.35)) { revealStage = true }
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { revealAction = true }
    }

    private var bustSubline: String {
        switch bustReason {
        case .greedy: return "you had no pearl in hand."
        case .rolled: return "the dice gave you nothing."
        case .stranded: return "no dice left, no pearl in hand."
        }
    }

    @ViewBuilder
    private func burnedTileChip(value: Int) -> some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    // Dashed stroke marks the shell as drifting away —
                    // same visual language as the bust banner's ghost
                    // chip in AIEventBanner.shellChip(drifting: true).
                    ShellCardShape()
                        .strokeBorder(
                            Color.stampText.opacity(0.85),
                            style: StrokeStyle(lineWidth: 2, dash: [3, 3])
                        )
                )
                .shadow(color: Color.coralDark.opacity(0.45), radius: 0, x: 0, y: 5)
                .shadow(color: Color.coralDark.opacity(0.25), radius: 14, x: 0, y: 0)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(28, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: coins, diameter: 7, spacing: 3)
            }
        }
        .frame(width: 64, height: 80)
        .opacity(0.85)
    }

    /// What the bust just cost the player, made unambiguous: their top
    /// shell goes back to the supply, AND the largest shell in the supply
    /// burns. If those happen to be the same tile (returned shell was the
    /// new pool max), it's collapsed to a single chip so we don't claim
    /// two losses where there's one.
    @ViewBuilder
    private func bustLossSection() -> some View {
        let returned = bustReturnedTile
        let burned = burnedTile
        let returnedIsBurned = returned != nil && returned == burned
        // Two distinct losses: the player's own shell came back AND a
        // different sand shell burned. Only in that case do we want
        // the side-by-side chips with yours/sand labels and the
        // trailing "And the largest..." line. Without this guard, a
        // solo sand burn renders as one chip labeled "sand" plus the
        // trailing line — both describing the same single shell.
        let twoLosses = returned != nil && burned != nil && !returnedIsBurned

        let headline: String = {
            if twoLosses {
                return "You lose your top shell, and the largest shell on the sand drifts away."
            }
            if returned != nil {
                return "You lose your top shell."
            }
            return "A shell drifts away."
        }()

        if returned != nil || burned != nil {
            VStack(spacing: 10) {
                Text(headline)
                    .font(.avenir(13, weight: .medium, italic: true))
                    .tracking(2.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.stampText.opacity(0.95))
                    .padding(.horizontal, 24)

                HStack(alignment: .top, spacing: 24) {
                    if let returned {
                        VStack(spacing: 6) {
                            burnedTileChip(value: returned)
                            if twoLosses {
                                Text("yours")
                                    .font(.avenir(10, weight: .demiBold, italic: true))
                                    .tracking(2)
                                    .textCase(.lowercase)
                                    .foregroundStyle(Color.stampText.opacity(0.85))
                            }
                        }
                    } else if let burned {
                        burnedTileChip(value: burned)
                    }
                    if twoLosses, let burned {
                        VStack(spacing: 6) {
                            burnedTileChip(value: burned)
                            Text("sand")
                                .font(.avenir(10, weight: .demiBold, italic: true))
                                .tracking(2)
                                .textCase(.lowercase)
                                .foregroundStyle(Color.stampText.opacity(0.85))
                        }
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    /// Large pearl rendered on the coral bust wash — the prize that almost
    /// was. Cream halo carries contrast, hard offset shadow gives stamp depth.
    @ViewBuilder
    private func bustPearl(size: CGFloat) -> some View {
        Pearl(diameter: size)
            .shadow(color: Color.stampText.opacity(0.55), radius: 24, x: 0, y: 0)
            .shadow(color: Color.coralDark, radius: 0, x: 0, y: 6)
    }

    private func triggerBustFlash() {
        GameSFX.shared.playBust()
        guard !settings.reducedMotion, !iosReduceMotion else { return }
        bustGeneration += 1
        let thisGeneration = bustGeneration
        withAnimation(.easeOut(duration: 0.25)) {
            bustFlash = true
        }
        // Reset countdown to full, then animate it down. The withAnimation
        // wrappers must be on separate ticks so the start-value mutation
        // isn't bundled into the long animation.
        bustProgress = 1.0
        DispatchQueue.main.async {
            withAnimation(.linear(duration: bustHoldSeconds)) {
                bustProgress = 0
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(bustHoldSeconds * 1_000_000_000))
            guard thisGeneration == bustGeneration else { return }
            dismissBustFlash()
        }
    }

    private func dismissBustFlash() {
        guard bustFlash else { return }
        withAnimation(.easeIn(duration: 0.35)) {
            bustFlash = false
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Background()

            VStack(spacing: 0) {
                ChromeBar(
                    settings: settings,
                    onDebugSeedAI: {
                        #if DEBUG
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            store.debugSeedAIVaults()
                        }
                        #endif
                    },
                    onDebugSteal: {
                        #if DEBUG
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            // Set the staging in the same MainActor turn
                            // as the mutation so SwiftUI batches them
                            // into one render — no active-state flash.
                            stealArrivalSeat = GameStore.humanSeat
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 450_000_000)
                                if stealArrivalSeat == GameStore.humanSeat { stealArrivalSeat = nil }
                            }
                            store.debugTriggerSteal()
                        }
                        #endif
                    },
                    onDebugBankChoice: {
                        #if DEBUG
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            store.debugTriggerBankChoice()
                        }
                        #endif
                    },
                    onDebugEndGame: {
                        #if DEBUG
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 250_000_000)
                            store.debugForceGameOver()
                        }
                        #endif
                    },
                    onDebugSeedBests: {
                        #if DEBUG
                        stats.debugSeedBestRuns()
                        #endif
                    },
                    onDebugShowStats: {
                        #if DEBUG
                        debugShowStats = true
                        #endif
                    },
                    onDebugForceNudge: {
                        #if DEBUG
                        // Armed here, read by the tally: arm it,
                        // then end the game from the next menu item.
                        DifficultyNudge.debugForce.toggle()
                        #endif
                    }
                )
                .opacity(revealChrome ? 1 : 0)
                .offset(y: revealChrome ? 0 : -16)

                Scoreboard(
                    players: displayedPlayers,
                    scores: store.scores,
                    current: displayCurrent,
                    revealed: revealScoreboard,
                    stolenFrom: stolenFromIdx
                )

                Spacer().frame(height: 6)

                ShellsGrid(
                    availableShells: bustFrozenCenterTiles ?? store.state.centerTiles,
                    remainingCount: (bustFrozenCenterTiles ?? store.state.centerTiles).count,
                    revealed: revealShells
                )

                Spacer().frame(height: 10)

                // Quiet AI mode swaps the live dice stage for a calm
                // placeholder during AI turns. Players who don't want
                // to parse AI rolling get a quieter screen; the engine
                // still runs underneath and the outcome banner fires
                // (see `AIEventBanner`). The human's own turn always
                // shows the full DiceStage so they can play.
                Group {
                    if showQuietAICard {
                        QuietAICard(name: store.state.players[displayCurrent].id.capitalized)
                    } else {
                        DiceStage(
                            phaseHint: displayPhaseHint,
                            setAsideSum: displayedSetAside.reduce(0) { $0 + $1.value },
                            rolled: bustAnimatedRoll ?? store.state.rolled,
                            locked: displayedSetAside,
                            diceInHand: displayedDiceInHand,
                            isHumanTurn: displayIsHumanTurn,
                            canPick: { store.canPick($0) },
                            onPick: { act(.pick(face: $0)) },
                            canBank: store.canBank && store.isHumanTurn,
                            bankPreview: store.bankActionLabel,
                            isSteal: store.isStealOpportunity,
                            onBank: { act(.stop) },
                            playerNames: store.state.players.map { $0.id.capitalized },
                            bankChoices: store.isHumanTurn ? store.bankChoices : [],
                            onChoose: { act(.bank(target: $0)) },
                            reduceMotion: settings.reducedMotion || iosReduceMotion,
                            speedFactor: settings.gameSpeed.factor,
                            forceRollSound: bustAnimatedRoll != nil
                        )
                    }
                }
                .opacity(revealStage ? 1 : 0)
                .offset(y: revealStage ? 0 : 12)

                Spacer().frame(height: 4)

                ActionBar(
                    canRoll: store.canRoll,
                    isHumanTurn: displayIsHumanTurn,
                    isOver: store.isOver,
                    hasSetAside: !displayedSetAside.isEmpty,
                    activePlayerName: store.state.players[displayCurrent].id.capitalized,
                    onRoll: { act(.roll) }
                )
                .opacity(revealAction ? 1 : 0)
                .offset(y: revealAction ? 0 : 30)

                Spacer().frame(height: 14)
            }
            .task {
                if gameStartTime == nil {
                    gameStartTime = Date()
                    trackGameStarted(from: "home")
                }
                await runIntroAnimation()
                #if DEBUG
                await applyScreenshotSeed()
                #endif
            }
            .onChange(of: store.state.players.map { $0.tiles.count }) { oldCounts, newCounts in
                detectSteal(oldCounts: oldCounts, newCounts: newCounts)
            }
            .onChange(of: store.isOver) { wasOver, isNowOver in
                guard !wasOver, isNowOver, !gameEndedReported else { return }
                gameEndedReported = true
                let scores = store.scores
                let humanScore = scores[GameStore.humanSeat]
                let topScore = scores.max() ?? 0
                let leaderCount = scores.filter { $0 == topScore }.count
                // A tie still counts as "won" for streaks and the
                // game_won event so historical data stays comparable.
                // `outcome` is what tells win and tie apart.
                let humanWon = humanScore == topScore
                let outcome = humanWon ? (leaderCount > 1 ? "tie" : "win") : "loss"
                stats.recordGameOver(
                    humanWon: humanWon,
                    humanScore: humanScore,
                    difficulty: settings.difficulty.rawValue,
                    pace: settings.gameSpeed.rawValue
                )
                let duration = gameStartTime.map { Int(Date().timeIntervalSince($0)) } ?? 0
                let endProps: [String: Any] = [
                    "won": humanWon,
                    "outcome": outcome,
                    "leader_count": leaderCount,
                    "my_score": humanScore,
                    "opponent_count": store.state.players.count - 1,
                    "busts": bustsThisGame,
                    "steals": stealsThisGame,
                    "biggest_keep": biggestKeepThisGame,
                    "duration_seconds": duration,
                    "difficulty": settings.difficulty.rawValue,
                    "pace": settings.gameSpeed.rawValue,
                    "quiet_ai": settings.quietAITurns,
                    "auto_continue": settings.autoContinue,
                ]
                Telemetry.shared.track("game_ended", props: endProps)
                Telemetry.shared.track(humanWon ? "game_won" : "game_lost", props: endProps)

                // Game Center hears the same finished game. `stats` has
                // already recorded it above, so the lifetime totals
                // include this run and a milestone can land on it.
                GameCenter.shared.recordGameOver(
                    summary: GameSummary(
                        won: humanWon,
                        score: humanScore,
                        difficulty: settings.difficulty.rawValue,
                        busts: bustsThisGame,
                        steals: stealsThisGame,
                        claimedShells: claimedShellsThisGame,
                        endedByClaimingLastShell: endedByClaimingLastShell
                    ),
                    lifetime: LifetimeTotals(
                        gamesPlayed: stats.gamesPlayed,
                        wins: stats.wins,
                        bestStreak: stats.bestStreak
                    ),
                    biggestKeep: stats.biggestKeep,
                    weekly: stats.weeklyBests()
                )
            }
        }
        .overlay {
            if bustFlash {
                ZStack {
                    // Full coral wash — the danger color, with a vignette
                    // toward the corners so the center stays loudest.
                    RadialGradient(
                        colors: [Color.coral, Color.coralDark],
                        center: .center,
                        startRadius: 80,
                        endRadius: 540
                    )
                    .ignoresSafeArea()

                    // Subtle paper-flecked grain so the wash doesn't read as flat.
                    LinearGradient(
                        colors: [Color.coralLight.opacity(0.18), .clear, Color.coralDark.opacity(0.3)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .blendMode(.softLight)

                    VStack(spacing: 20) {
                        if bustReason == .greedy || bustReason == .stranded {
                            bustPearl(size: 84)
                        }
                        // Stamped headline — the inverse of the "shell yes"
                        // wordmark moment. Italic for the narrative tone.
                        Text("Oh, shell no.")
                            .font(.avenir(52, weight: .demiBold, italic: true))
                            .tracking(1)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.stampText)
                            .shadow(color: Color.coralDark, radius: 0, x: 2, y: 3)
                            .shadow(color: Color.stampText.opacity(0.25), radius: 26, x: 0, y: 0)

                        // Hairline rule beneath the headline — a printer's mark.
                        Capsule()
                            .fill(Color.stampText.opacity(0.55))
                            .frame(width: 64, height: 1.5)

                        Text(bustSubline)
                            .font(.avenir(18, weight: .medium, italic: true))
                            .tracking(1.5)
                            .textCase(.lowercase)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.stampText)
                            .shadow(color: Color.coralDark.opacity(0.6), radius: 0, x: 1, y: 1)
                            .padding(.horizontal, 30)

                        // Show the shells the bust just cost. The player's
                        // returned top shell is the headline loss — without
                        // this they might think the bust only burns from the
                        // supply. When the returned shell IS the one that
                        // burned (it was the new pool max), don't double up
                        // the chip; one loss, label it clearly. When the
                        // sand burn is a different tile, show both with
                        // distinct labels so the player sees both losses.
                        bustLossSection()

                        // Countdown bar + "tap to continue" — anchored to the
                        // burned-shell stack so they read as part of the same
                        // composition rather than orphaned at the bottom.
                        VStack(spacing: 8) {
                            WaveLine(wavelength: 10, amplitude: 2)
                                .stroke(Color.stampText.opacity(0.8), lineWidth: 1.4)
                                .frame(width: 180, height: 8)
                                .mask(
                                    Rectangle()
                                        .frame(width: 180 * bustProgress, height: 8)
                                )
                            Text("tap to continue")
                                .font(.avenir(12, weight: .demiBold, italic: true))
                                .tracking(2)
                                .textCase(.lowercase)
                                .foregroundStyle(Color.stampText.opacity(0.9))
                        }
                        .padding(.top, 12)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { dismissBustFlash() }
                .transition(.opacity)
            }
        }
        .overlay {
            if let event = store.aiEvent {
                AIEventBanner(
                    event: event,
                    countdown: autoContinues(event) ? aiEventProgress : nil
                ) {
                    store.dismissAIEvent()
                }
                .animation(.easeOut(duration: 0.2), value: store.aiEvent)
            }
        }
        .onChange(of: store.aiEvent) { _, event in
            guard let event, autoContinues(event) else {
                // Cancels whatever was counting: either the banner was
                // tapped away, or the one that replaced it is a banner
                // the player has to answer themselves.
                aiEventGeneration += 1
                return
            }
            startAutoContinue(for: event)
        }
        // Tally screen waits until the last-shell banner is dismissed.
        // Without this gate, the fullScreenCover races the AIEventBanner
        // overlay and covers it the instant `state.phase` flips to .over,
        // so the player never gets to read "X claimed the last shell."
        // `bustFlash` is gated too so a bust that burns the last supply
        // tile gets its full "Oh, shell no" moment before the tally.
        // `bustAnimatedRoll` has to be gated alongside it: the flash is
        // only raised *after* the fake roll finishes, so on its own
        // `bustFlash` is still false while the dice are in the air and
        // the tally would cover the roll and the banner both.
        .fullScreenCover(
            isPresented: .constant(
                store.isOver && store.aiEvent == nil
                    && !bustFlash && bustAnimatedRoll == nil
            )
        ) {
            // The cover is presented at window level, outside the
            // canvas the game screen sits in, so it needs its own —
            // otherwise the tally meets a raw iPad window and clips
            // the same way the board did.
            PhoneCanvas {
            CountingCeremony(
                players: store.state.players,
                scores: store.scores,
                onNewGame: {
                    Telemetry.shared.track("game_end_action", props: ["choice": "new_game"])
                    startNewGame()
                },
                onHome: {
                    Telemetry.shared.track("game_end_action", props: ["choice": "home"])
                    resetTransientGameUI()
                    store.dismissAIEvent()
                    // goHome starts a fresh game and drains the nav
                    // stack, so `store.isOver` flips false and this
                    // cover dismisses on its own.
                    goHome()
                },
                // Evaluated as the tally appears, so `stats` already
                // includes the game that just finished.
                reviewEligible: ReviewPrompt.shared.isEligible(
                    gamesPlayed: stats.gamesPlayed,
                    wins: stats.wins
                ),
                reviewGamesPlayed: stats.gamesPlayed,
                reviewWins: stats.wins,
                // Same timing as the review ask, same reason: `stats`
                // already counts the game that just finished, so the
                // third game on Easy is offered the step up on the
                // tally it earned.
                nudgeEligible: DifficultyNudge.shared.isEligible(
                    settings: settings,
                    stats: stats
                ),
                nudgeGamesOnEasy: stats.gamesByDifficulty[Difficulty.easy.rawValue] ?? 0,
                nudgeWinsOnEasy: stats.winsByDifficulty[Difficulty.easy.rawValue] ?? 0,
                onStepUpDifficulty: {
                    settings.difficulty = .normal
                }
            )
            }
        }
        .navigationBarHidden(true)
        #if DEBUG
        .sheet(isPresented: $debugShowStats) {
            StatsView(stats: stats)
        }
        #endif
    }
}

struct ChromeBar: View {
    let settings: SettingsStore
    var onDebugSeedAI: (() -> Void)? = nil
    var onDebugSteal: (() -> Void)? = nil
    var onDebugBankChoice: (() -> Void)? = nil
    var onDebugEndGame: (() -> Void)? = nil
    var onDebugSeedBests: (() -> Void)? = nil
    var onDebugShowStats: (() -> Void)? = nil
    var onDebugForceNudge: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text("Shell Yes")
                .font(.custom("Optima", size: 22).weight(.semibold))
                .tracking(0.5)
                .foregroundStyle(Color.ink)

            Spacer()

            #if DEBUG
            if !ScreenshotMode.isActive {
            Menu {
                if let onDebugSeedAI {
                    Button("Seed AI vaults (+2 each)", systemImage: "shell.fill", action: onDebugSeedAI)
                }
                if let onDebugSteal {
                    Button("Trigger steal", systemImage: "hand.raised.fill", action: onDebugSteal)
                }
                if let onDebugBankChoice {
                    Button("Trigger bank choice", systemImage: "questionmark.diamond.fill", action: onDebugBankChoice)
                }
                if let onDebugForceNudge {
                    Button(
                        DifficultyNudge.debugForce
                            ? "Difficulty nudge: armed"
                            : "Arm difficulty nudge",
                        systemImage: DifficultyNudge.debugForce ? "checkmark.circle.fill" : "arrow.up.right.circle",
                        action: onDebugForceNudge
                    )
                }
                if let onDebugEndGame {
                    Button("End game (tally + Home button)", systemImage: "flag.checkered", action: onDebugEndGame)
                }
                if let onDebugSeedBests {
                    Button("Seed personal bests", systemImage: "trophy.fill", action: onDebugSeedBests)
                }
                if let onDebugShowStats {
                    Button("Open stats", systemImage: "chart.bar.fill", action: onDebugShowStats)
                }
                // Design tool: writes the fourteen 512x512 achievement
                // PNGs to the app's Documents directory, ready to
                // upload to App Store Connect.
                Button("Export achievement badges", systemImage: "square.and.arrow.up") {
                    AchievementArtExporter.exportAll()
                }
            } label: {
                Image(systemName: "ladybug.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.coral.opacity(0.85))
                    .padding(8)
            }
            .accessibilityLabel("Debug menu")
            }
            #endif

            NavigationLink(value: Route.settings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .padding(8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
        .padding(.bottom, 0)
    }
}

struct ActionBar: View {
    let canRoll: Bool
    let isHumanTurn: Bool
    let isOver: Bool
    let hasSetAside: Bool
    let activePlayerName: String
    let onRoll: () -> Void

    @SwiftUI.State private var pulse: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if isOver {
                Text("game over")
                    .font(.avenir(14, weight: .medium, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.dimInk)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if !isHumanTurn {
                HStack {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(activePlayerName) is playing")
                            .font(.avenir(15, weight: .medium, italic: true))
                            .foregroundStyle(Color.ink.opacity(0.55))
                        Text("…")
                            .font(.avenir(15, weight: .demiBold))
                            .foregroundStyle(Color.ink.opacity(pulse ? 0.85 : 0.3))
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: 280)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.4))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.ink.opacity(0.2), lineWidth: 1)
                    )
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 4)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        pulse.toggle()
                    }
                }
            } else {
                // Single position-stable Roll button — never moves between
                // turns or phases. Bank is anchored to the running sum
                // inside DiceStage, so the bottom of the screen always
                // means "throw the dice."
                HStack {
                    Spacer()
                    Button("Roll On") { onRoll() }
                        .stampButton(primary: true, invite: canRoll, inviteHalo: false)
                        .disabled(!canRoll)
                        .opacity(canRoll ? 1.0 : 0.4)
                        .frame(maxWidth: 280)
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .bottom)
    }
}

#Preview {
    GameView(store: GameStore(settings: SettingsStore()), settings: SettingsStore(), stats: StatsStore())
}
