import Foundation

/// Decides *whether* to offer a step up from Easy. The offer itself is
/// a card on the tally screen; this type owns only the policy and the
/// bookkeeping, the same split `ReviewPrompt` uses.
///
/// Fresh installs open on Easy, which is the right first game and the
/// wrong tenth. Nobody goes looking in Settings for a difficulty they
/// didn't choose, so the app has to raise it once — once being the
/// whole design. A nudge that comes back is nagging, so this fires a
/// single time per install, ever, whatever the answer.
///
/// The gate is "playing Easy comfortably":
///
/// - they are on Easy right now
/// - at least `minGames` games finished on Easy, so the offer follows
///   some evidence rather than a first-launch hunch
/// - at least one of them won, because telling someone who keeps
///   losing to make it harder is the opposite of help
///
/// One more condition lives at the call site, where the result of the
/// finished game is known: the card only appears on a tally the player
/// won.
@MainActor
final class DifficultyNudge {
    static let shared = DifficultyNudge()

    /// Ten games on Easy. The offer only makes sense to someone who
    /// has settled into the game rather than someone still learning
    /// it, and ten is comfortably past the point where a bust, a
    /// steal and a tally have all happened more than once. It also
    /// keeps the one shot we get for a player who is actually likely
    /// to say yes.
    static let minGames = 10

    private enum Key {
        static let didShow = "difficulty.nudgeShown"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Pure check — safe to call from a view body.
    func isEligible(
        difficulty: Difficulty,
        gamesOnEasy: Int,
        winsOnEasy: Int
    ) -> Bool {
        #if DEBUG
        // `-forceDifficultyNudge`, or the ladybug menu's toggle, skips
        // the history requirement and the spent-already flag, so the
        // card can be seen on a simulator that has never played ten
        // games and seen again on the next run. It still yields to the
        // rating ask, because that collision is the part worth seeing.
        if Self.isDebugForced { return true }
        #endif
        guard difficulty == .easy else { return false }
        guard !defaults.bool(forKey: Key.didShow) else { return false }
        guard gamesOnEasy >= Self.minGames, winsOnEasy >= 1 else { return false }
        return true
    }

    /// Convenience over `StatsStore`, so call sites don't each have to
    /// remember which dictionary the per-difficulty tallies live in.
    func isEligible(settings: SettingsStore, stats: StatsStore) -> Bool {
        isEligible(
            difficulty: settings.difficulty,
            gamesOnEasy: stats.gamesByDifficulty[Difficulty.easy.rawValue] ?? 0,
            winsOnEasy: stats.winsByDifficulty[Difficulty.easy.rawValue] ?? 0
        )
    }

    /// Spends the one offer. Called as the card appears, not as it is
    /// answered: a player who backgrounds the app mid-card has seen it,
    /// and showing it again would read as the app not listening.
    func markShown() {
        defaults.set(true, forKey: Key.didShow)
    }

    #if DEBUG
    /// Set by the ladybug menu to force the card onto the next tally.
    /// Lives alongside the launch argument rather than replacing it:
    /// the argument is for an automated run, this is for a thumb.
    static var debugForce = false

    /// Either route to the forced card, so call sites ask once.
    static var isDebugForced: Bool {
        debugForce || ScreenshotMode.forcesDifficultyNudge
    }

    /// Clears the flag so the card can be exercised again.
    func debugReset() {
        defaults.removeObject(forKey: Key.didShow)
    }
    #endif
}
