import XCTest
@testable import ShellYes

/// `WhatsNew` decides whether an update has news worth a card. Every
/// test runs against its own `UserDefaults` suite and its own version
/// string, so none of them can see the real install's bookkeeping or
/// go stale the next time the app is bumped.
@MainActor
final class WhatsNewTests: XCTestCase {

    private var suiteName = ""
    private var defaults = UserDefaults.standard

    /// A version that has a note. Reading it off the table rather than
    /// hardcoding "1.2" keeps these tests alive past the next release.
    private var versionWithNote: String { WhatsNew.notes[0].version }

    override func setUp() {
        super.setUp()
        suiteName = "whatsnew.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func subject(version: String) -> WhatsNew {
        WhatsNew(defaults: defaults, version: version)
    }

    func test_freshInstall_showsNothing() {
        let note = subject(version: versionWithNote).noteOnLaunch(gamesPlayed: 0)

        // All of it is new to a new player; none of it is news.
        XCTAssertNil(note)
    }

    func test_freshInstall_recordsTheVersionSoItNeverCatchesUpLater() {
        let whatsNew = subject(version: versionWithNote)

        XCTAssertNil(whatsNew.noteOnLaunch(gamesPlayed: 0))
        // Same install, later, after some games: still nothing, because
        // the first launch already wrote the version down.
        XCTAssertNil(whatsNew.noteOnLaunch(gamesPlayed: 12))
    }

    func test_playerWithAHistoryAndNoStoredVersion_getsTheNews() {
        let note = subject(version: versionWithNote).noteOnLaunch(gamesPlayed: 4)

        XCTAssertEqual(note?.version, versionWithNote)
    }

    func test_updateFromAnEarlierVersion_showsTheNoteOnce() {
        defaults.set("1.1", forKey: "whatsNew.lastSeenVersion")
        let whatsNew = subject(version: versionWithNote)

        XCTAssertEqual(whatsNew.noteOnLaunch(gamesPlayed: 30)?.version, versionWithNote)
        XCTAssertNil(whatsNew.noteOnLaunch(gamesPlayed: 30))
    }

    func test_sameVersionAgain_showsNothing() {
        defaults.set(versionWithNote, forKey: "whatsNew.lastSeenVersion")

        XCTAssertNil(subject(version: versionWithNote).noteOnLaunch(gamesPlayed: 30))
    }

    func test_versionWithoutANote_showsNothingAndStillRecordsItself() {
        defaults.set("1.1", forKey: "whatsNew.lastSeenVersion")
        let quiet = subject(version: "99.0")

        XCTAssertNil(quiet.noteOnLaunch(gamesPlayed: 30))
        XCTAssertEqual(defaults.string(forKey: "whatsNew.lastSeenVersion"), "99.0")
    }

    func test_everyNoteHasWordsToShow() {
        for note in WhatsNew.notes {
            XCTAssertFalse(note.title.isEmpty, "\(note.version) has no title")
            XCTAssertFalse(note.lines.isEmpty, "\(note.version) has no lines")
            XCTAssertFalse(
                note.lines.contains(where: \.isEmpty),
                "\(note.version) has an empty line"
            )
            if let intro = note.intro {
                XCTAssertFalse(
                    intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "\(note.version) has an intro with nothing in it"
                )
            }
        }
    }

    /// The mistake this exists to stop happening again: 1.5 build 12 was
    /// uploaded with the version bumped and no matching note, and a
    /// version absent from `notes` shows no card at all. Nothing failed,
    /// nothing warned, and the build had to be superseded.
    ///
    /// Reads the bundle rather than a literal, so bumping
    /// `MARKETING_VERSION` and forgetting the words fails here instead
    /// of in App Store Connect.
    func test_theShippingVersionHasANote() {
        let shipping = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        // The test bundle carries its own version, so fall back to the
        // app's when that is what turns up.
        let version = shipping ?? ""
        guard !version.isEmpty, version != "1.0" else {
            return XCTFail("could not read a version to check")
        }

        XCTAssertTrue(
            WhatsNew.notes.contains { $0.version == version },
            "version \(version) is shipping with no What's New note — "
                + "the card would not appear at all"
        )
    }
}
