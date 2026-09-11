import SwiftUI

/// What a player sees when they tap Leaderboards or Achievements
/// before finishing a single game.
///
/// Apple's Game Center sheet draws its own empty board, but it can't be
/// themed and it arrives with a sign-in prompt attached — a harsh first
/// thing to meet on a screen we otherwise own. This stands in for it
/// until there is a score to show, then gets out of the way for good.
struct GameCenterEmptyView: View {
    let pane: GameCenterSheet.Pane
    /// Carried through only so the New Game tap can be attributed to
    /// the screen the player started from.
    let from: GameCenterEntry.Source
    let onClose: () -> Void

    @Environment(\.startGame) private var startGame

    /// Both panes share the headline and differ only in what they
    /// promise. It names the beach rather than the absence: the same
    /// sand the board is played on, just before anyone has walked it.
    private let headline = "fresh sands"

    private var message: String {
        switch pane {
        case .leaderboards:
            return "Finish a game, win or lose, and your score washes up here."
        case .achievements:
            return "Fourteen badges buried out there. Finish a game to start digging."
        }
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer()

                ShellMedallion(size: 72)
                    .shadow(color: Color.gold.opacity(0.4), radius: 16, x: 0, y: 0)
                    .padding(.bottom, 22)

                Text(headline)
                    .font(.avenir(28, weight: .ultraLight))
                    .tracking(2)
                    .foregroundStyle(Color.ink)
                    .padding(.bottom, 12)

                Text(message)
                    .font(.avenir(14, weight: .medium, italic: true))
                    .tracking(0.8)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink.opacity(0.6))
                    .padding(.horizontal, 34)

                Button {
                    Telemetry.shared.track("gamecenter_empty_new_game", props: [
                        "pane": pane.analyticsName,
                        "from": from.rawValue,
                    ])
                    onClose()
                    startGame()
                } label: {
                    Text("New Game")
                }
                .stampButton(primary: true, invite: true)
                .frame(maxWidth: 260)
                .padding(.top, 32)
                // Both screens that present this sheet have a New Game
                // of their own behind it, so the label alone can't
                // identify this one in a UI test.
                .accessibilityIdentifier("emptyStateNewGame")

                Button(action: onClose) {
                    Text("close")
                        .font(.avenir(13, weight: .medium, italic: true))
                        .tracking(2)
                        .textCase(.lowercase)
                        .foregroundStyle(Color.ink.opacity(0.5))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                }
                .buttonStyle(.plain)
                .padding(.top, 14)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
    }
}
