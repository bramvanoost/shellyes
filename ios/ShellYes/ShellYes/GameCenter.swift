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
extension BoardScope {
    /// The GameKit term for the same idea. The mapping lives here so
    /// `BoardScope` itself stays importable by views that have no
    /// business knowing GameKit exists.
    var playerScope: GKLeaderboard.PlayerScope {
        switch self {
        case .everyone: return .global
        case .friends: return .friendsOnly
        }
    }
}

@MainActor
@Observable
final class GameCenter {
    static let shared = GameCenter()

    private(set) var isAuthenticated = false

    /// What to call the player, or nil when we have no right to call
    /// them anything. `displayName` rather than `alias` because Apple
    /// decides there what is safe to show — the real name only when
    /// the player has allowed it, the gamertag otherwise.
    ///
    /// Cached, so the splash can greet on its first frame instead of
    /// a beat later when GameKit answers. A name that turns out to be
    /// stale is corrected within the second; a greeting that pops in
    /// after the screen has settled is the thing worth avoiding.
    private(set) var playerName: String?

    /// The part of `playerName` a greeting uses: everything before the
    /// first space. "Bram van Oost" greets as Bram, and a one-word
    /// gamertag greets as itself.
    var playerFirstName: String? {
        guard let first = playerName?.split(separator: " ").first else { return nil }
        let trimmed = String(first)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Apple hands us a sign-in view controller when the player isn't
    /// signed in yet. We hold it rather than presenting it, and only
    /// show it if they ask for Game Center themselves.
    @ObservationIgnored private var pendingSignIn: UIViewController?

    /// Guards the one-time retroactive unlock for players upgrading
    /// from 1.0.1.
    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        /// Version 1's guard. Still read so a player who has already
        /// had it is not walked through the score submissions twice,
        /// but it no longer gates the run on its own — see `didBackfillV2`.
        static let didBackfill = "gamecenter.didBackfill"
        /// Version 2's guard, added when the backfill learned to grant
        /// `hardWin` and `squeaker` off `bestRuns`.
        ///
        /// A second key rather than a cleared first one: everyone who
        /// installed 1.2 already has `didBackfill` set, so reusing it
        /// would mean the two new achievements never reached a single
        /// existing player — the exact group the backfill exists for.
        /// Each new version of the rules needs its own key for the same
        /// reason.
        static let didBackfillV2 = "gamecenter.didBackfill.v2"
        /// Telemetry bookkeeping only. GameKit treats a re-report of an
        /// earned achievement as a no-op, which is why the app keeps no
        /// state for it — but without this, every later win would
        /// re-fire `achievement_unlocked` for "First Shell" and the
        /// number would mean nothing.
        static let reported = "gamecenter.reportedAchievements"
        static let playerName = "gamecenter.playerName"
    }

