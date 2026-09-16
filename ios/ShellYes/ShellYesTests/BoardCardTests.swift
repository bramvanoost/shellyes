import XCTest
@testable import ShellYes

/// The crown rule. Game Center hands back a tie as consecutive ranks,
/// so the board has to work the tie out from the scores itself.
final class BoardCardTests: XCTestCase {

    private func row(_ rank: Int, _ score: Int, isMe: Bool = false) -> BoardRow {
        BoardRow(rank: rank, name: "p\(rank)", score: score, isMe: isMe)
    }

    func test_crownedRanks_withNoTie_crownsRankOneOnly() {
        let rows = [row(1, 20), row(2, 14), row(3, 9)]

        XCTAssertEqual(BoardRow.crownedRanks(in: rows), [1])
    }

    func test_crownedRanks_withATieAtTheTop_crownsEveryoneInIt() {
        // The board Bram saw: three players on 14, one crown.
        let rows = [row(1, 14), row(2, 14), row(3, 14), row(4, 11)]

        XCTAssertEqual(BoardRow.crownedRanks(in: rows), [1, 2, 3])
    }

    func test_crownedRanks_withATieBelowTheTop_crownsNeitherOfThem() {
        let rows = [row(1, 20), row(2, 14), row(3, 14)]

        XCTAssertEqual(BoardRow.crownedRanks(in: rows), [1])
    }

    func test_crownedRanks_crownsTheLocalRowWhenItIsTiedAtTheTop() {
        // The appended local row carries its own rank from GameKit and
        // is crowned on the same rule as any other.
        let rows = [row(1, 14), row(2, 9), row(3, 14, isMe: true)]

        XCTAssertEqual(BoardRow.crownedRanks(in: rows), [1, 3])
    }

    func test_crownedRanks_withNoRows_crownsNothing() {
        XCTAssertEqual(BoardRow.crownedRanks(in: []), [])
    }

    func test_crownedRanks_withoutARankOneRow_crownsNothing() {
        // A window that does not start at the top: no claim to a crown
        // can be made from it, so none is drawn.
        let rows = [row(4, 14), row(5, 14)]

        XCTAssertEqual(BoardRow.crownedRanks(in: rows), [])
    }
}
