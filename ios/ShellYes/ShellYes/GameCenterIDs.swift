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
