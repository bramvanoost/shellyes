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
    /// Set on weekly score boards, where the number needs explaining.
    var footnote: String?
    /// True while the rows are still on their way. Held apart from an
    /// empty `rows` so the card never tells somebody the board is
    /// empty while it is still being asked.
    var isLoading: Bool = false
    var onOpenGameCenter: () -> Void = {}

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
                Text("no scores on this board yet.")
                    .font(.avenir(13, weight: .medium, italic: true))
                    .foregroundStyle(Color.ink.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 3) {
                    ForEach(rows) { row in
                        BoardCardRow(row: row)
                    }
                }
                .padding(.horizontal, 12)
            }

            VStack(spacing: 6) {
                Text("of \(total) players")
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

    var body: some View {
        HStack(spacing: 10) {
            // Rank one gets the crown rather than a "1", which is the
            // same mark the splash pill and the share card use.
            if row.rank == 1 {
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
    static let mockRows: [BoardRow] = [
        BoardRow(rank: 1, name: "Bram", score: 96, isMe: true),
        BoardRow(rank: 2, name: "Marina", score: 94, isMe: false),
        BoardRow(rank: 3, name: "Kai", score: 91, isMe: false),
        BoardRow(rank: 4, name: "Hazel", score: 88, isMe: false),
        BoardRow(rank: 5, name: "Reef", score: 84, isMe: false),
        BoardRow(rank: 6, name: "Tine", score: 79, isMe: false),
        BoardRow(rank: 7, name: "Coral", score: 77, isMe: false),
        BoardRow(rank: 8, name: "Dune", score: 72, isMe: false),
    ]
}
#endif
