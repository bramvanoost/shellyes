import XCTest
@testable import ShellYes

/// What the splash is allowed to show, and when.
///
/// The weekly boards are never backfilled on purpose — a best run from
/// March did not happen this week. So a player with years of history
/// and no game this week has no weekly rank, and the splash shows an
/// empty stack rather than standing all-time seniority lines in its
/// place. The one all-time line that survives is a held number one.
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

    /// All-time ranks never stand in for an empty week: five seniority
    /// lines above New Game say less than the blank space does.
    func test_splashRanks_staysEmptyWithOnlyAllTimeRanks() {
        let s = store(with: [
            allTime(.scoreEasy, rank: 12),
            allTime(.bestStreak, rank: 30),
        ])
        XCTAssertTrue(s.splashRanks.isEmpty)
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

    /// And it is the only line left when there is no weekly rank: the
    /// stack above is empty, the crown still earns its row.
    func test_splashCrown_survivesAnEmptyWeek() {
        let s = store(with: [
            allTime(.scoreHard, rank: 1),
            allTime(.bestStreak, rank: 30),
        ])
        XCTAssertTrue(s.splashRanks.isEmpty)
        XCTAssertEqual(s.splashCrown?.boardID, Leaderboard.scoreHard.rawValue)
    }

    func test_splashCrown_isNilWithoutANumberOne() {
        let s = store(with: [
            weekly(.scoreEasy, rank: 4),
            allTime(.scoreHard, rank: 2),
        ])
        XCTAssertNil(s.splashCrown)
    }
}
