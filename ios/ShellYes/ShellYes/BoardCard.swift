import SwiftUI

/// One row of a leaderboard, flattened out of `GKLeaderboard.Entry` so
/// the view has no GameKit in it and can be built from a literal in a
/// test or a screenshot run.
struct BoardRow: Identifiable, Equatable {
    let rank: Int
    let name: String
    let score: Int
    /// The local player's own row. Drawn differently, and the reason
    /// this board is worth showing at all rather than a top ten.
    let isMe: Bool

    var id: Int { rank }
}

extension BoardRow {
    /// The ranks that wear the crown, which is everybody tied at the
    /// top score rather than whoever holds rank one.
    ///
    /// Game Center breaks a tie by who posted first, so three players
    /// on 14 come back as ranks 1, 2 and 3. Drawing the crown on rank
    /// one alone told the other two they were behind, over a number
    /// the player can plainly see is the same. The score is the thing
    /// on screen, so it is the thing the crown follows.
    ///
    /// Falls back to rank one when no rank-one row is present, which
    /// only happens if a board ever hands back a window that does not
    /// start at the top.
    static func crownedRanks(in rows: [BoardRow]) -> Set<Int> {
        guard let topScore = rows.first(where: { $0.rank == 1 })?.score else {
            return Set(rows.filter { $0.rank == 1 }.map(\.rank))
        }
        return Set(rows.filter { $0.score == topScore }.map(\.rank))
    }
}

/// A board as the app reads it: the rows worth drawing, and how many
/// players the board holds in total so a rank has a denominator.
struct BoardPage: Equatable {
    let rows: [BoardRow]
    let total: Int

    /// Nothing to draw. Every failure in `GameCenter` lands here rather
    /// than throwing, because the card has an empty state and it is a
    /// better outcome than an error in front of somebody who just won
    /// something.
    static let empty = BoardPage(rows: [], total: 0)
}

/// Which players a board reads. Ours rather than GameKit's, so every
/// view above this line stays free of GameKit.
enum BoardScope: String, CaseIterable, Identifiable {
    /// Everybody who has ever posted a score.
    case everyone
    /// The player's Game Center friends, and themselves.
    case friends

    var id: String { rawValue }

    /// The word on the toggle.
    var label: String {
        switch self {
        case .everyone: return "everyone"
        case .friends: return "friends"
        }
    }

    /// What the denominator counts.
    func denominator(_ total: Int) -> String {
        switch self {
        case .everyone: return "of \(total) players"
        case .friends: return total == 1 ? "of 1 friend" : "of \(total) friends"
        }
    }

    /// What an empty board means, which is a different thing per scope:
    /// nobody has played, against nobody you know has.
    var emptyMessage: String {
        switch self {
        case .everyone: return "no scores on this board yet."
        case .friends: return "no friends on this board yet."
        }
    }
}

/// The board, drawn in our own look.
///
/// Apple's `GKGameCenterViewController` cannot be a card: it is a
/// navigation controller built for modal presentation, with its own
/// chrome and its own Done button, and embedding it in a pager would
/// fight the swipe. But the rows behind it are already ours —
/// `loadEntries` hands back the top entries alongside the local
/// player's row, and until now we threw them away. So the second page
/// of the share sheet draws them itself.
///
/// It earns its place by saying the thing Apple's sheet cannot: on a
/// weekly score board the number is a sum of three games, which nobody
/// ever scored in one.
struct BoardCard: View {
    let title: String
    let rows: [BoardRow]
    /// How many players are on the board at all, so a rank has a
    /// denominator.
    let total: Int
    /// Which players the rows came from. Decides the denominator's
    /// wording and what an empty board is taken to mean.
    var scope: BoardScope = .everyone
    /// Set on weekly score boards, where the number needs explaining.
    var footnote: String?
    /// True while the rows are still on their way. Held apart from an
    /// empty `rows` so the card never tells somebody the board is
    /// empty while it is still being asked.
    var isLoading: Bool = false
    var onOpenGameCenter: () -> Void = {}

