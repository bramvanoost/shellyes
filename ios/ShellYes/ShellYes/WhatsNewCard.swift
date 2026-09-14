import SwiftUI

/// The news an update brings, over the splash, once per version.
///
/// Tap anywhere to dismiss — no button. The card is not asking a
/// question, so it should not put an answer on screen; anything the
/// player does next is "yes, read it".
struct WhatsNewCard: View {
    let note: WhatsNew.Note
    let reducedMotion: Bool
    let onDismiss: () -> Void

    @SwiftUI.State private var entered = false

    var body: some View {
        ZStack {
            // The scrim is part of the tap target, which is the whole
            // screen. It also does the work of telling the player the
            // splash is still there underneath and nothing has moved.
            Color.treasureInk
                .opacity(entered ? 0.42 : 0)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ShellGlyph(size: 34)

                Text(note.title)
                    .font(.avenir(17, weight: .medium, italic: true))
                    .tracking(1.5)
                    .foregroundStyle(Color.coral)

                VStack(alignment: .leading, spacing: 11) {
                    ForEach(note.lines, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 9) {
                            // A shell per line rather than a bullet.
                            // Small enough to read as punctuation.
                            ShellGlyph(size: 9, showRidges: false)
                                .offset(y: 1)

                            Text(line)
                                .font(.avenir(13, weight: .medium))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(Color.ink.opacity(0.78))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("tap anywhere to carry on")
                    .font(.avenir(11, weight: .medium, italic: true))
                    .tracking(1)
                    .foregroundStyle(Color.ink.opacity(0.45))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Color.ink.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.treasureInk.opacity(0.25), radius: 24, x: 0, y: 10)
            .frame(maxWidth: 320)
            .padding(.horizontal, 28)
            .opacity(entered ? 1 : 0)
            .scaleEffect(entered ? 1 : 0.96)
        }
        // One target, the whole screen, including the gaps between the
        // lines of the card.
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .accessibilityIdentifier("whatsNewCard")
        .accessibilityAddTraits(.isModal)
        .onAppear {
            guard !reducedMotion else {
                entered = true
                return
            }
            withAnimation(.easeOut(duration: 0.35)) {
                entered = true
            }
        }
    }
}

#Preview {
    ZStack {
        Background()
        WhatsNewCard(
            note: WhatsNew.notes[0],
            reducedMotion: false,
            onDismiss: {}
        )
    }
}