    /// Last authentication outcome reported, so GameKit calling its
    /// handler again (sign-out, account switch) doesn't inflate the
    /// count with repeats of the same answer.
    @ObservationIgnored private var lastAuthOutcome: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.playerName = defaults.string(forKey: Key.playerName)
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
                    // Signed out is the one case that clears the name:
                    // greeting the last player by name on an account
                    // that has since left is worse than not greeting.
                    self.rememberPlayerName(nil)
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
                // A failed auth leaves the cached name alone — no
                // signal, no news about who they are. Only a confirmed
                // sign-in rewrites it.
                if self.isAuthenticated {
                    self.rememberPlayerName(GKLocalPlayer.local.displayName)
                }
                self.trackAuth(self.isAuthenticated ? "authenticated" : "not_signed_in")
            }
        }
    }

    /// Stores the name for this launch and the next. Never leaves the
    /// device: it is not a telemetry property and never will be.
    private func rememberPlayerName(_ name: String?) {
        let cleaned = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = (cleaned?.isEmpty == false) ? cleaned : nil
        playerName = value
        if let value {
            defaults.set(value, forKey: Key.playerName)
        } else {
            defaults.removeObject(forKey: Key.playerName)
        }
    }

    #if DEBUG
    /// A name the simulator has no account to supply. Goes through the
    /// same store as the real one, so the greeting is exercised by the
    /// code that will run in a player's hand.
    func debugSetPlayerName(_ name: String?) {
        rememberPlayerName(name)
    }
    #endif

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

    /// `landed` reports whether GameKit took the score. Live game
    /// submissions ignore it — a lost score there is replaced by the
    /// next game — but the one-time backfill has no second chance and
    /// must know, see `backfillIfNeeded`.
    func submit(
        _ value: Int,
        to board: Leaderboard,
        landed: (@MainActor (Bool) -> Void)? = nil
    ) {
        submit(value, toID: board.rawValue, shortKey: board.shortKey, landed: landed)
    }

    /// The weekly twin of the same call. Recurring boards take a score
    /// exactly like a classic one — Game Center decides which
    /// occurrence it lands in from the clock, not from anything the app
    /// sends.
    func submit(_ value: Int, to board: WeeklyLeaderboard) {
        submit(value, toID: board.rawValue, shortKey: board.shortKey, landed: nil)
    }

    private func submit(
        _ value: Int,
        toID id: String,
        shortKey: String,
        landed: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard isAuthenticated else {
            // Not an error GameKit ever hears about, so nothing else
            // reports it. A caller that needs to know gets a false.
            landed?(false)
            return
        }
        GKLeaderboard.submitScore(
            value,
            context: 0,
            player: GKLocalPlayer.local,
            leaderboardIDs: [id]
        ) { [weak self] error in
            guard let error else {
                if let landed {
                    Task { @MainActor in landed(true) }
                }
                return
            }
            #if DEBUG
            print("[GameCenter] score submit failed: \(error.localizedDescription)")
            #endif
            Task { @MainActor in
                self?.trackFailure(
                    "gamecenter_submit_failed",
                    error: error,
                    extra: ["board": shortKey]
                )
                landed?(false)
            }
        }
    }

    // MARK: - Reading back

    /// The local player's rank on every board they appear on.
    ///
    /// One `loadEntries` call per board, asked for the shortest
    /// possible range: the entries themselves are thrown away and only
    /// the local player's row and the board's total count are kept.
    /// Boards are walked in `Leaderboard.allCases` order and asked one
    /// at a time — five serial round trips on a screen that is already
    /// idle, in exchange for a result whose order doesn't shuffle
    /// between launches.
    ///
    /// Returns empty rather than throwing. A missing rank is a missing
    /// nicety; it is never worth putting an error in front of someone
    /// who opened a beach game.
    func loadStandings(
        for boardIDs: [String] = Leaderboard.allCases.map(\.rawValue),
        period: StandingPeriod = .allTime
    ) async -> [BoardStanding] {
        guard isAuthenticated, !boardIDs.isEmpty else { return [] }
        let order = boardIDs
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: order)
            var found: [BoardStanding] = []
            for board in boards {
                // Range is 1-based and must be non-empty, so ask for
                // the single top entry. `loadEntries` returns the local
                // player's own row separately, whatever their position.
                // The top entry used to be thrown away; it is kept now
                // because its score is the only way to tell a tie at
                // the top from a genuine second place — Game Center
                // ranks a tie by who posted first.
                let (localEntry, topEntries, total) = try await board.loadEntries(
                    for: .global,
                    timeScope: .allTime,
                    range: NSRange(location: 1, length: 1)
                )
                // Rank 0 is Game Center's answer for a board the
                // player has no score on. It is not a place, and a
                // weekly board hands one back all week until a game
                // lands, so it is dropped here rather than cached and
                // filtered on the way out.
                guard let localEntry, localEntry.rank >= 1 else { continue }
                found.append(
                    BoardStanding(
                        boardID: board.baseLeaderboardID,
                        period: period,
                        rank: localEntry.rank,
                        total: total,
                        score: localEntry.score,
                        topScore: topEntries.first?.score
                    )
                )
            }
            return found.sorted {
                (order.firstIndex(of: $0.boardID) ?? order.count)
                    < (order.firstIndex(of: $1.boardID) ?? order.count)
            }
        } catch {
            #if DEBUG
            print("[GameCenter] rank load failed: \(error.localizedDescription)")
            #endif
            trackFailure("gamecenter_rank_failed", error: error)
            return []
        }
    }

    /// The top of one board, plus the local player's own row.
    ///
    /// `loadStandings` asks the same call for a range of one and keeps
    /// only the rank; this one keeps the entries, because the share
    /// sheet draws the board itself rather than handing the player to
    /// Apple's screen. Eight rows is what fits on the card at a
    /// readable size on the smallest phone we support.
    ///
    /// A local player outside the top eight is appended rather than
    /// dropped: their row is the only reason this board is worth
    /// showing them at all, and `loadEntries` hands it back separately
    /// exactly so it can be.
    ///
    /// Returns empty rather than throwing, like every other read here.
    /// The board page has an empty state and it is a better outcome
    /// than an error in front of somebody who just won something.
    /// `scope` picks the crowd: everybody, or the player's Game Center
    /// friends. The friends read is deliberately ungated — GameKit has
    /// required `loadFriendsAuthorizationStatus` for friend *identity*
    /// since iOS 14.5, but whether `.friendsOnly` needs that grant to
    /// return rows is not documented either way, and asking for the
    /// grant is a real cost to spend on a guess. So it is asked for
    /// without one, and `board_scope_viewed` in the dashboard answers
    /// the question with real accounts. If it comes back empty for
    /// everybody, the grant is the next thing to try.
    func loadBoardRows(
        for boardID: String,
        top: Int = 8,
        scope: BoardScope = .everyone
    ) async -> BoardPage {
        guard isAuthenticated, !boardID.isEmpty else { return .empty }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [boardID])
            guard let board = boards.first else { return .empty }
            let (localEntry, entries, total) = try await board.loadEntries(
                for: scope.playerScope,
                timeScope: .allTime,
                range: NSRange(location: 1, length: top)
            )
            let localID = GKLocalPlayer.local.gamePlayerID
            var rows = entries.map { entry in
                BoardRow(
                    rank: entry.rank,
                    name: entry.player.displayName,
                    score: entry.score,
                    isMe: entry.player.gamePlayerID == localID
                )
            }
            if let localEntry, !rows.contains(where: { $0.isMe }) {
                rows.append(
                    BoardRow(
                        rank: localEntry.rank,
                        name: localEntry.player.displayName,
                        score: localEntry.score,
                        isMe: true
                    )
                )
            }
            return BoardPage(rows: rows.sorted { $0.rank < $1.rank }, total: total)
        } catch {
            #if DEBUG
            print("[GameCenter] board load failed: \(error.localizedDescription)")
            #endif
            trackFailure("gamecenter_board_failed", error: error)
            return .empty
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
            if let error {
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
                return
            }
            Task { @MainActor in
                self?.trackUnlocks(achievements, source: source)
            }
        }
    }

    /// Fires once per achievement per install, and only once Game
    /// Center has accepted the report.
    ///
    /// Until 1.2 this ran alongside `report` rather than inside its
    /// completion, so the event recorded what the app believed rather
    /// than what Game Center stored — which is why the 1.1 numbers are
    /// unreadable (the achievements were never live, so every report
    /// had nothing to land on). Hanging it off the success path makes
    /// `achievement_unlocked` mean exactly one thing: Game Center took
    /// it. Failures stay visible through `gamecenter_report_failed`.
    ///
    /// A failed report also leaves the bookkeeping untouched, so the
    /// achievement fires properly whenever it does land. Re-reports are
    /// silent to GameKit, and a reinstall starts the bookkeeping over,
    /// so this under-counts rather than inflates.
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

        // 1.2 owes every existing player their whole history at once,
        // so a backfill can fire fourteen of the events above in a
        // burst. This is the one line to read on the dashboard: how
        // much each catch-up actually caught. A zero-count backfill
        // never reaches here, which is what you want — the interesting
        // population is players who were owed something.
        if source == "backfill" {
            Telemetry.shared.track("achievement_backfill", props: [
                "count": fresh.count,
                "reported": achievements.count,
            ])
        }
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
        let scoresDone = defaults.bool(forKey: Key.didBackfill)
        let achievementsDone = defaults.bool(forKey: Key.didBackfillV2)
        // Both halves have to be done before this can stop running.
        // `didBackfillV2` used to gate the whole function, which meant a
        // score backfill that failed could never be retried even though
        // its own flag was still unset.
        guard isAuthenticated, !(scoresDone && achievementsDone) else { return }

        // Scores only on the first run. A player who already had the 1.2
        // backfill has these on the boards, and every board here takes
        // the best value rather than the latest, so re-submitting would
        // be noise rather than harm — but it is still five round trips
        // to tell Game Center something it already knows.
        if !scoresDone {
            var submissions = stats.bestRuns.map {
                (Leaderboard.score(forDifficulty: $0.difficulty), $0.score)
            }
            submissions.append((.bestStreak, stats.bestStreak))
            submissions.append((.biggestKeep, stats.biggestKeep))

            // The flag is written when the boards answer, never when the
            // submissions are merely dispatched. `submit` is
            // fire-and-forget, and writing it early is what marked
            // thirteen failed backfills as done across four players —
            // every one of them refused at the same second auth landed.
            // See `BackfillTally`.
            var tally = BackfillTally(expected: submissions.count)
            for (board, value) in submissions {
                submit(value, to: board) { [weak self] ok in
                    guard let self else { return }
                    tally.record(success: ok)
                    guard tally.isComplete else { return }
                    if tally.mayMarkDone {
                        self.defaults.set(true, forKey: Key.didBackfill)
                    } else {
                        // Left unset on purpose: the next launch runs the
                        // whole set again. Safe because every board is
                        // BEST_SCORE, so re-sending a score it already
                        // holds changes nothing.
                        // No GameKit error to attach: the individual
                        // refusals already went out as
                        // `gamecenter_submit_failed`. This one says the
                        // backfill as a whole is being retried.
                        Telemetry.shared.track(
                            "gamecenter_backfill_incomplete",
                            props: ["failed": tally.failed, "expected": tally.expected]
                        )
                    }
                }
            }
        }

        // Achievements run every time the rules learn something new.
        // Re-reporting an earned one is a no-op to GameKit, and
        // `trackUnlocks` keeps the telemetry from double-counting.
        report(
            AchievementRules.backfill(
                lifetime: LifetimeTotals(
                    gamesPlayed: stats.gamesPlayed,
                    wins: stats.wins,
                    bestStreak: stats.bestStreak
                ),
                bestRuns: stats.bestRuns
            ),
            source: "backfill"
        )

        defaults.set(true, forKey: Key.didBackfillV2)
    }
}
