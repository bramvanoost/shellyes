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

    func test_difficulty_modifierTable() {
        XCTAssertEqual(Difficulty.easy.modifier, -0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.normal.modifier, 0, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.hard.modifier, 0.15, accuracy: 0.0001)
        XCTAssertEqual(Difficulty.allCases, [.easy, .normal, .hard])
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
}
