import XCTest
@testable import ShellYes

@MainActor
final class SettingsStoreTests: XCTestCase {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"
    private static let soundModeKey = "ching.soundMode"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
        UserDefaults.standard.removeObject(forKey: Self.soundModeKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: Self.difficultyKey)
        UserDefaults.standard.removeObject(forKey: Self.colorModeKey)
        UserDefaults.standard.removeObject(forKey: Self.reducedMotionKey)
        UserDefaults.standard.removeObject(forKey: Self.soundModeKey)
        super.tearDown()
    }

    func test_difficulty_defaultIsEasy() {
        let store = SettingsStore()
        XCTAssertEqual(store.difficulty, .easy)
    }

    func test_difficulty_persistsAcrossInstances() {
        let a = SettingsStore()
        a.difficulty = .hard
        let b = SettingsStore()
        XCTAssertEqual(b.difficulty, .hard)
    }

    func test_colorMode_defaultIsSystem() {
        let store = SettingsStore()
        XCTAssertEqual(store.colorMode, .system)
    }

    func test_colorMode_persistsAcrossInstances() {
        let a = SettingsStore()
        a.colorMode = .dark
        let b = SettingsStore()
        XCTAssertEqual(b.colorMode, .dark)
    }

    func test_reducedMotion_defaultIsFalse() {
        let store = SettingsStore()
        XCTAssertFalse(store.reducedMotion)
    }

    func test_reducedMotion_persistsAcrossInstances() {
        let a = SettingsStore()
        a.reducedMotion = true
        let b = SettingsStore()
        XCTAssertTrue(b.reducedMotion)
    }

    func test_soundMode_defaultIsAll() {
        let store = SettingsStore()
        XCTAssertEqual(store.soundMode, .all)
    }

    func test_soundMode_persistsAcrossInstances() {
        let a = SettingsStore()
        a.soundMode = .gameOnly
        let b = SettingsStore()
        XCTAssertEqual(b.soundMode, .gameOnly)
    }
}
