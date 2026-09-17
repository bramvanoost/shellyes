import XCTest
@testable import ShellYes

/// The one-time score backfill is fire-and-forget, so the decision
/// "may I mark this done?" has to survive being answered late and out
/// of order. `BackfillTally` is that decision on its own, away from
/// GameKit, which is the only reason it can be tested at all.
final class BackfillTallyTests: XCTestCase {

    func test_isNotDoneUntilEverySubmissionHasAnswered() {
        var tally = BackfillTally(expected: 3)

        XCTAssertFalse(tally.isComplete)
        XCTAssertFalse(tally.mayMarkDone)

        tally.record(success: true)
        tally.record(success: true)
        XCTAssertFalse(tally.isComplete, "two of three answered is not complete")
        XCTAssertFalse(tally.mayMarkDone)

        tally.record(success: true)
        XCTAssertTrue(tally.isComplete)
        XCTAssertTrue(tally.mayMarkDone)
    }

    /// The bug this whole type exists for. The old code set
    /// `didBackfill` synchronously right after dispatching the
    /// submissions, so a backfill that failed was marked done forever
    /// and the player's history never reached the boards.
    func test_oneFailureBlocksTheDoneFlag() {
        var tally = BackfillTally(expected: 3)

        tally.record(success: true)
        tally.record(success: false)
        tally.record(success: true)

        XCTAssertTrue(tally.isComplete, "every submission answered")
        XCTAssertFalse(
            tally.mayMarkDone,
            "a partial backfill must retry, or the failed board loses that score for good"
        )
    }

    func test_allFailingBlocksTheDoneFlag() {
        var tally = BackfillTally(expected: 2)

        tally.record(success: false)
        tally.record(success: false)

        XCTAssertTrue(tally.isComplete)
        XCTAssertFalse(tally.mayMarkDone)
    }

    /// A player with no history at all still completes: there is
    /// nothing to send, so there is nothing that can fail, and leaving
    /// the flag unset would retry an empty backfill on every launch
    /// forever.
    func test_nothingToSubmitIsImmediatelyDone() {
        let tally = BackfillTally(expected: 0)

        XCTAssertTrue(tally.isComplete)
        XCTAssertTrue(tally.mayMarkDone)
    }

    /// Answers arrive from GameKit's completion handlers, which carry
    /// no ordering guarantee. The verdict must not depend on which
    /// landed first.
    func test_orderOfAnswersDoesNotChangeTheVerdict() {
        var failFirst = BackfillTally(expected: 2)
        failFirst.record(success: false)
        failFirst.record(success: true)

        var failLast = BackfillTally(expected: 2)
        failLast.record(success: true)
        failLast.record(success: false)

        XCTAssertEqual(failFirst.mayMarkDone, failLast.mayMarkDone)
        XCTAssertFalse(failFirst.mayMarkDone)
    }

    /// Defensive: a stray extra answer must not flip a failed backfill
    /// into a clean one.
    func test_extraAnswersCannotEraseAFailure() {
        var tally = BackfillTally(expected: 1)

        tally.record(success: false)
        tally.record(success: true)

        XCTAssertFalse(tally.mayMarkDone)
    }
}