    /// Ranks drawn with a crown instead of a number. A tie at the top
    /// crowns every player in it; see `BoardRow.crownedRanks`.
    private var crowned: Set<Int> { BoardRow.crownedRanks(in: rows) }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.avenir(13, weight: .demiBold))
                .tracking(2.5)
                .foregroundStyle(Color.treasureInk)
                .textCase(.uppercase)
                .padding(.top, 18)
                .padding(.bottom, 14)

            if isLoading {
                Text("reading the board…")
                    .font(.avenir(13, weight: .medium, italic: true))
                    .foregroundStyle(Color.ink.opacity(0.45))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if rows.isEmpty {
                Text(scope.emptyMessage)
                    .font(.avenir(13, weight: .medium, italic: true))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 3) {
                    ForEach(rows) { row in
                        BoardCardRow(row: row, crowned: crowned.contains(row.rank))
                    }
                }
                .padding(.horizontal, 12)
            }

            VStack(spacing: 6) {
                Text(scope.denominator(total))
                    .font(.avenir(12, weight: .medium, italic: true))
                    .foregroundStyle(Color.ink.opacity(0.5))

                if let footnote {
                    Text(footnote)
                        .font(.avenir(12, weight: .medium, italic: true))
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 18)

            Button(action: onOpenGameCenter) {
                Text("open in Game Center")
                    .font(.avenir(12, weight: .medium, italic: true))
                    .tracking(1.5)
                    .foregroundStyle(Color.ink.opacity(0.5))
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: 340)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.safePeachLight)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(Color.coralDark.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: Color.treasureInk.opacity(0.22), radius: 16, y: 7)
    }
}

/// A single row. The local player's is the only one with a fill, so the
/// eye lands on it before it reads any names.
private struct BoardCardRow: View {
    let row: BoardRow
    /// Tied at the top score. Decided by the card, not the row, because
    /// it takes the whole board to know it.
    let crowned: Bool

    var body: some View {
        HStack(spacing: 10) {
            // A crowned rank gets the crown rather than its number,
            // which is the same mark the splash pill and the share
            // card use.
            if crowned {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.gold)
                    .frame(width: 26, alignment: .leading)
            } else {
                Text("\(row.rank)")
                    .font(.avenir(13, weight: .demiBold))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .frame(width: 26, alignment: .leading)
            }

            Text(row.name)
                .font(.avenir(14, weight: row.isMe ? .demiBold : .regular))
                .foregroundStyle(row.isMe ? Color.treasureInk : Color.ink.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text("\(row.score)")
                .font(.avenir(14, weight: .demiBold))
                .foregroundStyle(row.isMe ? Color.treasureInk : Color.ink.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(row.isMe ? Color.coinGoldLight.opacity(0.75) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    row.isMe ? Color.gold.opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            row.isMe
                ? "You, \(row.rank). \(row.score)"
                : "\(row.rank). \(row.name), \(row.score)"
        )
    }
}

#if DEBUG
extension BoardCard {
    /// Stand-in rows for the simulator, which has no Game Center
    /// account and would otherwise only ever show the empty state.
    ///
    /// The local player's row is named by whoever the run says they
    /// are, so a capture seeded with `-playerName` does not show one
    /// name in the greeting and another on the board.
    static func mockRows(me: String?) -> [BoardRow] {
        [
        BoardRow(rank: 1, name: me ?? "You", score: 96, isMe: true),
        BoardRow(rank: 2, name: "Marina", score: 94, isMe: false),
        BoardRow(rank: 3, name: "Nalu", score: 91, isMe: false),
        BoardRow(rank: 4, name: "Hazel", score: 88, isMe: false),
        BoardRow(rank: 5, name: "Reef", score: 84, isMe: false),
        BoardRow(rank: 6, name: "Tine", score: 79, isMe: false),
        BoardRow(rank: 7, name: "Coral", score: 77, isMe: false),
        BoardRow(rank: 8, name: "Dune", score: 72, isMe: false),
        ]
    }
}
#endif
