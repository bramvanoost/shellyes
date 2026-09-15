import XCTest
@testable import ShellYes

/// The six weekly achievements added in 1.4. Three turn on what the
/// player did with their week, three on where they stand. Both halves
/// are pure: `AchievementRules` takes snapshots, so none of this needs
/// GameKit, a signed build, or a real week to pass.
final class WeeklyAchievementTests: XCTestCase {

    // MARK: - Remembering last week

    private func week(
        id: String = "2026-W37",
        scores: [String: [Int]] = [:],
        bestStreak: Int = 0,
        biggestKeep: Int = 0,
        previous: WeeklyBests.PreviousWeek? = nil
    ) -> WeeklyBests {
        WeeklyBests(
            weekID: id,
            scoresByDifficulty: scores,
            bestStreak: bestStreak,
            biggestKeep: biggestKeep,
            previous: previous
        )
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.date(from: iso)!
    }

    func test_rollover_keepsTheWeekItIsLeaving() {
        let before = week(scores: ["easy": [10, 8]], bestStreak: 3, biggestKeep: 12)
        let after = before.rolledOver(to: date("2026-09-21T12:00:00Z"))

        XCTAssertNotEqual(after.weekID, before.weekID, "should have rolled")
        XCTAssertEqual(after.previous?.weekID, before.weekID)
        XCTAssertEqual(after.previous?.scoreByDifficulty["easy"], 18, "the summed score, not the games")
        XCTAssertEqual(after.previous?.bestStreak, 3)
        XCTAssertEqual(after.previous?.biggestKeep, 12)
        XCTAssertTrue(after.scoresByDifficulty.isEmpty, "the new week starts empty")
    }

    /// A week nobody played is not worth remembering, and remembering
    /// it would wipe the last week that had something in it.
    func test_rollover_emptyWeekDoesNotDisplaceTheLastPlayedOne() {
        let played = WeeklyBests.PreviousWeek(
            weekID: "2026-W30", scoreByDifficulty: ["easy": 40], bestStreak: 5, biggestKeep: 9
        )
        let idle = week(id: "2026-W37", previous: played)
        let after = idle.rolledOver(to: date("2026-09-21T12:00:00Z"))
        XCTAssertEqual(after.previous?.weekID, "2026-W30")
    }

    func test_rollover_withinTheSameWeekChangesNothing() {
        let now = week(scores: ["easy": [10]])
        XCTAssertEqual(now.rolledOver(to: date("2026-09-10T12:00:00Z")).weekID, now.weekID)
    }

    // MARK: - What the week's numbers say

    func test_boardsPosted_countsOnlyBoardsWithSomethingOnThem() {
        XCTAssertEqual(week().boardsPosted, 0)
        XCTAssertEqual(week(scores: ["easy": [5]]).boardsPosted, 1)
        XCTAssertEqual(
            week(
                scores: ["easy": [5], "normal": [4], "hard": [3]],
                bestStreak: 2,
                biggestKeep: 7
            ).boardsPosted,
            WeeklyBests.boardCount
        )
    }

    func test_bestOfThree_needsAllThreeOnOneDifficulty() {
        XCTAssertFalse(week(scores: ["easy": [5, 4]]).hasFilledBestOfThree)
        XCTAssertFalse(week(scores: ["easy": [5, 4], "hard": [3, 2]]).hasFilledBestOfThree)
        XCTAssertTrue(week(scores: ["easy": [5, 4, 3]]).hasFilledBestOfThree)
    }

    func test_beatsPreviousWeek_needsAWeekToBeat() {
        XCTAssertFalse(week(scores: ["easy": [50]]).beatsPreviousWeek, "no previous week at all")

        /// Coming back from nothing beats a zero arithmetically. It is
        /// not "better than last week" in any sense a player means.
        let blank = WeeklyBests.PreviousWeek(
            weekID: "2026-W36", scoreByDifficulty: [:], bestStreak: 0, biggestKeep: 0
        )
        XCTAssertFalse(week(scores: ["easy": [50]], previous: blank).beatsPreviousWeek)
    }

