import Foundation

/// Remembers that a game was underway, so quitting out of a bad one
/// can't be free.
///
/// The hole this closes: `StatsStore.recordGameOver` only fires when
/// the engine reaches `.over`, and nothing about a game survived a
/// launch. So force-quitting a game you were losing left `winStreak`
/// untouched — and the best-streak boards, all-time and weekly, are
/// exactly what a preserved streak inflates. The weekly score board
/// sums a player's best three games, so quitting the bad ones kept
/// that pool artificially clean too.
///
/// A flag rather than a saved `State`. Resuming an interrupted game is
/// a feature and this is a bugfix; the flag is what makes quitting
/// cost something, which is the whole of the fix. If a Continue button
/// is ever built, it reads the same armed/disarmed signal and this type
/// grows a payload rather than being replaced.
///
/// Three keys rather than one, because the loss has to be filed against
/// the difficulty and pace it was played at — `recordAbandonedGame`
/// feeds the per-difficulty and per-pace breakdowns on the stats
/// screen, and billing a quit on Hard to Easy would quietly corrupt
/// both.
@MainActor
final class AbandonGuard {
    static let shared = AbandonGuard()

    private let defaults: UserDefaults
    private enum Key {
        static let armed = "game.inProgress"
        static let difficulty = "game.inProgress.difficulty"
        static let pace = "game.inProgress.pace"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The game that was underway when the app last went away, or nil
    /// if it ended properly — or if the player never touched it.
    var armedGame: (difficulty: String, pace: String)? {
        guard defaults.bool(forKey: Key.armed) else { return nil }
        // A flag without its context is still a real abandonment, so it
        // is reported rather than dropped. Normal is the same fallback
        // `Leaderboard.score(forDifficulty:)` uses for an unknown value.
        return (
            defaults.string(forKey: Key.difficulty) ?? Difficulty.normal.rawValue,
            defaults.string(forKey: Key.pace) ?? ""
        )
    }

    /// Called once a game has actually been played into — not when it
    /// is dealt. Opening a game and backing straight out is not a
    /// quit, and should not cost a streak.
    func arm(difficulty: String, pace: String) {
        defaults.set(true, forKey: Key.armed)
        defaults.set(difficulty, forKey: Key.difficulty)
        defaults.set(pace, forKey: Key.pace)
    }

    /// The game reached a proper end, or its loss has already been
    /// filed. Either way there is nothing left to charge for.
    func disarm() {
        defaults.removeObject(forKey: Key.armed)
        defaults.removeObject(forKey: Key.difficulty)
        defaults.removeObject(forKey: Key.pace)
    }
}
