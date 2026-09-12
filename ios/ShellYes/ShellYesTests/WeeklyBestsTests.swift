import XCTest
@testable import ShellYes

@MainActor
final class WeeklyBestsTests: XCTestCase {
    private func freshStore(_ name: String = UUID().uuidString) -> StatsStore {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return StatsStore(defaults: defaults)
    }

    /// Thursday 14 Nov 2024, 22:13 UTC. A fixed instant so the week
    /// identifiers below are stable forever.
    private let anchor = Date(timeIntervalSince1970: 1_731_622_400)

    private func plus(days: Int, from date: Date? = nil) -> Date {
        (date ?? anchor).addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: - Which week it is

    func test_weekID_isISOWeekInUTC() {
        XCTAssertEqual(WeeklyBests.weekID(for: anchor), "2024-W46")
        // Seven days on is the next week, whatever the weekday.
        XCTAssertEqual(WeeklyBests.weekID(for: plus(days: 7)), "2024-W47")
    }

    func test_weekID_ignoresTheDeviceTimeZone() {
        // 22:13 UTC is already Friday in Tokyo and still Thursday in
        // Los Angeles. The id must not move with the phone, because the
        // board Apple restarts is on UTC.
        let original = NSTimeZone.default
        defer { NSTimeZone.default = original }

        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        let tokyo = WeeklyBests.weekID(for: anchor)
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        let la = WeeklyBests.weekID(for: anchor)

        XCTAssertEqual(tokyo, la)
        XCTAssertEqual(tokyo, "2024-W46")
    }

    func test_weekID_rollsOverAtTheYearBoundaryByISORules() {
        // 30 Dec 2024 is a Monday and ISO week 1 of 2025, not week 53
        // of 2024. Calendar year and ISO week-year disagree here, which
        // is exactly the case `yearForWeekOfYear` exists for.
        let dec30 = Date(timeIntervalSince1970: 1_735_516_800)
        XCTAssertEqual(WeeklyBests.weekID(for: dec30), "2025-W01")
    }

    // MARK: - Top three

    func test_score_sumsTheBestThreeOfTheWeek() {
        var week = WeeklyBests.empty(weekID: "2024-W46")
        for score in [12, 30, 7, 21] {
            week.add(score: score, difficulty: "easy")
        }

        // 30 + 21 + 12, with the 7 displaced.
        XCTAssertEqual(week.score(for: "easy"), 63)
        XCTAssertEqual(week.gamesCounted(for: "easy"), 3)
    }

    func test_score_countsFewerThanThreeGames() {
        var week = WeeklyBests.empty(weekID: "2024-W46")
        week.add(score: 18, difficulty: "hard")

        // One game this week submits that one game, so a player climbs
        // as they add more rather than waiting for a full set.
        XCTAssertEqual(week.score(for: "hard"), 18)
        XCTAssertEqual(week.gamesCounted(for: "hard"), 1)
    }

    func test_score_keepsDifficultiesApart() {
        var week = WeeklyBests.empty(weekID: "2024-W46")
        week.add(score: 30, difficulty: "easy")
        week.add(score: 11, difficulty: "hard")

        XCTAssertEqual(week.score(for: "easy"), 30)
        XCTAssertEqual(week.score(for: "hard"), 11)
        XCTAssertEqual(week.score(for: "normal"), 0)
    }

    func test_rolledOver_emptiesAStaleWeekAndKeepsACurrentOne() {
        var week = WeeklyBests.empty(weekID: WeeklyBests.weekID(for: anchor))
        week.add(score: 30, difficulty: "easy")

        XCTAssertEqual(week.rolledOver(to: plus(days: 1)).score(for: "easy"), 30)
        XCTAssertEqual(week.rolledOver(to: plus(days: 8)).score(for: "easy"), 0)
        XCTAssertEqual(week.rolledOver(to: plus(days: 8)).weekID, "2024-W47")
    }

    // MARK: - Through the store

    func test_recordGameOver_accumulatesTheWeekThenStartsFresh() {
        let stats = freshStore()
        stats.recordGameOver(humanWon: true, humanScore: 20, difficulty: "easy", pace: "slow", date: anchor)
        stats.recordGameOver(humanWon: true, humanScore: 26, difficulty: "easy", pace: "slow", date: plus(days: 1))

        XCTAssertEqual(stats.weeklyBests(on: plus(days: 1)).score(for: "easy"), 46)

        // The next week starts from nothing, and the lifetime numbers
        // are untouched by the roll-over.
        stats.recordGameOver(humanWon: false, humanScore: 9, difficulty: "easy", pace: "slow", date: plus(days: 8))
        XCTAssertEqual(stats.weeklyBests(on: plus(days: 8)).score(for: "easy"), 9)
        XCTAssertEqual(stats.gamesPlayed, 3)
        XCTAssertEqual(stats.bestScore, 26)
    }

    func test_weeklyBests_readsStaleStorageAsEmpty() {
        let stats = freshStore()
        stats.recordGameOver(humanWon: true, humanScore: 24, difficulty: "normal", pace: "fast", date: anchor)

        // Nothing was written in the new week, so the stored week is
        // still last week's. A reader must not see last week's sum.
        XCTAssertEqual(stats.weeklyBests(on: plus(days: 9)).score(for: "normal"), 0)
    }

    func test_recordGameOver_tracksTheWeeksBestStreak() {
        let stats = freshStore()
        stats.recordGameOver(humanWon: true, humanScore: 20, difficulty: "easy", pace: "slow", date: anchor)
        stats.recordGameOver(humanWon: true, humanScore: 22, difficulty: "easy", pace: "slow", date: plus(days: 1))

        XCTAssertEqual(stats.weeklyBests(on: plus(days: 1)).bestStreak, 2)
        // A loss ends the run without lowering the week's best.
        stats.recordGameOver(humanWon: false, humanScore: 8, difficulty: "easy", pace: "slow", date: plus(days: 2))
        XCTAssertEqual(stats.weeklyBests(on: plus(days: 2)).bestStreak, 2)
    }

    func test_recordBank_tracksTheWeeksBiggestKeep() {
        let stats = freshStore()
        stats.recordBank(sum: 14, stoleATile: false, date: anchor)
        stats.recordBank(sum: 9, stoleATile: false, date: anchor)

        XCTAssertEqual(stats.weeklyBests(on: anchor).biggestKeep, 14)
        XCTAssertEqual(stats.biggestKeep, 14)

        // A new week starts the keep over, lifetime keeps its record.
        stats.recordBank(sum: 6, stoleATile: false, date: plus(days: 8))
        XCTAssertEqual(stats.weeklyBests(on: plus(days: 8)).biggestKeep, 6)
        XCTAssertEqual(stats.biggestKeep, 14)
    }
}
