import XCTest
@testable import ShellYes

/// What the splash is allowed to show, and when.
///
/// The weekly boards are never backfilled on purpose — a best run from
/// March did not happen this week. The cost of that correctness was a
/// signed-in player with years of history staring at a splash with no
/// rank on it, which reads as the feature being broken. `splashRanks`
/// is the fallback that fixes it without touching what gets submitted.
@MainActor
final class StandingsTests: XCTestCase {

    private func freshStore(_ name: String = UUID().uuidString) -> StandingsStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return StandingsStore(defaults: defaults)
    }

    private func weekly(
        _ board: WeeklyLeaderboard,
        rank: Int,
        total: Int = 100,
        score: Int = 20
    ) -> BoardStanding {
        BoardStanding(
            boardID: board.rawValue, period: .week,
            rank: rank, total: total, score: score
        )
    }

    private func allTime(
        _ board: Leaderboard,
        rank: Int,
        total: Int = 100,
        score: Int = 20
    ) -> BoardStanding {
        BoardStanding(
            boardID: board.rawValue, period: .allTime,
            rank: rank, total: total, score: score
        )
    }

    /// Seeds the store through its own cache, so the tests exercise the
    /// decoding path the app actually uses on launch.
    private func store(with standings: [BoardStanding]) -> StandingsStore {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set(try! JSONEncoder().encode(standings), forKey: "standings.cached")
        return StandingsStore(defaults: defaults)
    }

    // MARK: - splashRanks

    func test_splashRanks_prefersThisWeek() {
        let s = store(with: [
            weekly(.scoreEasy, rank: 4),
            allTime(.scoreEasy, rank: 12),
            allTime(.bestStreak, rank: 30),
        ])
        XCTAssertEqual(s.splashRanks.map(\.boardID), [WeeklyLeaderboard.scoreEasy.rawValue])
    }

    /// The case the fix exists for: a backfilled history, no game
    /// played yet this week.
    func test_splashRanks_fallsBackToAllTimeWhenNoWeeklyRankYet() {
        let s = store(with: [
            allTime(.scoreEasy, rank: 12),
            allTime(.bestStreak, rank: 30),
        ])
        XCTAssertEqual(s.splashRanks.count, 2)
        XCTAssertTrue(s.splashRanks.allSatisfy { !$0.isWeekly })
    }

    func test_splashRanks_isEmptyForAPlayerWhoHasNeverPlaced() {
        XCTAssertTrue(freshStore().splashRanks.isEmpty)
    }

    // MARK: - splashCrown

    /// A held all-time number one is promoted under the weekly lines,
    /// because it is the best thing about the account and would
    /// otherwise never be seen.
    func test_splashCrown_promotesAHeldNumberOneUnderTheWeeklyRanks() {
        let s = store(with: [
            weekly(.scoreEasy, rank: 4),
            allTime(.scoreHard, rank: 1),
        ])
        XCTAssertEqual(s.splashCrown?.boardID, Leaderboard.scoreHard.rawValue)
    }

    /// But not when the stack above is already showing all-time ranks:
    /// the crown's own line is up there, and promoting it again would
    /// print the same standing twice.
    func test_splashCrown_isNilWhenTheFallbackAlreadyShowsIt() {
        let s = store(with: [
            allTime(.scoreHard, rank: 1),
            allTime(.bestStreak, rank: 30),
        ])
        XCTAssertEqual(s.splashRanks.count, 2)
        XCTAssertNil(s.splashCrown)
    }

    func test_splashCrown_isNilWithoutANumberOne() {
        let s = store(with: [
            weekly(.scoreEasy, rank: 4),
            allTime(.scoreHard, rank: 2),
        ])
        XCTAssertNil(s.splashCrown)
    }
}
