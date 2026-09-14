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
                "Five weekly boards, reset every Monday.",
                "Your standing on the beach, on the home screen.",
                "Hold a number one and you can send the card to anyone.",
                "Achievements, showing everything you have already earned.",
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
    #endif
}
