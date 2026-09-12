import Foundation
import Observation

/// Where the local player stands on one leaderboard.
///
/// No GameKit here on purpose: `GameCenter` does the fetching and hands
/// back these values, the same way it hands back `Leaderboard` and
/// `Achievement`. Everything above that file stays GameKit-free.
/// All-time, or this week. Two boards can now share everything but the
/// window they measure, so a standing has to say which one it is: the
/// id alone no longer identifies it, and the cache has to keep the two
/// apart across a launch.
enum StandingPeriod: String, Codable {
    case allTime
    case week
}

struct BoardStanding: Codable, Equatable, Identifiable {
    /// `Leaderboard.rawValue`. Stored as the raw string rather than the
    /// enum so a cached standing written by an older build can't fail
    /// to decode when a board is added.
    let boardID: String
    /// Defaults to `.allTime` when absent, so a cache written before
    /// the weekly boards existed still decodes.
    var period: StandingPeriod = .allTime
    /// 1-based position. 1 is Top Banana.
    let rank: Int
    /// How many players are on the board at all. A rank with no
    /// denominator says nothing: 12th of 14 and 12th of 3,000 are
    /// opposite pieces of news.
    let total: Int
    let score: Int

    var id: String { boardID }

    var board: Leaderboard? { Leaderboard(rawValue: boardID) }

    var weeklyBoard: WeeklyLeaderboard? { WeeklyLeaderboard(rawValue: boardID) }

    var isWeekly: Bool { period == .week }

    var boardName: String { board?.displayName ?? weeklyBoard?.displayName ?? "" }

    /// "on easy", "for best streak, this week". Empty for a board this
    /// build does not know, which is the same silence `boardName` keeps.
    var boardPhrase: String {
        board?.standingPhrase ?? weeklyBoard?.standingPhrase ?? ""
    }

    var isTop: Bool { rank == 1 }

    /// "1st", "12th", "23rd" — localized, because English's ordinal
    /// rules are not every language's.
    var ordinal: String {
        Self.ordinalFormatter.string(from: NSNumber(value: rank)) ?? "\(rank)"
    }

    /// The quiet line: "12th of 340". Unlabelled, because the line has
    /// to survive next to a board phrase on one row of a phone screen,
    /// and "Rank:" is the first thing worth spending to keep it there.
    var summary: String {
        "\(ordinal) of \(total)"
    }

    private static let ordinalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        return f
    }()
}

