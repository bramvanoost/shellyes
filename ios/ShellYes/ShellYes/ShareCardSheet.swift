import SwiftUI

/// The screen a tapped crown opens: the card, a way to send it, and a
/// way on to the board it came from.
///
/// Why this sits between the splash and Apple's leaderboard screen at
/// all: holding a number one is the only thing in Shell Yes worth
/// showing somebody, and until now it lived on a pill nobody outside
/// the app would ever see. Sending the player straight to the board
/// hands them to Apple's UI at the exact moment they feel best about
/// the game, with nothing to take away from it. So the card comes
/// first and the board is one tap further on — and the plain
/// Leaderboards button on the splash still goes there directly, for
/// anyone who only wants the board.
///
/// There is no Save button. The share sheet already offers Save Image,
/// which means the card can reach Photos without the app ever asking
/// for the photo library — one fewer permission prompt, and nothing
/// for the filed App Privacy answers to change.
struct ShareCardSheet: View {
    let subject: ShareCardSubject
    /// Called after this sheet closes, to open Apple's board.
    let onSeeBoard: () -> Void

    @Environment(\.dismiss) private var dismiss

    /// Rendered once, on appear. A card is a few hundred kilobytes of
    /// PNG and the render is not free; re-rendering it on every layout
    /// pass would be paid for in a stutter as the sheet slides up.
    @SwiftUI.State private var card: ShareCardImage?

    /// How big the preview can be drawn here. The card is a fixed
    /// 360×450 picture, so it is scaled rather than re-laid-out — what
    /// the player sees has to be the file, not a version of it that
    /// fits better. The two limits are the sheet's width and a little
    /// under two thirds of its height, which keeps the share button and
    /// the board link on screen on the smallest phone we support.
    private func previewScale(in size: CGSize) -> CGFloat {
        let byWidth = (size.width - 48) / ShareCardView.size.width
        let byHeight = (size.height * 0.62) / ShareCardView.size.height
        return min(1, byWidth, byHeight)
    }

    var body: some View {
        GeometryReader { geo in
        let scale = previewScale(in: geo.size)
        ZStack {
            Background()
            // The card carries the same beach. Without a veil the two
            // scenes read as one busy picture and the card stops
            // looking like an object.
            Color.paper.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 0)

                // The card at its own aspect ratio, sized to the sheet.
                // What the player sees here is the file, pixel for
                // pixel, so there is never a surprise in what lands in
                // the message.
                ShareCardView(subject: subject)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(Color.ink.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.treasureInk.opacity(0.25), radius: 18, y: 8)
                    .scaleEffect(scale)
                    .frame(
                        width: ShareCardView.size.width * scale,
                        height: ShareCardView.size.height * scale
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(subject.message)

                VStack(spacing: 14) {
                    if let card {
                        ShareLink(
                            item: card,
                            subject: Text(subject.message),
                            // The link rides in the message rather than
                            // on the picture, so it is tappable
                            // wherever the card ends up.
                            message: Text("\(subject.message) \(AppLink.appStore.absoluteString)"),
                            preview: SharePreview(
                                subject.message,
                                image: Image(uiImage: card.image)
                            )
                        ) {
                            Text("Share")
                        }
                        .stampButton(primary: true, invite: true)
                        .frame(maxWidth: 280)
                    }

                    Button {
                        dismiss()
                        onSeeBoard()
                    } label: {
                        Text("see the board")
                            .font(.avenir(13, weight: .medium, italic: true))
                            .tracking(2)
                            .foregroundStyle(Color.ink.opacity(0.55))
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.ink.opacity(0.5))
                    .padding(16)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .task {
            card = ShareCardRenderer.render(subject)
        }
        }
    }
}
