import Foundation
import GameKit
import Observation
import UIKit

/// All GameKit I/O lives here, the way all Aptabase I/O lives in
/// `Telemetry`. Everything above this file deals in `Leaderboard` /
/// `Achievement` values and never imports GameKit.
///
/// Sign-in policy: authenticate silently at launch and say nothing if
/// it fails. Apple's sign-in sheet is only presented when the player
/// actually asks for Game Center by tapping Leaderboards or
/// Achievements in Settings. A game whose pitch is calm does not open
/// with a modal.
@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    private(set) var isAuthenticated = false

    /// Apple hands us a sign-in view controller when the player isn't
    /// signed in yet. We hold it rather than presenting it, and only
    /// show it if they ask for Game Center themselves.
    @ObservationIgnored private var pendingSignIn: UIViewController?

    /// Guards the one-time retroactive unlock for players upgrading
    /// from 1.0.1.
    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let didBackfill = "gamecenter.didBackfill"
        /// Telemetry bookkeeping only. GameKit treats a re-report of an
        /// earned achievement as a no-op, which is why the app keeps no
        /// state for it — but without this, every later win would
        /// re-fire `achievement_unlocked` for "First Shell" and the
        /// number would mean nothing.
        static let reported = "gamecenter.reportedAchievements"
    }

    /// Last authentication outcome reported, so GameKit calling its
    /// handler again (sign-out, account switch) doesn't inflate the
    /// count with repeats of the same answer.
    @ObservationIgnored private var lastAuthOutcome: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Authentication

    /// Called once from `ShellYesApp`. GameKit may call the handler
    /// more than once over the app's life (sign-out, account switch),
    /// so this keeps `isAuthenticated` current rather than resolving
    /// a single time.
    func authenticate() {
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            MainActor.assumeIsolated {
                if let viewController {
                    // Not signed in. Hold the sheet for later.
                    self.pendingSignIn = viewController
                    self.isAuthenticated = false
                    self.trackAuth("not_signed_in")
                    return
                }
                if let error {
                    #if DEBUG
                    print("[GameCenter] auth failed: \(error.localizedDescription)")
                    #endif
                    self.isAuthenticated = false
                    self.trackAuth("failed", error: error)
                    return
                }
                self.pendingSignIn = nil
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                self.trackAuth(self.isAuthenticated ? "authenticated" : "not_signed_in")
            }
        }
    }

    /// Presents Apple's sign-in sheet if we're holding one. Returns
    /// false when there's nothing to present, which means either the
    /// player is already signed in or GameKit hasn't offered a sheet.
    @discardableResult
    func presentSignInIfAvailable(from presenter: UIViewController) -> Bool {
        guard let pendingSignIn else { return false }
        presenter.present(pendingSignIn, animated: true)
        self.pendingSignIn = nil
        return true
    }

    /// Same, addressed to whatever is on screen. SwiftUI has no way to
    /// present a bare `UIViewController`, and this sheet is Apple's to
    /// present, not ours to wrap.
    @discardableResult
    func presentSignInFromKeyWindow() -> Bool {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard let root = scene?.keyWindow?.rootViewController else { return false }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return presentSignInIfAvailable(from: top)
    }

    /// How many players can actually reach the boards. If
    /// `not_signed_in` dominates, the leaderboard entries on the home
    /// screen are advertising a room most players can't enter.
    private func trackAuth(_ outcome: String, error: Error? = nil) {
        guard lastAuthOutcome != outcome else { return }
        lastAuthOutcome = outcome
        var props: [String: Any] = ["outcome": outcome]
        if let error = error as NSError? {
            props["error_code"] = error.code
        }
        Telemetry.shared.track("gamecenter_auth", props: props)
    }

    /// Submit and report failures were DEBUG prints, which means they
    /// were invisible in the only build that matters. The code is
    /// numeric and carries no player data.
    private func trackFailure(_ event: String, error: Error, extra: [String: Any] = [:]) {
        let ns = error as NSError
        Telemetry.shared.track(event, props: extra.merging([
            "error_code": ns.code,
            "error_domain": ns.domain,
        ]) { current, _ in current })
    }

    // MARK: - Submitting

    func submit(_ value: Int, to board: Leaderboard) {
        submit(value, toID: board.rawValue, shortKey: board.shortKey)
    }

    /// The weekly twin of the same call. Recurring boards take a score
    /// exactly like a classic one — Game Center decides which
    /// occurrence it lands in from the clock, not from anything the app
    /// sends.
    func submit(_ value: Int, to board: WeeklyLeaderboard) {
        submit(value, toID: board.rawValue, shortKey: board.shortKey)
    }

    private func submit(_ value: Int, toID id: String, shortKey: String) {
        guard isAuthenticated else { return }
        GKLeaderboard.submitScore(
            value,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [id]
        ) { [weak self] error in
            guard let error else { return }
            #if DEBUG
            print("[GameCenter] score submit failed: \(error.localizedDescription)")
            #endif
            Task { @MainActor in
                self?.trackFailure(
                    "gamecenter_submit_failed",
                    error: error,
                    extra: ["board": shortKey]
                )
            }
        }
    }

    func report(_ achievements: Set<Achievement>, source: String = "game") {
        guard isAuthenticated, !achievements.isEmpty else { return }
        let reports = achievements.map { achievement -> GKAchievement in
            let gk = GKAchievement(identifier: achievement.rawValue)
            gk.percentComplete = 100
            gk.showsCompletionBanner = true
            return gk
        }
        GKAchievement.report(reports) { [weak self] error in
            guard let error else { return }
            #if DEBUG
            print("[GameCenter] achievement report failed: \(error.localizedDescription)")
            #endif
            Task { @MainActor in
                self?.trackFailure(
                    "gamecenter_report_failed",
                    error: error,
                    extra: ["count": reports.count]
                )
            }
        }
        trackUnlocks(achievements, source: source)
    }

    /// Fires once per achievement per install. Re-reports are silent,
    /// so the event counts earnings rather than reports; a reinstall
    /// starts the bookkeeping over, which under-counts rather than
    /// inflates.
    private func trackUnlocks(_ achievements: Set<Achievement>, source: String) {
        var seen = Set(defaults.stringArray(forKey: Key.reported) ?? [])
        let fresh = achievements.filter { !seen.contains($0.rawValue) }
        guard !fresh.isEmpty else { return }

        for achievement in fresh.sorted(by: { $0.shortKey < $1.shortKey }) {
            Telemetry.shared.track("achievement_unlocked", props: [
                "achievement": achievement.shortKey,
                "source": source,
            ])
            seen.insert(achievement.rawValue)
        }
        defaults.set(Array(seen), forKey: Key.reported)
    }

    // MARK: - The two things the app actually calls

    /// Everything Game Center should hear about one finished game.
    func recordGameOver(
        summary: GameSummary,
        lifetime: LifetimeTotals,
        biggestKeep: Int,
        weekly: WeeklyBests
    ) {
        guard isAuthenticated else { return }

        submit(summary.score, to: Leaderboard.score(forDifficulty: summary.difficulty))
        submit(lifetime.bestStreak, to: Leaderboard.bestStreak)
        submit(biggestKeep, to: Leaderboard.biggestKeep)

        // The same game, told to the boards that restart every week.
        // The score here is a sum of up to three games, which is why it
        // arrives pre-computed rather than as `summary.score`.
        submit(
            weekly.score(for: summary.difficulty),
            to: WeeklyLeaderboard.score(forDifficulty: summary.difficulty)
        )
        submit(weekly.bestStreak, to: WeeklyLeaderboard.bestStreak)
        submit(weekly.biggestKeep, to: WeeklyLeaderboard.biggestKeep)

        report(AchievementRules.unlocked(after: summary, lifetime: lifetime))
    }

    /// One-time catch-up for players who already have a history when
    /// Game Center arrives. Posts their stored best runs to the right
    /// boards and grants the lifetime achievements.
    ///
    /// All-time boards only, deliberately. A best run from March is not
    /// something that happened this week, and posting it to a recurring
    /// board would hand a player a rank they did not earn in the
    /// occurrence it lands in.
    func backfillIfNeeded(from stats: StatsStore) {
        guard isAuthenticated, !defaults.bool(forKey: Key.didBackfill) else { return }

        for run in stats.bestRuns {
            submit(run.score, to: Leaderboard.score(forDifficulty: run.difficulty))
        }
        submit(stats.bestStreak, to: Leaderboard.bestStreak)
        submit(stats.biggestKeep, to: Leaderboard.biggestKeep)

        report(
            AchievementRules.backfill(lifetime: LifetimeTotals(
                gamesPlayed: stats.gamesPlayed,
                wins: stats.wins,
                bestStreak: stats.bestStreak
            )),
            source: "backfill"
        )

        defaults.set(true, forKey: Key.didBackfill)
    }
}
