import Foundation

/// What the player has done *this week*, and which week that is.
///
/// The weekly boards exist because three of the five all-time boards
/// have a hard ceiling — roughly 40 coins exist in a game of Shell Yes,
/// and a keep tops out at eight dice of coin — so their top eventually
/// fills with players tied at the maximum and the rank goes to whoever
/// arrived first. A board that restarts every week is winnable forever.
///
/// The score board takes the **sum of the week's best three games**, per
/// difficulty. Not the single best game, which would tell a player who
/// scored well on Monday that the rest of their week is worthless to the
/// board; and not the sum of every game, which pays for volume rather
/// than skill and makes the board a grind. Three is reachable in three
/// sessions, so a player who plays twice a week competes with one who
/// plays daily.
///
/// Streak and biggest keep stay single values — the best of the week.
/// Summing those would be nonsense.
struct WeeklyBests: Codable, Equatable {
    /// "2026-W37". The occurrence these numbers belong to. Any write
    /// carrying a different id wipes the rest of the struct first.
    var weekID: String
    /// Keyed by `Difficulty.rawValue`, highest first, at most
    /// `kept` entries. Stored as the individual scores rather than
    /// their sum so a fourth game can displace the weakest of three.
    var scoresByDifficulty: [String: [Int]]
    var bestStreak: Int
    var biggestKeep: Int

    /// Three. The number the board's whole shape rests on: high enough
    /// that one lucky game doesn't own the week, low enough that a
    /// casual player can fill it.
    static let kept = 3

    static func empty(weekID: String) -> WeeklyBests {
        WeeklyBests(
            weekID: weekID,
            scoresByDifficulty: [:],
            bestStreak: 0,
            biggestKeep: 0
        )
    }

    /// What goes to the weekly score board for one difficulty: the sum
    /// of however many of the three are filled. A player with one game
    /// this week submits that one game, and climbs as they add more.
    func score(for difficulty: String) -> Int {
        (scoresByDifficulty[difficulty] ?? []).reduce(0, +)
    }

    /// How many of the three are filled, for anywhere the app wants to
    /// say "two of three" rather than leave the sum unexplained.
    func gamesCounted(for difficulty: String) -> Int {
        (scoresByDifficulty[difficulty] ?? []).count
    }

    /// Files a finished game. Keeps the top `kept`, highest first.
    mutating func add(score: Int, difficulty: String) {
        var scores = scoresByDifficulty[difficulty] ?? []
        scores.append(score)
        scores.sort(by: >)
        scoresByDifficulty[difficulty] = Array(scores.prefix(Self.kept))
    }

    // MARK: - Which week it is

    /// ISO week in **UTC**, never the device's calendar.
    ///
    /// The boards themselves restart on a UTC schedule, so a device
    /// calendar would disagree with them for every player not on UTC,
    /// and a player who flies east would get two Mondays or lose one.
    /// The id a game is filed under has to be the one Apple is counting
    /// by, not the one the phone happens to be showing.
    static func weekID(for date: Date) -> String {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let parts = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let year = parts.yearForWeekOfYear ?? 0
        let week = parts.weekOfYear ?? 0
        return String(format: "%04d-W%02d", year, week)
    }

    /// This week's numbers, or a fresh empty week if `self` belongs to
    /// an older one.
    ///
    /// The roll-over is lazy, on write, deliberately: nothing has to run
    /// while the app is closed, and a player who skips a month simply
    /// finds a stale id waiting the next time they finish a game.
    func rolledOver(to date: Date) -> WeeklyBests {
        let current = Self.weekID(for: date)
        return weekID == current ? self : .empty(weekID: current)
    }
}
