import XCTest
@testable import ShellYes

@MainActor
final class StatsStoreTests: XCTestCase {
    /// Each test gets its own suite so records never leak between runs
    /// or into the simulator's real stats.
    private func freshStore(_ name: String = UUID().uuidString) -> StatsStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return StatsStore(defaults: defaults)
    }

    private func day(_ offset: Int) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 86_400)
    }

    func test_recordGameOver_filesTheRunWithItsSettingsAndDate() {
        let stats = freshStore()
        stats.recordGameOver(
            humanWon: true, humanScore: 21,
            difficulty: "hard", pace: "slow", date: day(0)
        )

        XCTAssertEqual(stats.bestRuns.count, 1)
        let run = stats.bestRuns[0]
        XCTAssertEqual(run.score, 21)
        XCTAssertEqual(run.difficulty, "hard")
        XCTAssertEqual(run.pace, "slow")
        XCTAssertEqual(run.date, day(0))
        XCTAssertTrue(run.won)
        XCTAssertEqual(run.settingLabel, "Hard · Slow")
    }

    func test_bestRuns_sortedByScoreThenRecency() {
        let stats = freshStore()
        stats.recordGameOver(humanWon: false, humanScore: 14, difficulty: "easy", pace: "fast", date: day(0))
        stats.recordGameOver(humanWon: true, humanScore: 30, difficulty: "normal", pace: "fast", date: day(1))
        // Same score as the leader but newer, so it takes the top slot.
        stats.recordGameOver(humanWon: true, humanScore: 30, difficulty: "hard", pace: "slow", date: day(2))

        XCTAssertEqual(stats.bestRuns.map(\.score), [30, 30, 14])
        XCTAssertEqual(stats.bestRuns[0].difficulty, "hard")
    }

    func test_bestRuns_keepsOnlyTheTopFive() {
        let stats = freshStore()
        for i in 0..<8 {
            stats.recordGameOver(
                humanWon: false, humanScore: i,
                difficulty: "normal", pace: "fast", date: day(i)
            )
        }

        XCTAssertEqual(stats.bestRuns.count, StatsStore.bestRunsKept)
        XCTAssertEqual(stats.bestRuns.map(\.score), [7, 6, 5, 4, 3])
    }

    func test_bestRuns_survivesReload() {
        let suite = UUID().uuidString
        let stats = freshStore(suite)
        stats.recordGameOver(
            humanWon: true, humanScore: 27,
            difficulty: "hard", pace: "slow", date: day(3)
        )

        let reloaded = StatsStore(defaults: UserDefaults(suiteName: suite)!)
        XCTAssertEqual(reloaded.bestRuns, stats.bestRuns)
    }

    func test_recordGameOver_stillUpdatesTheScalarTotals() {
        let stats = freshStore()
        stats.recordGameOver(humanWon: true, humanScore: 25, difficulty: "normal", pace: "fast", date: day(0))
        stats.recordGameOver(humanWon: false, humanScore: 12, difficulty: "normal", pace: "fast", date: day(1))

        XCTAssertEqual(stats.gamesPlayed, 2)
        XCTAssertEqual(stats.wins, 1)
        XCTAssertEqual(stats.bestScore, 25)
        XCTAssertEqual(stats.winStreak, 0)
        XCTAssertEqual(stats.bestStreak, 1)
    }

    // MARK: - Abandoned games

    /// The whole point of the fix: walking out mid-game must cost the
    /// streak, or quitting a bad game stays strictly better than
    /// finishing it. See `AbandonGuard`.
    func test_recordAbandonedGame_breaksTheWinStreak() {
        let stats = freshStore()
        stats.recordGameOver(
            humanWon: true, humanScore: 20,
            difficulty: "normal", pace: "normal", date: day(0)
        )
        stats.recordGameOver(
            humanWon: true, humanScore: 22,
            difficulty: "normal", pace: "normal", date: day(1)
        )
        XCTAssertEqual(stats.winStreak, 2)

        stats.recordAbandonedGame(difficulty: "normal", pace: "normal")

        XCTAssertEqual(stats.winStreak, 0)
        // The high-water mark stands — it was reached, and reaching it
        // is what the board records.
        XCTAssertEqual(stats.bestStreak, 2)
    }

    func test_recordAbandonedGame_countsAsAGamePlayedButNotAWin() {
        let stats = freshStore()
        stats.recordAbandonedGame(difficulty: "hard", pace: "slow")

        XCTAssertEqual(stats.gamesPlayed, 1)
        XCTAssertEqual(stats.wins, 0)
        XCTAssertEqual(stats.gamesByDifficulty["hard"], 1)
        XCTAssertNil(stats.winsByDifficulty["hard"])
        XCTAssertEqual(stats.gamesByPace["slow"], 1)
        XCTAssertNil(stats.winsByPace["slow"])
    }

    /// A walked-out game has a partial score. It must not reach the
    /// personal bests, the best-runs archive, or the weekly pool —
    /// that pool is exactly what the quitting was gaming.
    func test_recordAbandonedGame_leavesTheRecordsAlone() {
        let stats = freshStore()
        stats.recordGameOver(
            humanWon: true, humanScore: 30,
            difficulty: "normal", pace: "normal", date: day(0)
        )
        let weeklyBefore = stats.weekly

        stats.recordAbandonedGame(difficulty: "normal", pace: "normal")

        XCTAssertEqual(stats.bestScore, 30)
        XCTAssertEqual(stats.bestRuns.count, 1)
        XCTAssertEqual(stats.weekly, weeklyBefore)
    }
}
