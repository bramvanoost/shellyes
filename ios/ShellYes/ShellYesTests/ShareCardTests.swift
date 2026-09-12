import XCTest
@testable import ShellYes

/// The card's words, not its picture. Everything that decides what a
/// card claims is a pure function of a standing, which is what makes it
/// checkable here without a Game Center account, a simulator or a
/// render.
@MainActor
final class ShareCardTests: XCTestCase {
    /// Thursday 14 Nov 2024, 22:13 UTC — the same fixed instant
    /// `WeeklyBestsTests` uses, so week ids agree across both files.
    private let anchor = Date(timeIntervalSince1970: 1_731_622_400)

    private func standing(
        boardID: String,
        period: StandingPeriod,
        rank: Int,
        total: Int = 120,
        score: Int = 96
    ) -> BoardStanding {
        BoardStanding(
            boardID: boardID,
            period: period,
            rank: rank,
            total: total,
            score: score
        )
    }

    // MARK: - Who gets a card

    func test_from_makesNoCardBelowRankOne() {
        let second = standing(
            boardID: WeeklyLeaderboard.scoreEasy.rawValue,
            period: .week,
            rank: 2
        )
        XCTAssertNil(ShareCardSubject.from(standing: second, name: "Kai"))
    }

    func test_from_crownsTheWeeklyBoardTopBanana() {
        let top = standing(
            boardID: WeeklyLeaderboard.scoreEasy.rawValue,
            period: .week,
            rank: 1
        )
        let card = ShareCardSubject.from(standing: top, name: "Kai", now: anchor)

        XCTAssertEqual(card?.title, "Top Banana")
        XCTAssertEqual(card?.isKahuna, false)
        XCTAssertEqual(card?.boardName, "easy")
        XCTAssertEqual(card?.scorePhrase, "96 coins")
    }

    func test_from_crownsTheAllTimeBoardBigKahuna() {
        let top = standing(
            boardID: Leaderboard.scoreHard.rawValue,
            period: .allTime,
            rank: 1
        )
        let card = ShareCardSubject.from(standing: top, name: "Kai", now: anchor)

        XCTAssertEqual(card?.title, "Big Kahuna")
        XCTAssertEqual(card?.isKahuna, true)
        // No dates on an all-time card: there is no window to name.
        XCTAssertEqual(card?.windowLine, "all time")
    }

    // MARK: - What the card says

    /// The whole reason a weekly card names dates: it is looked at
    /// after the week it belongs to has ended, by somebody who was not
    /// there. "This week" would be a claim about the reader's week.
    func test_from_namesTheWeeksDatesRatherThanSayingThisWeek() {
        let top = standing(
            boardID: WeeklyLeaderboard.bestStreak.rawValue,
            period: .week,
            rank: 1,
            score: 5
        )
        let card = ShareCardSubject.from(standing: top, name: nil, now: anchor)

        XCTAssertNotNil(card?.windowLine)
        XCTAssertTrue(card?.windowLine.hasPrefix("week of") == true,
                      "expected dated week, got \(card?.windowLine ?? "nil")")
        XCTAssertFalse(card?.windowLine.contains("this week") == true)
    }

    func test_scorePhrase_saysWhatTheNumberCounts() {
        let streak = standing(
            boardID: WeeklyLeaderboard.bestStreak.rawValue,
            period: .week,
            rank: 1,
            score: 5
        )
        let keep = standing(
            boardID: Leaderboard.biggestKeep.rawValue,
            period: .allTime,
            rank: 1,
            score: 8
        )
        let lonelyStreak = standing(
            boardID: Leaderboard.bestStreak.rawValue,
            period: .allTime,
            rank: 1,
            score: 1
        )

        XCTAssertEqual(streak.scorePhrase, "5 wins in a row")
        XCTAssertEqual(keep.scorePhrase, "8 coins in one keep")
        XCTAssertEqual(lonelyStreak.scorePhrase, "1 win in a row")
    }

    /// A board added in a later build, read back from this one's cache.
    /// It must not crash and must not invent a phrase for a number it
    /// cannot name.
    func test_unknownBoard_yieldsNoScorePhrase() {
        let future = standing(
            boardID: "com.fastronaut.game.shellyes.weekly.nothing",
            period: .week,
            rank: 1
        )
        XCTAssertNil(future.scorePhrase)
        // Still a card: rank one is rank one, whatever the board is.
        XCTAssertEqual(ShareCardSubject.from(standing: future, name: nil)?.title,
                       "Top Banana")
    }

    func test_message_carriesTheClaimAndTheBoard() {
        let top = standing(
            boardID: WeeklyLeaderboard.scoreEasy.rawValue,
            period: .week,
            rank: 1
        )
        let card = ShareCardSubject.from(standing: top, name: "Kai", now: anchor)

        XCTAssertTrue(card?.message.contains("Top Banana") == true)
        XCTAssertTrue(card?.message.contains("easy") == true)
        // The player's name is on the picture, never in the text the
        // share sheet hands to other apps.
        XCTAssertFalse(card?.message.contains("Kai") == true)
    }

    // MARK: - The week in words

    func test_weekLabel_namesTheSevenDaysOfTheID() {
        // 2024-W46 is Mon 11 Nov to Sun 17 Nov.
        let label = WeeklyBests.weekLabel(for: "2024-W46")
        XCTAssertNotNil(label)
        XCTAssertTrue(label?.contains("11") == true, "got \(label ?? "nil")")
        XCTAssertTrue(label?.contains("17") == true, "got \(label ?? "nil")")
        // The year is not optional: a card is read long after the week
        // it names has passed.
        XCTAssertTrue(label?.contains("2024") == true, "got \(label ?? "nil")")
    }

    func test_weekLabel_refusesNonsense() {
        XCTAssertNil(WeeklyBests.weekLabel(for: "not-a-week"))
        XCTAssertNil(WeeklyBests.weekLabel(for: "2024-Wxx"))
    }
}
