import XCTest
import ShellYesEngine
@testable import ShellYes

@MainActor
final class GameStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
        super.tearDown()
    }

    private func makeStore(seed: UInt32 = 1) -> GameStore {
        GameStore(seed: seed, settings: SettingsStore())
    }

    /// A guard backed by its own suite, so arming in a test never
    /// reaches the defaults the app reads at launch.
    private func freshGuard(_ name: String = UUID().uuidString) -> AbandonGuard {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return AbandonGuard(defaults: defaults)
    }

    func test_init_setsUpThreePlayersHumanTurnRollPhase() {
        let store = makeStore(seed: 1)
        XCTAssertEqual(store.state.players.count, 3)
        XCTAssertEqual(store.state.players[0].id, "YOU")
        // The two rival seats draw random distinct names from the pool
        // on every new game, so assert the shape, not the literals.
        let rivals = [store.state.players[1].id, store.state.players[2].id]
        XCTAssertEqual(Set(rivals).count, 2)
        XCTAssertFalse(rivals.contains("YOU"))
        XCTAssertFalse(rivals.contains(where: \.isEmpty))
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.current, 0)
        XCTAssertTrue(store.isHumanTurn)
        XCTAssertFalse(store.isOver)
        XCTAssertEqual(store.scores, [0, 0, 0])
    }

    func test_apply_rollAdvancesPhaseOrTurn() {
        let store = makeStore(seed: 1)
        store.apply(.roll)
        let advanced = store.state.phase == .pick || store.state.current != 0
        XCTAssertTrue(advanced)
    }

    func test_newGame_resetsState() {
        let store = makeStore(seed: 1)
        store.apply(.roll)
        store.newGame()
        XCTAssertEqual(store.state.centerTiles, Array(21...36))
        XCTAssertEqual(store.state.phase, .roll)
        XCTAssertEqual(store.state.players[0].tiles, [])
        XCTAssertEqual(store.state.players[1].tiles, [])
        XCTAssertEqual(store.state.players[2].tiles, [])
        XCTAssertEqual(store.state.current, 0)
    }

    func test_runAIIfNeeded_isNoOpOnHumanTurn() async {
        let store = makeStore(seed: 1)
        let before = store.state
        await store.runAIIfNeeded(reduceMotion: true)
        XCTAssertEqual(store.state, before)
    }

    func test_runAIIfNeeded_reduceMotionRunsInstantly() async {
        let store = makeStore(seed: 1)
        let start = Date()
        await store.runAIIfNeeded(reduceMotion: true)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func test_fullThreePlayerGameTerminates() {
        let store = makeStore(seed: 1)
        var safetyLimit = 5000
        while !store.isOver && safetyLimit > 0 {
            let action = decide(state: store.state, ai: ShellYesEngine.Difficulty(discipline: 0.5))
            store.apply(action)
            safetyLimit -= 1
        }
        XCTAssertTrue(store.isOver, "3-player game should terminate within 5000 actions")
        XCTAssertGreaterThan(safetyLimit, 0)
        XCTAssertEqual(store.state.players.count, 3)
    }

    func test_difficulty_seatDisciplineTable() {
        XCTAssertEqual(Difficulty.easy.seatDiscipline, [0.00, 0.00])
        XCTAssertEqual(Difficulty.normal.seatDiscipline, [0.20, 0.00])
        XCTAssertEqual(Difficulty.hard.seatDiscipline, [0.20, 0.50])
        XCTAssertEqual(Difficulty.allCases, [.easy, .normal, .hard])
    }

    /// Only Easy bends the dice. A score posted on Normal or Hard has
    /// to mean what it always did, because both boards carry results
    /// from before the handicap existed.
    func test_difficulty_onlyEasyBendsTheDice() {
        XCTAssertEqual(Difficulty.easy.luck, 0.05)
        XCTAssertEqual(Difficulty.normal.luck, 0)
        XCTAssertEqual(Difficulty.hard.luck, 0)
    }

    /// The bend has to stay under the engine's cap, where the 1 would
    /// stop coming up at all.
    func test_difficulty_luckStaysUnderTheCap() {
        for difficulty in Difficulty.allCases {
            XCTAssertGreaterThanOrEqual(difficulty.luck, 0)
            XCTAssertLessThan(difficulty.luck, maxLuck)
        }
    }

    /// Every difficulty has to describe both AI seats. A short table
    /// would silently drop a seat to the 0.5 fallback, which plays a
    /// perfectly good game at the wrong difficulty — the kind of bug
    /// that only shows up as "easy feels hard".
    func test_difficulty_everyTierCoversBothAISeats() {
        for difficulty in Difficulty.allCases {
            XCTAssertEqual(
                difficulty.seatDiscipline.count, 2,
                "\(difficulty.rawValue) must give a discipline for both AI seats"
            )
        }
    }

    /// No seat may get *more* disciplined as the game gets easier.
    ///
    /// This does not prove Easy is easier — strength is not monotone in
    /// discipline at a three-seat table, which is exactly how 1.2
    /// shipped an Easy that was harder than Normal. `npm run
    /// sim:difficulty` is what proves that, over 20,000 games a tier.
    /// This is the cheap guard that catches a typo'd table.
    func test_difficulty_disciplineNeverFallsAsTheGameGetsHarder() {
        let ladder = [Difficulty.easy, .normal, .hard].map(\.seatDiscipline)
        for seat in 0..<2 {
            for tier in 1..<ladder.count {
                XCTAssertGreaterThanOrEqual(
                    ladder[tier][seat], ladder[tier - 1][seat],
                    "seat \(seat) gets softer between tier \(tier - 1) and \(tier)"
                )
            }
        }
    }

    func test_phaseHint_byPhaseAndSeat() {
        let store = makeStore(seed: 1)
        XCTAssertEqual(store.phaseHint, "Your turn. Deep breath.")

        var s = store.state
        s.phase = .pick
        s.rolled = [.three, .three, .five, .coin]
        store.setStateForTesting(s)
        XCTAssertEqual(store.phaseHint, "Pick what you'll keep.")

        s.current = GameStore.jonesSeat
        s.phase = .roll
        store.setStateForTesting(s)
        let rival = store.state.players[GameStore.jonesSeat].id.capitalized
        XCTAssertEqual(store.phaseHint, "\(rival) reads the tide…")
    }

    func test_burnedCount_derivesFromMissingSafes() {
        let store = makeStore(seed: 1)
        XCTAssertEqual(store.burnedCount, 0)

        var s = store.state
        s.centerTiles = [23, 24, 25]
        s.players[0].tiles = [21, 22]
        s.players[1].tiles = [26, 27, 28]
        store.setStateForTesting(s)
        XCTAssertEqual(store.burnedCount, 8)
    }

    /// Fixture for a human turn parked in `.roll` with a bankable
    /// set-aside summing to 25 (a coin is present, so banking is legal).
    private func stealFixture(_ store: GameStore, centerTiles: [Int]) -> State {
        var s = store.state
        s.centerTiles = centerTiles
        s.setAside = [.five, .coin, .five, .four, .three, .three]
        s.pickedFaces = [.five, .coin, .four, .three]
        s.diceInHand = 2
        s.phase = .roll
        s.current = GameStore.humanSeat
        return s
    }

    func test_bankActionLabel_namesTheVictimWhenStealIsTheOnlyOption() {
        let store = makeStore(seed: 1)
        // No center shell is reachable at sum 25, and only one rival's
        // top matches, so the steal is the single legal bank option.
        var s = stealFixture(store, centerTiles: [30, 31])
        s.players[1].tiles = [25]
        s.players[2].tiles = [30]
        store.setStateForTesting(s)
        XCTAssertEqual(store.setAsideSum, 25)
        XCTAssertTrue(store.isStealOpportunity)
        let victim = store.state.players[GameStore.jonesSeat].id.capitalized
        XCTAssertEqual(store.bankActionLabel, "Take \(victim)'s shell")
    }

    func test_bankActionLabel_defersToChoiceWhenStealAndCenterBothOffered() {
        let store = makeStore(seed: 1)
        // Center holds a reachable shell AND a rival's top matches, so
        // the engine will park in `.chooseBank` rather than auto-commit.
        var s = stealFixture(store, centerTiles: [24, 30])
        s.players[1].tiles = [25]
        s.players[2].tiles = [30]
        store.setStateForTesting(s)
        XCTAssertFalse(store.isStealOpportunity)
        XCTAssertEqual(store.bankActionLabel, "Choose…")
    }

    // MARK: - Abandon guard

    /// Dealing a game is not playing one. A player who opens New Game
    /// and backs straight out has not quit anything.
    func test_abandonGuard_isNotArmedUntilThePlayerActs() {
        let guarded = freshGuard()
        _ = GameStore(seed: 1, settings: SettingsStore(), abandonGuard: guarded)
        XCTAssertNil(guarded.armedGame)
    }

    func test_abandonGuard_armsOnTheFirstAction() {
        let guarded = freshGuard()
        let settings = SettingsStore()
        settings.difficulty = .hard
        let store = GameStore(seed: 1, settings: settings, abandonGuard: guarded)

        store.apply(.roll)

        XCTAssertEqual(guarded.armedGame?.difficulty, "hard")
    }

    /// A game played to the end is not an abandonment, and must not be
    /// charged as one on the next launch.
    func test_abandonGuard_disarmsWhenTheGameEndsProperly() {
        let guarded = freshGuard()
        let store = GameStore(seed: 1, settings: SettingsStore(), abandonGuard: guarded)

        var safetyLimit = 5000
        while !store.isOver && safetyLimit > 0 {
            store.apply(decide(state: store.state, ai: ShellYesEngine.Difficulty(discipline: 0.5)))
            safetyLimit -= 1
        }

        XCTAssertTrue(store.isOver)
        XCTAssertNil(guarded.armedGame)
    }

    /// Walking out through Home or New Game costs the same as
    /// force-quitting: the loss is filed there and then, and the guard
    /// is cleared so the next launch doesn't charge for it twice.
    ///
    /// One roll and out, deliberately. That claims no shell and leaves
    /// the beach full, which is below the bar `game_abandoned` uses to
    /// decide a quit is worth *reporting* — and it is precisely the
    /// quit this fix has to charge for. Sharing that bar let "roll
    /// badly, tap Home" stay free while force-quitting was punished.
    func test_newGame_filesTheLossForAGameInProgress() {
        let guarded = freshGuard()
        let name = UUID().uuidString
        let statsDefaults = UserDefaults(suiteName: name)!
        statsDefaults.removePersistentDomain(forName: name)
        let stats = StatsStore(defaults: statsDefaults)
        stats.recordGameOver(
            humanWon: true, humanScore: 20,
            difficulty: "normal", pace: "normal"
        )
        XCTAssertEqual(stats.winStreak, 1)

        let store = GameStore(
            seed: 1, settings: SettingsStore(), stats: stats, abandonGuard: guarded
        )
        store.apply(.roll)
        store.newGame()

        XCTAssertEqual(stats.winStreak, 0)
        XCTAssertEqual(stats.gamesPlayed, 2)
        XCTAssertNil(guarded.armedGame)
    }

    /// The bar for charging a quit is the same bar `reportAbandonedGame`
    /// uses for reporting one: a game nobody touched is neither.
    func test_newGame_doesNotFileALossForAnUntouchedGame() {
        let guarded = freshGuard()
        let name = UUID().uuidString
        let statsDefaults = UserDefaults(suiteName: name)!
        statsDefaults.removePersistentDomain(forName: name)
        let stats = StatsStore(defaults: statsDefaults)
        stats.recordGameOver(
            humanWon: true, humanScore: 20,
            difficulty: "normal", pace: "normal"
        )

        let store = GameStore(
            seed: 1, settings: SettingsStore(), stats: stats, abandonGuard: guarded
        )
        store.newGame()

        XCTAssertEqual(stats.winStreak, 1)
        XCTAssertEqual(stats.gamesPlayed, 1)
    }
}
