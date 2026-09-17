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
        /// Put a bot's outcome banner on screen, which a real game
        /// only reaches by playing a turn out. The one way to look at
        /// the auto-continue countdown without playing.
        case aiBanner
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

    /// Which share card to open over the splash. Pair it with
    /// `-standings top`, the only state that has a card to show, and
    /// `-playerName` so the card carries one.
    enum ShareCardSeed: String {
        /// The weekly crown: crown mark, "Top Banana".
        case weekly
        /// The all-time one: palms, "Big Kahuna".
        case allTime
    }

    /// Hands the board page stand-in rows. The simulator has no Game
    /// Center account, so without this the board only ever captures as
    /// its empty state.
    static var seedsBoardRows: Bool {
        ProcessInfo.processInfo.arguments.contains("-boardCard")
    }

    /// Opens the share sheet already scrolled past the board to the
    /// card, which is otherwise only reachable by a swipe a capture
    /// run cannot perform.
    static var startsOnShareCard: Bool {
        ProcessInfo.processInfo.arguments.contains("-sharePage")
    }

    /// Forces the What's New card for the running version.
    ///
    /// The card is normally once-per-version and writes as it reads, so
    /// capturing it otherwise means faking an upgrade in UserDefaults —
    /// which loses to `cfprefsd` caching about as often as it works.
    /// Release copy is worth being able to look at before it ships.
    static var forcesWhatsNew: Bool {
        ProcessInfo.processInfo.arguments.contains("-whatsNew")
    }

    static var shareCardSeed: ShareCardSeed? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-shareCard"), i + 1 < args.count else { return nil }
        return ShareCardSeed(rawValue: args[i + 1])
    }

    /// A name for the greeting and the share card. The simulator has
    /// no Game Center account to supply one, and a card with a blank
    /// where the name goes is not the card players will make.
    static var playerName: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-playerName"), i + 1 < args.count else { return nil }
        return args[i + 1]
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
