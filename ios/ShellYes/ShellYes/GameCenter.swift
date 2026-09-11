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
    }

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
                    return
                }
                if let error {
                    #if DEBUG
                    print("[GameCenter] auth failed: \(error.localizedDescription)")
                    #endif
                    self.isAuthenticated = false
                    return
                }
                self.pendingSignIn = nil
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
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

    // MARK: - Submitting

    func submit(_ value: Int, to board: Leaderboard) {
        guard isAuthenticated else { return }
        GKLeaderboard.submitScore(
            value,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [board.rawValue]
        ) { error in
            #if DEBUG
            if let error {
                print("[GameCenter] score submit failed: \(error.localizedDescription)")
            }
            #endif
        }
    }

    func report(_ achievements: Set<Achievement>) {
        guard isAuthenticated, !achievements.isEmpty else { return }
        let reports = achievements.map { achievement -> GKAchievement in
            let gk = GKAchievement(identifier: achievement.rawValue)
            gk.percentComplete = 100
            gk.showsCompletionBanner = true
            return gk
        }
        GKAchievement.report(reports) { error in
            #if DEBUG
            if let error {
                print("[GameCenter] achievement report failed: \(error.localizedDescription)")
            }
            #endif
        }
    }

    // MARK: - The two things the app actually calls

    /// Everything Game Center should hear about one finished game.
    func recordGameOver(summary: GameSummary, lifetime: LifetimeTotals, biggestKeep: Int) {
        guard isAuthenticated else { return }

        submit(summary.score, to: .score(forDifficulty: summary.difficulty))
        submit(lifetime.bestStreak, to: .bestStreak)
        submit(biggestKeep, to: .biggestKeep)

        report(AchievementRules.unlocked(after: summary, lifetime: lifetime))
    }

    /// One-time catch-up for players who already have a history when
    /// Game Center arrives. Posts their stored best runs to the right
    /// boards and grants the lifetime achievements.
    func backfillIfNeeded(from stats: StatsStore) {
        guard isAuthenticated, !defaults.bool(forKey: Key.didBackfill) else { return }

        for run in stats.bestRuns {
            submit(run.score, to: .score(forDifficulty: run.difficulty))
        }
        submit(stats.bestStreak, to: .bestStreak)
        submit(stats.biggestKeep, to: .biggestKeep)

        report(AchievementRules.backfill(lifetime: LifetimeTotals(
            gamesPlayed: stats.gamesPlayed,
            wins: stats.wins,
            bestStreak: stats.bestStreak
        )))

        defaults.set(true, forKey: Key.didBackfill)
    }
}