/// The player's standing across all five boards, cached so the splash
/// can show last-known instantly and correct itself a moment later.
///
/// This is the "Top Banana" feature in full: a rank is one
/// `loadEntries` call GameKit already answers for free, and holding
/// rank 1 is just that call coming back with a 1 in it. No server, no
/// new permission, nothing for App Privacy to change.
@MainActor
@Observable
final class StandingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    private enum Key {
        static let cached = "standings.cached"
    }

    private(set) var standings: [BoardStanding]

    /// Set while a refresh is in flight, so a view can avoid showing a
    /// stale rank as though it were fresh if it ever wants to.
    private(set) var isRefreshing = false

    /// Fires the `rank_loaded` event once per launch rather than once
    /// per trip back to the splash.
    @ObservationIgnored private var didTrack = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Key.cached),
           let decoded = try? JSONDecoder().decode([BoardStanding].self, from: data) {
            self.standings = decoded
        } else {
            self.standings = []
        }
        #if DEBUG
        // `-standings mid|top` paints a standing the simulator could
        // never earn, so the screenshot harness can capture both
        // states of the splash line.
        if let seeded = ScreenshotMode.standingsSeed {
            debugSeed(top: seeded == .top)
        }
        #endif
    }

    /// The standing worth showing: the best rank held, ties broken by
    /// the busier board, because 1st of 900 is a bigger claim than 1st
    /// of 12.
    var best: BoardStanding? {
        standings.min {
            $0.rank != $1.rank ? $0.rank < $1.rank : $0.total > $1.total
        }
    }

    /// This week's ranks — the winnable ones, and what the splash shows.
    var weekly: [BoardStanding] { standings.filter(\.isWeekly) }

    /// All-time ranks, kept out of the splash stack because they are
    /// mostly unwinnable once a ceilinged board fills up.
    var allTime: [BoardStanding] { standings.filter { !$0.isWeekly } }

    /// The one all-time standing worth promoting anyway. A held number
    /// one is the best thing about the account and would otherwise
    /// never be seen; anything below it is the seniority queue the
    /// weekly boards exist to escape.
    var allTimeCrown: BoardStanding? {
        allTime.filter(\.isTop).min { $0.total > $1.total }
    }

    /// True when the player is number one somewhere.
    var isTopBanana: Bool { best?.isTop == true }

    /// Every board they lead, for the day there is somewhere to list
    /// them.
    var topBoards: [BoardStanding] { standings.filter(\.isTop) }

    /// Pulls fresh ranks. Silent on failure: a rank is a nicety, and a
    /// player with no signal should see the last one we knew rather
    /// than an error.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Both windows, weekly first: the order they are shown in, and
        // the order that matters if only one of the two calls answers.
        async let week = GameCenter.shared.loadStandings(
            for: WeeklyLeaderboard.allCases.map(\.rawValue),
            period: .week
        )
        async let allTime = GameCenter.shared.loadStandings(
            for: Leaderboard.allCases.map(\.rawValue),
            period: .allTime
        )
        let fresh = await week + allTime
        // An empty answer means unsigned, offline, or a board that has
        // not seen this player yet — none of which is news that the
        // rank they had yesterday is wrong. Boards are only ever added,
        // so keeping the cache can't strand a standing that was removed.
        guard !fresh.isEmpty else { return }

        standings = fresh
        if let data = try? JSONEncoder().encode(fresh) {
            defaults.set(data, forKey: Key.cached)
        }
        track()
    }

    /// How many players reach a rank at all, and how many hold a number
    /// one. Part 3 of Top Banana — telling someone their lead is at
    /// risk — is only worth building if this says anyone leads.
    private func track() {
        guard !didTrack, let best else { return }
        didTrack = true
        Telemetry.shared.track("rank_loaded", props: [
            "best_rank": best.rank,
            "best_board": best.board?.shortKey ?? "unknown",
            "board_total": best.total,
            "boards_ranked": standings.count,
            "top_banana": isTopBanana,
        ])
    }

    #if DEBUG
    /// Puts a plausible set of ranks in place so the splash line and
    /// the crown can be eyeballed without a signed-in account and a
    /// populated board. `top` swaps the best rank for a number one.
    func debugSeed(top: Bool) {
        standings = [
            BoardStanding(
                boardID: WeeklyLeaderboard.scoreEasy.rawValue,
                period: .week,
                rank: top ? 1 : 4,
                total: 88,
                score: 96
            ),
            BoardStanding(
                boardID: WeeklyLeaderboard.bestStreak.rawValue,
                period: .week,
                rank: 11,
                total: 88,
                score: 3
            ),
            BoardStanding(
                boardID: Leaderboard.scoreEasy.rawValue,
                // All-time rank one only in the `top` seed: the god
                // tier line is the rarer of the two crowns and should
                // not be the default thing on screen.
                rank: top ? 1 : 12,
                total: 340,
                score: 34
            ),
            BoardStanding(
                boardID: Leaderboard.scoreHard.rawValue,
                rank: 3,
                total: 210,
                score: 29
            ),
            BoardStanding(
                boardID: Leaderboard.bestStreak.rawValue,
                rank: 58,
                total: 340,
                score: 4
            ),
        ]
    }

    /// Back to the state of a player who has never placed, so the
    /// splash can be seen without the line as well as with it. Clears
    /// the cache too, or the next launch would restore what this just
    /// removed.
    func debugClear() {
        standings = []
        defaults.removeObject(forKey: Key.cached)
    }
    #endif
}
