import XCTest
@testable import ShellYes

/// `AchievementRules` is the pure half of Game Center: no GameKit, no
/// I/O, just "given this finished game and these lifetime totals, what
/// is now unlocked". That makes every rule testable without a signed
/// build or a Game Center account.
final class AchievementRulesTests: XCTestCase {

    private func game(
        won: Bool = true,
        score: Int = 20,
        difficulty: String = "normal",
        busts: Int = 0,
        steals: Int = 0,
        claimedShells: Set<Int> = [24],
        endedByClaimingLastShell: Bool = false
    ) -> GameSummary {
        GameSummary(
            won: won,
            score: score,
            difficulty: difficulty,
            busts: busts,
            steals: steals,
            claimedShells: claimedShells,
            endedByClaimingLastShell: endedByClaimingLastShell
        )
    }

    private func lifetime(
        gamesPlayed: Int = 1,
        wins: Int = 1,
        bestStreak: Int = 1
    ) -> LifetimeTotals {
        LifetimeTotals(gamesPlayed: gamesPlayed, wins: wins, bestStreak: bestStreak)
    }

    // MARK: - Skill

    func test_firstWin_unlocksOnAWin() {
        let out = AchievementRules.unlocked(after: game(), lifetime: lifetime())
        XCTAssertTrue(out.contains(.firstWin))
    }

    func test_firstWin_staysLockedAfterALoss() {
        let out = AchievementRules.unlocked(
            after: game(won: false),
            lifetime: lifetime(gamesPlayed: 1, wins: 0, bestStreak: 0)
        )
        XCTAssertFalse(out.contains(.firstWin))
    }

    func test_cleanWin_needsAWinAndZeroBusts() {
        XCTAssertTrue(
            AchievementRules.unlocked(after: game(busts: 0), lifetime: lifetime())
                .contains(.cleanWin)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(after: game(busts: 1), lifetime: lifetime())
                .contains(.cleanWin)
        )
    }

    /// A bust-free *loss* is not a clean sweep. Easy rule to get wrong.
    func test_cleanWin_doesNotUnlockOnABustFreeLoss() {
        let out = AchievementRules.unlocked(
            after: game(won: false, busts: 0),
            lifetime: lifetime(wins: 0, bestStreak: 0)
        )
        XCTAssertFalse(out.contains(.cleanWin))
    }

    func test_hardWin_needsHardAndAWin() {
        XCTAssertTrue(
            AchievementRules.unlocked(after: game(difficulty: "hard"), lifetime: lifetime())
                .contains(.hardWin)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(after: game(difficulty: "easy"), lifetime: lifetime())
                .contains(.hardWin)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(
                after: game(won: false, difficulty: "hard"),
                lifetime: lifetime(wins: 0, bestStreak: 0)
            ).contains(.hardWin)
        )
    }

    func test_streak5_unlocksAtFiveAndNotFour() {
        XCTAssertTrue(
            AchievementRules.unlocked(after: game(), lifetime: lifetime(bestStreak: 5))
                .contains(.streak5)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(after: game(), lifetime: lifetime(bestStreak: 4))
                .contains(.streak5)
        )
    }

    /// Claiming the last shell ends the game whether or not you win it.
    func test_lastShell_unlocksEvenWhenYouLoseTheGame() {
        let out = AchievementRules.unlocked(
            after: game(won: false, endedByClaimingLastShell: true),
            lifetime: lifetime(wins: 0, bestStreak: 0)
        )
        XCTAssertTrue(out.contains(.lastShell))
    }

    func test_steal3_needsThreeStealsInOneGame() {
        XCTAssertTrue(
            AchievementRules.unlocked(after: game(steals: 3), lifetime: lifetime())
                .contains(.steal3)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(after: game(steals: 2), lifetime: lifetime())
                .contains(.steal3)
        )
    }

    // MARK: - Milestones

    func test_milestones_unlockAtTheirThresholds() {
        let out = AchievementRules.unlocked(
            after: game(),
            lifetime: lifetime(gamesPlayed: 50, wins: 10, bestStreak: 1)
        )
        XCTAssertTrue(out.contains(.played10))
        XCTAssertTrue(out.contains(.played50))
        XCTAssertFalse(out.contains(.played100))
        XCTAssertTrue(out.contains(.won10))
        XCTAssertFalse(out.contains(.won50))
    }

    // MARK: - Silly

    func test_bust3_countsBustsWithinOneGame() {
        XCTAssertTrue(
            AchievementRules.unlocked(after: game(busts: 3), lifetime: lifetime())
                .contains(.bust3)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(after: game(busts: 2), lifetime: lifetime())
                .contains(.bust3)
        )
    }

    func test_squeaker_needsAWinUnderTen() {
        XCTAssertTrue(
            AchievementRules.unlocked(after: game(score: 9), lifetime: lifetime())
                .contains(.squeaker)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(after: game(score: 10), lifetime: lifetime())
                .contains(.squeaker)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(
                after: game(won: false, score: 4),
                lifetime: lifetime(wins: 0, bestStreak: 0)
            ).contains(.squeaker)
        )
    }

    func test_bookends_needsBothEndsOfTheBeach() {
        XCTAssertTrue(
            AchievementRules.unlocked(
                after: game(claimedShells: [21, 29, 36]), lifetime: lifetime()
            ).contains(.bookends)
        )
        XCTAssertFalse(
            AchievementRules.unlocked(
                after: game(claimedShells: [21, 29]), lifetime: lifetime()
            ).contains(.bookends)
        )
    }

    // MARK: - Backfill

    /// Players upgrading from 1.0.1 have lifetime totals but no
    /// per-game history, so only the lifetime achievements can be
    /// granted retroactively.
    func test_backfill_grantsLifetimeOnly() {
        let out = AchievementRules.backfill(
            lifetime: lifetime(gamesPlayed: 120, wins: 60, bestStreak: 7)
        )
        XCTAssertTrue(out.contains(.played100))
        XCTAssertTrue(out.contains(.won50))
        XCTAssertTrue(out.contains(.streak5))
        XCTAssertTrue(out.contains(.firstWin))

        XCTAssertFalse(out.contains(.cleanWin))
        XCTAssertFalse(out.contains(.bookends))
        XCTAssertFalse(out.contains(.lastShell))
    }

    func test_backfill_grantsNothingForAFreshInstall() {
        let out = AchievementRules.backfill(
            lifetime: lifetime(gamesPlayed: 0, wins: 0, bestStreak: 0)
        )
        XCTAssertTrue(out.isEmpty)
    }

    /// Every achievement the backfill can return must be marked
    /// lifetime, and vice versa. Guards the two lists from drifting.
    func test_backfillMatchesTheLifetimeFlag() {
        let generous = AchievementRules.backfill(
            lifetime: lifetime(gamesPlayed: 1000, wins: 1000, bestStreak: 1000)
        )
        XCTAssertEqual(generous, Set(Achievement.allCases.filter(\.isLifetime)))
    }
}
