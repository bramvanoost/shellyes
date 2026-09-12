import Foundation

/// Decides *whether* to ask for an App Store rating. The asking itself
/// happens in `CountingCeremony` via SwiftUI's `requestReview`, which
/// needs a view's environment; this type owns only the policy and the
/// bookkeeping so the rules live in one readable place.
///
/// The policy is deliberately stingy. iOS already caps the real dialog
/// at three appearances per year per user and silently swallows the
/// rest, so a prompt spent on a player who just lost is a prompt we
/// don't get back later. The gate is therefore "a player who is having
/// a good time and has had enough of them to have an opinion":
///
/// - they just won (checked at the call site, on their own win only)
/// - at least `minGames` finished games, so a first-launch fluke win
///   doesn't trigger it
/// - never asked for this app version, so a re-ask needs a new build
/// - and at least `minDaysBetweenAsks` since any previous ask
@MainActor
final class ReviewPrompt {
    static let shared = ReviewPrompt()

    /// Enough games that the player has seen a bust, a steal, and a
    /// real tally, not just the tutorial-shaped first round.
    static let minGames = 5
    /// Roughly a season. Below iOS's own 365/3 budget, so we never
    /// burn a slot re-asking someone who ignored us last month.
    static let minDaysBetweenAsks = 120

    private enum Key {
        static let askedVersion = "review.askedVersion"
        static let lastAskedAt  = "review.lastAskedAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }

    /// Pure check — safe to call from a view body. `justWon` is the
    /// caller's business: only the human's own outright win counts, a
    /// beach tie doesn't.
    func isEligible(gamesPlayed: Int, wins: Int, now: Date = Date()) -> Bool {
        guard gamesPlayed >= Self.minGames, wins >= 1 else { return false }
        // Asked already on this exact version — wait for a new build.
        if defaults.string(forKey: Key.askedVersion) == currentVersion { return false }
        if let last = defaults.object(forKey: Key.lastAskedAt) as? Date {
            let days = now.timeIntervalSince(last) / 86_400
            if days < Double(Self.minDaysBetweenAsks) { return false }
        }
        return true
    }

    /// Records that we spent an ask. Called right before the prompt so
    /// a player who backgrounds the app mid-dialog still counts as
    /// asked; re-asking them would be worse than missing one.
    func markAsked(now: Date = Date()) {
        defaults.set(currentVersion, forKey: Key.askedVersion)
        defaults.set(now, forKey: Key.lastAskedAt)
    }

    #if DEBUG
    /// Clears the bookkeeping so the prompt can be exercised again on
    /// the same build.
    func debugReset() {
        defaults.removeObject(forKey: Key.askedVersion)
        defaults.removeObject(forKey: Key.lastAskedAt)
    }
    #endif
}
