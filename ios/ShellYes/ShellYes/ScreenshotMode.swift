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

    static var seed: Seed? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-seed"), i + 1 < args.count else { return nil }
        return Seed(rawValue: args[i + 1])
    }
}
#endif
