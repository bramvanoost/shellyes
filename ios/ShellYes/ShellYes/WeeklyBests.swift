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

    /// The week before this one, flattened to the five board totals.
    ///
    /// Roll-over used to drop the finished week on the floor, which
    /// made "better than last week" unanswerable: by the time the new
    /// week exists the old numbers are already gone. Optional so a
    /// record written before this field existed still decodes, and
    /// flattened rather than a nested `WeeklyBests` so it cannot
    /// recurse into a chain of every week ever played.
    var previous: PreviousWeek?

    /// One finished week, as the five numbers its boards saw.
    struct PreviousWeek: Codable, Equatable {
        var weekID: String
        /// Keyed by `Difficulty.rawValue`. The summed score, which is
        /// what the board took, not the individual games.
        var scoreByDifficulty: [String: Int]
        var bestStreak: Int
        var biggestKeep: Int
    }

    /// Three. The number the board's whole shape rests on: high enough
    /// that one lucky game doesn't own the week, low enough that a
    /// casual player can fill it.
    static let kept = 3

    static func empty(weekID: String, previous: PreviousWeek? = nil) -> WeeklyBests {
        WeeklyBests(
            weekID: weekID,
            scoresByDifficulty: [:],
            bestStreak: 0,
            biggestKeep: 0,
            previous: previous
        )
    }

    /// The difficulties with a weekly score board, in board order.
    static let scoredDifficulties = ["easy", "normal", "hard"]

    /// How many weekly boards exist: three score boards, best streak,
    /// biggest keep.
    static let boardCount = 5

    /// This week flattened the way a finished week is remembered.
    var asPreviousWeek: PreviousWeek {
        PreviousWeek(
            weekID: weekID,
            scoreByDifficulty: Dictionary(
                uniqueKeysWithValues: Self.scoredDifficulties.map { ($0, score(for: $0)) }
            ),
            bestStreak: bestStreak,
            biggestKeep: biggestKeep
        )
    }

    /// How many of the five boards have anything on them this week.
    /// A zero is "not posted": no board takes a score of nothing.
    var boardsPosted: Int {
        var n = Self.scoredDifficulties.filter { score(for: $0) > 0 }.count
        if bestStreak > 0 { n += 1 }
        if biggestKeep > 0 { n += 1 }
        return n
    }

    /// True when some difficulty has all three counted games filled.
    var hasFilledBestOfThree: Bool {
        Self.scoredDifficulties.contains { gamesCounted(for: $0) >= Self.kept }
    }

    /// True when some board beats the same board last week.
    ///
    /// Only boards the previous week actually posted on count. Coming
    /// back from nothing beats a zero arithmetically, but "better than
    /// last week" should mean a week was improved on, not that one
    /// existed at all, and every returning player would otherwise earn
    /// it on their first game back.
    var beatsPreviousWeek: Bool {
        guard let previous else { return false }
        for difficulty in Self.scoredDifficulties {
            let before = previous.scoreByDifficulty[difficulty] ?? 0
            if before > 0 && score(for: difficulty) > before { return true }
        }
        if previous.bestStreak > 0 && bestStreak > previous.bestStreak { return true }
        if previous.biggestKeep > 0 && biggestKeep > previous.biggestKeep { return true }
        return false
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

    /// The week an id names, in words: "8–14 Sep", or "29 Sep – 5 Oct"
    /// when it straddles two months.
    ///
    /// Only the share card needs this. A rank shown inside the app can
    /// say "this week" because the player is reading it this week; a
    /// card that leaves the phone is looked at later, by someone else,
    /// and "this week" would be a claim about whatever week they happen
    /// to open it in. The dates make it true forever.
    ///
    /// UTC, like `weekID` itself, because the boards restart on UTC and
    /// the label has to name the same seven days Apple counted.
    /// `DateIntervalFormatter` does the joining, so a locale that
    /// writes the month first gets "Sep 8 – 14" rather than a range
    /// assembled in English word order.
    static func weekLabel(for weekID: String) -> String? {
        let parts = weekID.components(separatedBy: "-W")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let week = Int(parts[1]) else { return nil }

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        var components = DateComponents()
        components.yearForWeekOfYear = year
        components.weekOfYear = week
        components.weekday = calendar.firstWeekday
        guard let start = calendar.date(from: components),
              let end = calendar.date(byAdding: .day, value: 6, to: start) else { return nil }

        let formatter = DateIntervalFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateTemplate = "dMMM"
        let days = formatter.string(from: start, to: end)

        // The year always rides along, and it goes on the end by hand.
        // This label exists to date a share card, and a card outlives
        // the year it was made in as surely as it outlives the week:
        // "7–13 Sep" read next September names the wrong seven days.
        // Asking the interval formatter for the year instead puts it
        // in front on some locales ("2026 Sep 7–13"), which reads as a
        // filename rather than a date.
        return "\(days), \(year)"
    }

    /// This week's numbers, or a fresh empty week if `self` belongs to
    /// an older one.
    ///
    /// The roll-over is lazy, on write, deliberately: nothing has to run
    /// while the app is closed, and a player who skips a month simply
    /// finds a stale id waiting the next time they finish a game.
    /// A week with nothing on it is not worth remembering, and
    /// remembering it would wipe the last week that had something.
    /// Somebody who skips a fortnight still gets to beat the last week
    /// they actually played.
    func rolledOver(to date: Date) -> WeeklyBests {
        let current = Self.weekID(for: date)
        guard weekID != current else { return self }
        return .empty(weekID: current, previous: boardsPosted > 0 ? asPreviousWeek : previous)
    }
}
