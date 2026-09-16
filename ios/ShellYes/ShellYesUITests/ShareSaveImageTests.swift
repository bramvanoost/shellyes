import XCTest

/// Does the system share sheet actually offer Save Image for the card?
///
/// It did not, for two shipped versions, and neither attempt at fixing
/// it was testable by reading the code: the payload was correct both
/// times. "Save Image" is `UIActivity.ActivityType.saveToCameraRoll`,
/// which runs inside Shell Yes rather than in an extension, so iOS
/// drops it from the sheet unless the app declares
/// `NSPhotoLibraryAddUsageDescription`. Nothing in the app's own code
/// says so, which is exactly why this has to be a UI test.
@MainActor
final class ShareSaveImageTests: XCTestCase {

    func test_shareSheet_offersSaveImage() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-screenshotMode",
            "-standings", "top",
            "-playerName", "Bram",
            "-shareCard", "allTime",
            "-sharePage",
        ]
        app.launch()
        // The splash buttons slide in; a tap landing mid-animation does
        // nothing at all. Same settle every other UI test here uses.
        Thread.sleep(forTimeInterval: 4.0)

        let share = app.buttons
            .matching(NSPredicate(format: "label ==[c] %@", "Share"))
            .firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 10), "no Share button")
        // `stampButton` reports an oversized accessibility frame, so the
        // element's centre is roughly 170pt right of the visible
        // control. Tap where the button is drawn instead.
        share.coordinate(withNormalizedOffset: CGVector(dx: 0.214, dy: 0.5)).tap()
        Thread.sleep(forTimeInterval: 5.0)

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "share-sheet"
        shot.lifetime = .keepAlways
        add(shot)

        // The sheet is hosted out of process, so look in both places
        // rather than guessing which one owns the row today.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", "Save Image")
        let inApp = app.descendants(matching: .any).matching(predicate).firstMatch
        let inSpringboard = springboard.descendants(matching: .any)
            .matching(predicate).firstMatch

        let found = inApp.waitForExistence(timeout: 8)
            || inSpringboard.waitForExistence(timeout: 8)

        let labels = (app.descendants(matching: .any).allElementsBoundByIndex
            + springboard.descendants(matching: .any).allElementsBoundByIndex)
            .prefix(120)
            .map(\.label)
            .filter { !$0.isEmpty }
        let dump = XCTAttachment(string: labels.joined(separator: "\n"))
        dump.name = "sheet-labels"
        dump.lifetime = .keepAlways
        add(dump)

        XCTAssertTrue(found, "share sheet offered no Save Image")
    }
}
