import Foundation

/// Decides *whether* an update has news worth stopping the player for,
/// and holds the words. The card itself is `WhatsNewCard`, over the
/// splash; this type owns only the policy and the bookkeeping, the same
/// split `ReviewPrompt` and `DifficultyNudge` use.
///
/// The policy is one line long: once per version, never on a fresh
/// install. A player who has just downloaded the game has no news —
/// all of it is new — so the first launch records the version and says
/// nothing.
@MainActor
final class WhatsNew {
    static let shared = WhatsNew()

    /// What one release has to say for itself. Short on purpose: this
    /// is a card somebody taps away, not a changelog they read.
    struct Note: Equatable {
        let version: String
        let title: String
        let lines: [String]
    }

    /// Keyed by `CFBundleShortVersionString`. A version absent from
    /// here shows nothing, which is the right answer for a release
    /// that only fixes things.
    ///
    /// These words live with the release, and they should not disagree
    /// with the What's New in `asc/release.json`. UK English, like
    /// every other string the player reads.
    static let notes: [Note] = [
        Note(
            version: "1.2",
            title: "new this wave",
            lines: [
                "Game Center! Leaderboards! Achievements! Omg!",
                "Five weekly leaderboards, reset each Monday!",
                "Your standing on the beach is now on your homescreen",
                "Global stats or among your friends",
            ]
        ),
        Note(
            version: "1.3",
            title: "new this wave",
            // These five are what build 7 shipped with, and this array
            // is kept matching the binary rather than tidied after the
            // fact — a card the player has already been shown is not
            // something the repo gets to disagree with.
            //
            // The App Store notes for 1.3 deliberately ran one line
            // shorter: they did not mention saving the card to Photos,
            // because that fix had never been verified on a device and
            // a store listing is a promise in a way an in-app card is
            // not. That caution was right. Tested on a device during
            // 1.4 and it did not work: the sheet offered Files and
            // Dropbox and no Photos at all. Two of these five lines,
            // this one and the Easy one, were untrue in build 7. 1.4
            // is where they both come true, which is why its card says
            // so plainly rather than quietly repeating them.
            lines: [
                "Easy is properly easy now. It wasn't. Sorry.",
                "Your rank turns up on the homescreen again",
                "Old games now count towards achievements",
                "Walking out of a game counts as a loss",
                "Save your crown card straight to Photos",
            ]
        ),
        Note(
            version: "1.4",
            title: "new this wave",
            lines: [
                "Tweaked difficulty balance even more!",
                "Saving your crown to your camera roll should actually work now. Cool.",
                "Automation! Other players can play without you. In settings.",
                "Big Kahuna also looks Kahunish in Dark Mode.",
            ]
        ),
        Note(
            version: "1.5",
            title: "new this wave",
            // 1.2's card already promised weekly boards and they have
            // never once worked: they were configured in App Store
            // Connect but never released, so Apple accepted every
            // score and dropped it. The first line owns that rather
            // than quietly repeating the claim, the same way 1.4's
            // card owned the Photos fix.
            lines: [
                "Weekly leaderboards. For real this time! I hope. Shakes fist at Apple.",
                "Every Monday, the beach is cleared!",
                "Your week is your best three games",
                "Cleaned up the homescreen",
            ]
        ),
    ]

    private enum Key {
        static let lastSeenVersion = "whatsNew.lastSeenVersion"
    }

    private let defaults: UserDefaults

    /// The running version. Injected so tests can ask what happens on
    /// a release that has no note without having to bump the app to
    /// get there.
    private let currentVersion: String

    init(
        defaults: UserDefaults = .standard,
        version: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    ) {
        self.defaults = defaults
        self.currentVersion = version
    }

    private var noteForCurrentVersion: Note? {
        Self.notes.first { $0.version == currentVersion }
    }

    /// This version's note regardless of whether it has been shown,
    /// for the Settings row that asks for it on purpose. Nil on a
    /// release with nothing to say, which is how the row knows to stay
    /// off the screen.
    var currentNote: Note? { noteForCurrentVersion }

    /// The note to show on this launch, or nil. Call it once, from the
    /// splash's task — it writes as well as reads, because the answer
    /// and the bookkeeping are the same decision and splitting them
    /// invites a second launch that shows the card again.
    ///
    /// `gamesPlayed` separates the two players who both arrive with no
    /// stored version: somebody who installed the game a minute ago,
    /// and somebody who has been playing since before this card
    /// existed. The second one is exactly who the news is for — it is
    /// the same retroactive reading of the lifetime counter that
    /// decides the How to Play row.
    func noteOnLaunch(gamesPlayed: Int) -> Note? {
        #if DEBUG
        if Self.debugForce { return noteForCurrentVersion }
        #endif
        let seen = defaults.string(forKey: Key.lastSeenVersion)
        // Whatever else happens, this launch has now seen this version.
        defaults.set(currentVersion, forKey: Key.lastSeenVersion)

        guard let note = noteForCurrentVersion else { return nil }
        if let seen {
            return seen == currentVersion ? nil : note
        }
        // No stored version: a fresh install stays quiet, a player with
        // a history gets the news.
        return gamesPlayed > 0 ? note : nil
    }

    #if DEBUG
    /// Set from the ladybug menu, so the card can be seen on a build
    /// that has already recorded its version.
    static var debugForce = false

    /// Clears the stored version so the next launch shows the card.
    func debugReset() {
        defaults.removeObject(forKey: Key.lastSeenVersion)
    }

    /// This version's note, whatever the bookkeeping says. The ladybug
    /// menu shows the card there and then rather than leaving somebody
    /// to quit and relaunch to see what they just reset.
    func debugNote() -> Note? { currentNote }
    #endif
}
