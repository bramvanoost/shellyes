import XCTest
@testable import ShellYes

/// Who gets which sheet. The board page is for every rank; the card
/// page is for a held number one and nobody else, and the whole
/// difference is one optional.
@MainActor
final class BoardSheetTests: XCTestCase {
    private func standing(
        boardID: String = WeeklyLeaderboard.scoreEasy.rawValue,
        period: StandingPeriod = .week,
        rank: Int,
        total: Int = 13,
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

    // MARK: - Who gets a card page

    func test_from_belowRankOne_makesABoardWithNoCard() {
        let subject = BoardSheetSubject.from(standing: standing(rank: 8), name: "Kai")

        XCTAssertNil(subject.card, "a twelfth place has nothing to crown")
        XCTAssertEqual(subject.tier, "ranked")
        XCTAssertEqual(subject.rank, 8)
        XCTAssertEqual(subject.total, 13)
    }

    func test_from_atRankOne_carriesTheCard() {
        let subject = BoardSheetSubject.from(standing: standing(rank: 1), name: "Kai")

        XCTAssertEqual(subject.card?.title, "Top Banana")
        XCTAssertEqual(subject.tier, "top_banana")
    }

    func test_from_atRankOneAllTime_isTheKahunaTier() {
        let subject = BoardSheetSubject.from(
            standing: standing(
                boardID: Leaderboard.scoreHard.rawValue,
                period: .allTime,
                rank: 1
            ),
            name: "Kai"
        )

        XCTAssertEqual(subject.card?.title, "Big Kahuna")
        XCTAssertEqual(subject.tier, "big_kahuna")
    }

    /// A tie at the top is a number one. Game Center ranks the second
    /// player on the same score as rank two, and the sheet has to agree
    /// with the badge the splash already drew.
    func test_from_tiedAtTheTop_stillCarriesTheCard() {
        var tied = standing(rank: 2, score: 96)
        tied.topScore = 96

        XCTAssertNotNil(BoardSheetSubject.from(standing: tied, name: nil).card)
    }

    // MARK: - What the board page says

    func test_from_headsThePageWithTheBoardTheStandingCameFrom() {
        let subject = BoardSheetSubject.from(standing: standing(rank: 4), name: nil)

        XCTAssertEqual(subject.title, "easy · this week")
        XCTAssertEqual(subject.boardID, WeeklyLeaderboard.scoreEasy.rawValue)
        XCTAssertEqual(subject.boardKey, WeeklyLeaderboard.scoreEasy.shortKey)
    }

    /// The one sentence Apple's sheet has no room for. It belongs to
    /// the board, not to the crown, so an eighth place has to get it
    /// too — that player is the one most likely to be puzzled by a
    /// number they never scored in a game.
    func test_footnote_explainsAWeeklyScoreBoardAtEveryRank() {
        let eighth = BoardSheetSubject.from(standing: standing(rank: 8), name: nil)
        let first = BoardSheetSubject.from(standing: standing(rank: 1), name: nil)

        XCTAssertEqual(eighth.footnote, "your best three games this week, added up")
        XCTAssertEqual(first.footnote, eighth.footnote)
    }

    func test_footnote_isAbsentWhereTheNumberNeedsNoExplaining() {
        let streak = BoardSheetSubject.from(
            standing: standing(boardID: WeeklyLeaderboard.bestStreak.rawValue, rank: 3),
            name: nil
        )
        let allTime = BoardSheetSubject.from(
            standing: standing(
                boardID: Leaderboard.scoreEasy.rawValue,
                period: .allTime,
                rank: 3
            ),
            name: nil
        )

        XCTAssertNil(streak.footnote)
        XCTAssertNil(allTime.footnote, "an all-time score is one game")
    }

    /// A board added by a later build, read back from this one's cache.
    /// It must still open — the rows come from an id, and GameKit knows
    /// ids this build has no case for.
    func test_from_unknownBoard_stillOpens() {
        let future = BoardSheetSubject.from(
            standing: standing(boardID: "com.fastronaut.game.shellyes.weekly.nothing", rank: 5),
            name: nil
        )

        XCTAssertEqual(future.boardID, "com.fastronaut.game.shellyes.weekly.nothing")
        XCTAssertEqual(future.boardKey, "unknown")
        XCTAssertNil(future.footnote)
    }

    /// `.sheet(item:)` redraws when the id changes, so two different
    /// standings must not share one.
    func test_id_separatesTheBoardsAndTheWindows() {
        let weekly = BoardSheetSubject.from(standing: standing(rank: 4), name: nil)
        let allTime = BoardSheetSubject.from(
            standing: standing(
                boardID: Leaderboard.scoreEasy.rawValue,
                period: .allTime,
                rank: 4
            ),
            name: nil
        )
        let streak = BoardSheetSubject.from(
            standing: standing(boardID: WeeklyLeaderboard.bestStreak.rawValue, rank: 4),
            name: nil
        )

        XCTAssertNotEqual(weekly.id, allTime.id)
        XCTAssertNotEqual(weekly.id, streak.id)
    }
}
