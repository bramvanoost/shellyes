import Foundation

/// What one finished game looked like, reduced to the facts an
/// achievement can turn on. Built in `GameView` at game over.
struct GameSummary: Equatable {
    let won: Bool
    let score: Int
    /// `Difficulty.rawValue`, kept as a string so a case rename can't
    /// silently change which achievements fire.
    let difficulty: String
    let busts: Int
    let steals: Int
    /// Every shell number the human claimed this game.
    let claimedShells: Set<Int>
    /// True when the human took the final shell off the sand, which is
    /// what ends the game. Independent of winning it.
    let endedByClaimingLastShell: Bool
}

/// What this week looks like locally, reduced to the facts a badge
/// turns on. Lifted off `WeeklyBests`, which is the only thing that
/// knows them.
struct WeeklyProgress: Equatable {
    /// How many of the five weekly boards have anything on them.
    let boardsPosted: Int
    /// Some difficulty has all three counted games filled.
    let filledBestOfThree: Bool
    /// Some board beats the same board last week.
    let beatLastWeek: Bool
}

/// Where the player stands right now. Lifted off `StandingsStore`,
/// which already loads every rank on launch, so none of this costs a
/// new GameKit call.
struct RankProgress: Equatable {
    /// Weekly boards currently held at number one.
    let weeklyTops: Int
    /// Any all-time board held at number one.
    let holdsAllTimeTop: Bool
}

/// Lifetime totals, lifted off `StatsStore`.
struct LifetimeTotals: Equatable {
    let gamesPlayed: Int
    let wins: Int
    let bestStreak: Int
}

/// The pure half of Game Center. No GameKit import, no I/O, no
/// `Date.now` — the same discipline the engine keeps, for the same
/// reason: every rule here is testable on its own.
///
/// Re-reporting an already-earned achievement is harmless; Game Center
/// ignores a percentage that doesn't increase. So these functions
/// return everything currently *satisfied*, not everything newly
/// earned, and no local "already unlocked" bookkeeping is needed.
enum AchievementRules {

    /// Everything satisfied after a finished game.
    static func unlocked(
        after game: GameSummary,
        lifetime: LifetimeTotals
    ) -> Set<Achievement> {
        var out = backfill(lifetime: lifetime)

        if game.won && game.busts == 0 { out.insert(.cleanWin) }
        if game.won && game.difficulty == "hard" { out.insert(.hardWin) }
        if game.endedByClaimingLastShell { out.insert(.lastShell) }
        if game.steals >= 3 { out.insert(.steal3) }

        if game.busts >= 3 { out.insert(.bust3) }
        if game.won && game.score < 10 { out.insert(.squeaker) }
        if game.claimedShells.contains(21) && game.claimedShells.contains(36) {
            out.insert(.bookends)
        }

        return out
    }

    /// Everything the week's own numbers satisfy.
    ///
    /// Separate from `unlocked(after:lifetime:)` because these turn on
    /// the state of a seven-day window rather than on the game that
    /// just ended.
    static func unlocked(weekly: WeeklyProgress) -> Set<Achievement> {
        var out: Set<Achievement> = []
        if weekly.boardsPosted >= WeeklyBests.boardCount { out.insert(.weekSweep) }
        if weekly.filledBestOfThree { out.insert(.weekBestOfThree) }
        if weekly.beatLastWeek { out.insert(.weekBetter) }
        return out
    }

    /// Everything a held rank satisfies.
    ///
    /// Split from the week's own three because the two arrive at
    /// different moments and from different places. A game being filed
    /// changes `WeeklyBests` and nothing about a rank; ranks coming
    /// back from GameKit change no local number at all, and happen on
    /// launches where no game is played.
    static func unlocked(ranks: RankProgress) -> Set<Achievement> {
        var out: Set<Achievement> = []
        if ranks.weeklyTops >= 1 { out.insert(.topBanana) }
        if ranks.weeklyTops >= WeeklyBests.boardCount { out.insert(.wholeBeach) }
        if ranks.holdsAllTimeTop { out.insert(.bigKahuna) }
        return out
    }

    /// Everything earnable from a stored history. Used on first sign-in
    /// so a player upgrading arrives with the achievements they already
    /// deserve.
    ///
    /// `bestRuns` is optional because the lifetime half of this is also
    /// the floor of `unlocked(after:lifetime:)`, which is scoring a
    /// single game and has no business reading the archive.
    ///
    /// Most per-game achievements still can't be recovered: `cleanWin`,
    /// `lastShell`, `steal3`, `bust3` and `bookends` all turn on facts
    /// about a game that were never written down. `busts` and `steals`
    /// are stored as lifetime totals only, so "three in one game" is not
    /// answerable from them — and guessing would hand out an
    /// achievement nobody earned, which is worse than a locked one.
    static func backfill(
        lifetime: LifetimeTotals,
        bestRuns: [ScoreRecord] = []
    ) -> Set<Achievement> {
        var out: Set<Achievement> = []

        // The two that survive in `bestRuns`, which keeps each run's
        // difficulty, score and whether it was won.
        if bestRuns.contains(where: { $0.won && $0.difficulty == "hard" }) {
            out.insert(.hardWin)
        }
        if bestRuns.contains(where: { $0.won && $0.score < 10 }) {
            out.insert(.squeaker)
        }

        if lifetime.wins >= 1 { out.insert(.firstWin) }
        if lifetime.bestStreak >= 5 { out.insert(.streak5) }

        if lifetime.gamesPlayed >= 10 { out.insert(.played10) }
        if lifetime.gamesPlayed >= 50 { out.insert(.played50) }
        if lifetime.gamesPlayed >= 100 { out.insert(.played100) }

        if lifetime.wins >= 10 { out.insert(.won10) }
        if lifetime.wins >= 50 { out.insert(.won50) }

        return out
    }
}
