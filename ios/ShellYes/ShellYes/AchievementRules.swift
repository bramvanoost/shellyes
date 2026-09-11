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

    /// Everything earnable from lifetime totals alone. Used on first
    /// sign-in so a player upgrading from 1.0.1 arrives with the
    /// achievements their history already deserves. The per-game ones
    /// can't be recovered — that history was never recorded.
    static func backfill(lifetime: LifetimeTotals) -> Set<Achievement> {
        var out: Set<Achievement> = []

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
