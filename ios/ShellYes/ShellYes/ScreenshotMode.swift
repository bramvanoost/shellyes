#if DEBUG
import Foundation

/// Launch-argument hooks used only by `ScreenshotTests` to put the board
/// into a known state for App Store captures.
///
/// The UI test can't drive the ladybug debug menu for this, because the
/// menu button itself would then sit in the corner of every screenshot.
/// So the same debug actions are reachable by launch argument, and
/// `-screenshotMode` hides the menu button for the duration of the run.
///
/// The whole file is `#if DEBUG`, so none of it exists in a Release build.
enum ScreenshotMode {
    /// Hides debug-only chrome so captures match what ships.
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }

    enum Seed: String {
        /// Rivals hold a few shells, so the board reads mid-game.
        case vaults
        /// Mid-game, plus the steal banner on screen.
        case steal
        /// Jump straight to the end-of-game counting ceremony.
        case tally
    }

    /// A leaderboard standing to draw on the splash. The simulator
    /// has no Game Center account, so the only way to capture the
    /// rank line — or the Top Banana crown — is to hand it one.
    enum StandingsSeed: String {
        /// Mid-table: the quiet "12th of 340" line.
        case mid
        /// Rank one, crown and all.
        case top
    }

    /// Forces the one-time difficulty nudge on the next tally. Its
    /// real gate needs ten finished games on Easy with a win among
    /// them, which is ten games a capture run would have to play.
    static var forcesDifficultyNudge: Bool {
        ProcessInfo.processInfo.arguments.contains("-forceDifficultyNudge")
    }

    static var standingsSeed: StandingsSeed? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-standings"), i + 1 < args.count else { return nil }
        return StandingsSeed(rawValue: args[i + 1])
    }

    static var seed: Seed? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-seed"), i + 1 < args.count else { return nil }
        return Seed(rawValue: args[i + 1])
    }
}
#endif