    func test_beatsPreviousWeek_onAnyOfTheFiveBoards() {
        let before = WeeklyBests.PreviousWeek(
            weekID: "2026-W36", scoreByDifficulty: ["easy": 20], bestStreak: 4, biggestKeep: 10
        )
        XCTAssertTrue(week(scores: ["easy": [21]], previous: before).beatsPreviousWeek)
        XCTAssertTrue(week(bestStreak: 5, previous: before).beatsPreviousWeek)
        XCTAssertTrue(week(biggestKeep: 11, previous: before).beatsPreviousWeek)

        XCTAssertFalse(week(scores: ["easy": [20]], previous: before).beatsPreviousWeek, "equal is not better")
        XCTAssertFalse(week(scores: ["easy": [19]], bestStreak: 4, previous: before).beatsPreviousWeek)
    }

    // MARK: - The badges themselves

    func test_weekBadges_turnOnTheirOwnFact() {
        let none = AchievementRules.unlocked(
            weekly: WeeklyProgress(boardsPosted: 2, filledBestOfThree: false, beatLastWeek: false)
        )
        XCTAssertTrue(none.isEmpty)

        XCTAssertEqual(
            AchievementRules.unlocked(
                weekly: WeeklyProgress(boardsPosted: 5, filledBestOfThree: false, beatLastWeek: false)
            ),
            [.weekSweep]
        )
        XCTAssertEqual(
            AchievementRules.unlocked(
                weekly: WeeklyProgress(boardsPosted: 1, filledBestOfThree: true, beatLastWeek: false)
            ),
            [.weekBestOfThree]
        )
        XCTAssertEqual(
            AchievementRules.unlocked(
                weekly: WeeklyProgress(boardsPosted: 1, filledBestOfThree: false, beatLastWeek: true)
            ),
            [.weekBetter]
        )
    }

    func test_rankBadges_stackAsTheRanksDo() {
        XCTAssertTrue(
            AchievementRules.unlocked(ranks: RankProgress(weeklyTops: 0, holdsAllTimeTop: false)).isEmpty
        )
        XCTAssertEqual(
            AchievementRules.unlocked(ranks: RankProgress(weeklyTops: 1, holdsAllTimeTop: false)),
            [.topBanana]
        )
        // Holding all five is also holding one, and Game Center shows
        // both. Whole Beach does not replace Top Banana.
        XCTAssertEqual(
            AchievementRules.unlocked(ranks: RankProgress(weeklyTops: 5, holdsAllTimeTop: false)),
            [.topBanana, .wholeBeach]
        )
        XCTAssertEqual(
            AchievementRules.unlocked(ranks: RankProgress(weeklyTops: 0, holdsAllTimeTop: true)),
            [.bigKahuna]
        )
    }

    /// A finished game must never grant a weekly badge by accident, and
    /// a weekly badge must never be reachable from lifetime totals.
    func test_theTwoHalvesDoNotLeakIntoEachOther() {
        let fromGame = AchievementRules.unlocked(
            after: GameSummary(
                won: true, score: 40, difficulty: "hard", busts: 0, steals: 3,
                claimedShells: [21, 36], endedByClaimingLastShell: true
            ),
            lifetime: LifetimeTotals(gamesPlayed: 100, wins: 50, bestStreak: 5)
        )
        let weekly: Set<Achievement> = [
            .weekSweep, .weekBestOfThree, .weekBetter, .topBanana, .wholeBeach, .bigKahuna,
        ]
        XCTAssertTrue(fromGame.isDisjoint(with: weekly))
        XCTAssertTrue(weekly.allSatisfy { !$0.isLifetime }, "none of these come from stored totals")
    }

    /// Ids are permanent once created in App Store Connect. A rename
    /// here after release orphans the record.
    func test_ids_areStableAndUnique() {
        XCTAssertEqual(Achievement.allCases.count, 20)
        XCTAssertEqual(Set(Achievement.allCases.map(\.rawValue)).count, 20)
        XCTAssertEqual(Achievement.weekSweep.rawValue, "com.fastronaut.game.shellyes.week.sweep")
        XCTAssertEqual(Achievement.topBanana.rawValue, "com.fastronaut.game.shellyes.rank.topbanana")
        XCTAssertEqual(Achievement.bigKahuna.rawValue, "com.fastronaut.game.shellyes.rank.bigkahuna")
    }
}
