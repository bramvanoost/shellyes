import Foundation

/// Game Center identifiers.
///
/// These strings are permanent. App Store Connect will not let a
/// leaderboard or achievement ID be reused or deleted once it exists,
/// so renaming a case here after release orphans the board. Change the
/// display name in App Store Connect instead — it is not in the app.

/// The five boards, grouped in App Store Connect as two sets plus one
/// loose board. Best score is per difficulty because a harder AI takes
/// more shells, so the same player scores lower on Hard.
enum Leaderboard: String, CaseIterable {
    case scoreEasy   = "com.fastronaut.game.shellyes.score.easy"
    case scoreNormal = "com.fastronaut.game.shellyes.score.normal"
    case scoreHard   = "com.fastronaut.game.shellyes.score.hard"
    case bestStreak  = "com.fastronaut.game.shellyes.streak.best"
    case biggestKeep = "com.fastronaut.game.shellyes.keep.biggest"

    /// Short key for telemetry, so an event carries `score.hard`
    /// rather than the full reverse-DNS id. Same trick as
    /// `Achievement.shortKey`.
    var shortKey: String {
        rawValue.replacingOccurrences(
            of: "com.fastronaut.game.shellyes.", with: ""
        )
    }

    /// Short human name for the board, used where the app shows the
    /// player's own standing on it. Deliberately lowercase and terse:
    /// it sits in the quiet line under the splash's Leaderboards
    /// button, not in a heading. The board's real title lives in App
    /// Store Connect and is Apple's to render inside their sheet.
    var displayName: String {
        switch self {
        case .scoreEasy:   return "easy"
        case .scoreNormal: return "normal"
        case .scoreHard:   return "hard"
        case .bestStreak:  return "streak"
        case .biggestKeep: return "biggest keep"
        }
    }

    /// What follows the rank on the splash line. Bare, no preposition:
    /// "on" and "for" read well in a sentence and cost a line break on
    /// a phone, and the line is not a sentence.
    var standingPhrase: String {
        switch self {
        case .scoreEasy:   return "easy, all time"
        case .scoreNormal: return "normal, all time"
        case .scoreHard:   return "hard, all time"
        case .bestStreak:  return "best streak, all time"
        case .biggestKeep: return "biggest keep, all time"
        }
    }

    /// The weekly twin of this board, so a caller that has one can
    /// reach the other without a second switch.
    var weekly: WeeklyLeaderboard {
        switch self {
        case .scoreEasy:   return .scoreEasy
        case .scoreNormal: return .scoreNormal
        case .scoreHard:   return .scoreHard
        case .bestStreak:  return .bestStreak
        case .biggestKeep: return .biggestKeep
        }
    }

    /// The score board matching a `Difficulty.rawValue`. Unknown values
    /// fall to Normal rather than crashing, so a future difficulty
    /// can't take the app down before its board exists.
    static func score(forDifficulty raw: String) -> Leaderboard {
        switch raw {
        case "easy": return .scoreEasy
        case "hard": return .scoreHard
        default: return .scoreNormal
        }
    }
}

/// The fourteen achievements, in the order they appear in Game Center.
enum Achievement: String, CaseIterable {
    // Skill — how you played.
    case firstWin   = "com.fastronaut.game.shellyes.first.win"
    case cleanWin   = "com.fastronaut.game.shellyes.clean.win"
    case hardWin    = "com.fastronaut.game.shellyes.hard.win"
    case streak5    = "com.fastronaut.game.shellyes.streak.5"
    case lastShell  = "com.fastronaut.game.shellyes.last.shell"
    case steal3     = "com.fastronaut.game.shellyes.steal.3"

    // Milestones — time served.
    case played10   = "com.fastronaut.game.shellyes.played.10"
    case played50   = "com.fastronaut.game.shellyes.played.50"
    case played100  = "com.fastronaut.game.shellyes.played.100"
    case won10      = "com.fastronaut.game.shellyes.won.10"
    case won50      = "com.fastronaut.game.shellyes.won.50"

    // Silly — on-brand nonsense.
    case bust3      = "com.fastronaut.game.shellyes.bust.3"
    case squeaker   = "com.fastronaut.game.shellyes.squeaker"
    case bookends   = "com.fastronaut.game.shellyes.bookends"

    /// Short key used for the exported badge filename, so the PNG a
    /// designer sees matches the row in App Store Connect.
    var shortKey: String {
        rawValue.replacingOccurrences(
            of: "com.fastronaut.game.shellyes.", with: ""
        )
    }

    /// True when the achievement can be earned from lifetime totals
    /// alone, which is what makes retroactive unlocking possible for
    /// players upgrading from 1.0.1.
    var isLifetime: Bool {
        switch self {
        case .firstWin, .streak5, .played10, .played50,
             .played100, .won10, .won50:
            return true
        case .cleanWin, .hardWin, .lastShell, .steal3,
             .bust3, .squeaker, .bookends:
            return false
        }
    }
}

/// The five recurring boards: the same five contests, restarted every
/// week. They are a separate enum rather than a `period` axis on
/// `Leaderboard` precisely so `Leaderboard.allCases` keeps meaning "the
/// all-time boards" — `loadStandings(for:)` walks whatever list it is
/// handed, and folding the two together would silently double every
/// caller's work.
///
/// Same warning as above: these ids are permanent once created in App
/// Store Connect.
enum WeeklyLeaderboard: String, CaseIterable {
    case scoreEasy   = "com.fastronaut.game.shellyes.weekly.score.easy"
    case scoreNormal = "com.fastronaut.game.shellyes.weekly.score.normal"
    case scoreHard   = "com.fastronaut.game.shellyes.weekly.score.hard"
    case bestStreak  = "com.fastronaut.game.shellyes.weekly.streak.best"
    case biggestKeep = "com.fastronaut.game.shellyes.weekly.keep.biggest"

    var shortKey: String {
        rawValue.replacingOccurrences(
            of: "com.fastronaut.game.shellyes.", with: ""
        )
    }

    var displayName: String {
        switch self {
        case .scoreEasy:   return "easy"
        case .scoreNormal: return "normal"
        case .scoreHard:   return "hard"
        case .bestStreak:  return "streak"
        case .biggestKeep: return "biggest keep"
        }
    }

    /// The all-time phrasing plus the window it applies to. "this week"
    /// is the whole reason these boards are worth showing, so it is in
    /// the line rather than left to a heading the player has to find.
    var standingPhrase: String {
        switch self {
        case .scoreEasy:   return "easy, this week"
        case .scoreNormal: return "normal, this week"
        case .scoreHard:   return "hard, this week"
        case .bestStreak:  return "best streak, this week"
        case .biggestKeep: return "biggest keep, this week"
        }
    }

    static func score(forDifficulty raw: String) -> WeeklyLeaderboard {
        Leaderboard.score(forDifficulty: raw).weekly
    }
}
