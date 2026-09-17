import Foundation

/// Counts the answers to a one-time score backfill and decides whether
/// it may be marked done.
///
/// Its own type, with no GameKit in sight, because the decision is the
/// whole bug and everything around it is untestable.
///
/// The failure it exists to prevent, seen in production on 1.1 and 1.4:
/// `GameCenter.submit` is fire-and-forget, so `backfillIfNeeded` set
/// `didBackfill` synchronously right after *dispatching* its
/// submissions rather than after they landed. Every one of those
/// submissions fires the instant authentication flips, which is exactly
/// when GameKit is most likely to refuse them — thirteen refusals
/// across four players, all `GKInternalErrorDomain` 101, every one at
/// the same second as the `authenticated` callback. The flag was
/// written anyway, so the backfill never ran again and those players'
/// pre-Game-Center history never reached the boards.
///
/// Retrying is safe precisely because every board is `BEST_SCORE`:
/// re-sending a score a board already holds is a no-op, while skipping
/// one loses it for good. So the tally is deliberately strict — a
/// single failure keeps the flag unset and the next launch tries the
/// whole set again.
struct BackfillTally {
    /// How many submissions were dispatched, and so how many answers
    /// are owed before any verdict is possible.
    let expected: Int

    private(set) var succeeded = 0
    private(set) var failed = 0

    init(expected: Int) {
        self.expected = expected
    }

    /// Every dispatched submission has reported back. Until this is
    /// true the verdict is simply not known yet — GameKit answers on
    /// its own schedule and in no particular order.
    var isComplete: Bool { succeeded + failed >= expected }

    /// A clean sweep, and the only state that earns the done flag.
    var mayMarkDone: Bool { isComplete && failed == 0 }

    mutating func record(success: Bool) {
        if success {
            succeeded += 1
        } else {
            failed += 1
        }
    }
}
