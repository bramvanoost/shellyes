import SwiftUI

struct AIEventBanner: View {
    let event: GameStore.AIEvent

    /// How much of the auto-continue wait is left, 1 down to 0, or nil
    /// when the banner waits for a tap and nothing is counting. The
    /// view only draws it — the countdown itself is run by the game
    /// screen, the same place the bust flash runs its own.
    var countdown: Double? = nil

    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Constant deep-plum scrim. Adaptive `Color.ink` would flip
            // to cream in dark mode and brighten the screen behind the
            // banner instead of darkening it.
            Color.treasureInk.opacity(0.42)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                // zIndex bumps title + subtitle above the chip's drawing
                // layer below. The chip's LightRays background extends
                // ~90pt beyond the chip silhouette, including upward into
                // the title's row — VStack draws top-to-bottom, so without
                // an explicit zIndex the chip's later paint covers the
                // title.
                Text(titleLine)
                    .font(.avenir(24, weight: .demiBold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(titleColor)
                    .padding(.horizontal, 18)
                    .zIndex(1)

                if let subtitle = subtitleLine {
                    Text(subtitle)
                        .font(.avenir(14, weight: .medium, italic: true))
                        .tracking(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(subtitleColor)
                        .padding(.horizontal, 24)
                        .zIndex(1)
                }

                if let shell = shellNumber {
                    ShellChip(value: shell, drifting: false, celebrate: tone == .positive)
                        .padding(.top, 4)
                } else if case .bust(_, let burned) = event, let burned {
                    ShellChip(value: burned, drifting: true, celebrate: false)
                        .padding(.top, 4)
                } else {
                    Image(systemName: "wind")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(Color.coralDark)
                        .padding(.top, 4)
                }

                VStack(spacing: 7) {
                    // The tide pulling back, same as the bust flash —
                    // a countdown that reads as the beach rather than
                    // as a progress bar.
                    if let countdown {
                        WaveLine(wavelength: 10, amplitude: 2)
                            .stroke(tapHintColor.opacity(0.9), lineWidth: 1.4)
                            .frame(width: 140, height: 8)
                            .mask(
                                Rectangle()
                                    .frame(width: 140 * countdown, height: 8)
                            )
                    }

                    // A tap still skips the wait, so the hint stands
                    // either way.
                    Text("tap to continue")
                        .font(.avenir(11, weight: .demiBold, italic: true))
                        .tracking(2)
                        .textCase(.lowercase)
                        .foregroundStyle(tapHintColor)
                }
                .padding(.top, 6)
            }
            .padding(.vertical, 28)
            .padding(.horizontal, 24)
            .frame(maxWidth: 360)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(cardStroke, lineWidth: tone == .negative ? 1.5 : 1)
            )
            .shadow(color: Color.treasureInk.opacity(0.35), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 32)
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    private var titleLine: String {
        switch event {
        case .took(let actor, let shell, let isFinal):
            if isFinal {
                if actor.lowercased() == "you" {
                    return "Shell yes!\nYou claimed the last shell."
                }
                return "\(actor) claimed the last shell."
            }
            if actor.lowercased() == "you" {
                return "Nice, you claimed shell \(shell)!"
            }
            return "\(actor) claimed a shell!"
        case .stole(let actor, let victim, let shell, let isFinal):
            if isFinal {
                if actor.lowercased() == "you" {
                    return "You took \(victim)'s last shell."
                }
                if victim.lowercased() == "you" {
                    return "\(actor) took your last shell."
                }
                return "\(actor) took \(victim)'s last shell."
            }
            if actor.lowercased() == "you" {
                return "Nice, you took \(victim)'s shell \(shell)!"
            }
            if victim.lowercased() == "you" {
                return "\(actor) casually took your shell!"
            }
            return "\(actor) casually took \(victim)'s shell!"
        case .bust(let actor, _):
            return "\(actor) went bust"
        }
    }

    // Positive/neutral text sits on the constant cream celebration card,
    // so the ink stays constant deep plum too. Without this the banner
    // flips to a plum card with cream text in dark mode and loses its
    // "physical treasure" feel.
    private var titleColor: Color {
        return tone == .negative ? Color.stampText : Color.treasureInk
    }

    private var subtitleColor: Color {
        return tone == .negative ? Color.stampText.opacity(0.85) : Color.treasureInk.opacity(0.7)
    }

    private var tapHintColor: Color {
        return tone == .negative ? Color.stampText.opacity(0.7) : Color.treasureInk.opacity(0.45)
    }

    private enum Tone { case positive, negative, neutral }

    /// Player-perspective tone. Positive = good for you (you claimed, AI
    /// busted). Negative = bad for you (AI took your shell). Neutral = the
    /// event doesn't directly involve you.
    private var tone: Tone {
        switch event {
        case .took(let actor, _, _):
            return actor.lowercased() == "you" ? .positive : .neutral
        case .stole(let actor, let victim, _, _):
            if actor.lowercased() == "you" { return .positive }
            if victim.lowercased() == "you" { return .negative }
            return .neutral
        case .bust(let actor, _):
            return actor.lowercased() == "you" ? .negative : .positive
        }
    }

    @ViewBuilder
    private var cardBackground: some View {
        switch tone {
        case .negative:
            // Deeper coral-to-crimson gradient — cream text reads cleanly
            // against this where it didn't against the lighter rose.
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [Color.coralDark, Color.bannerNegativeAccent],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        case .positive, .neutral:
            // Constant cream — same value as light-mode `Color.paper`
            // but doesn't invert in dark mode. Matches the treasure
            // palette so the shell chip inside reads as a physical
            // object rather than a piece of chrome.
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.stampText)
        }
    }

    private var cardStroke: Color {
        switch tone {
        case .negative: return Color.bannerNegativeAccent
        case .positive, .neutral: return Color.treasureInk.opacity(0.18)
        }
    }

    private var subtitleLine: String? {
        switch event {
        case .took(_, _, let isFinal), .stole(_, _, _, let isFinal):
            // The final-shell banner closes the game and dissolves
            // into the tally — borrow the engine's game-over hint so
            // the language of the moment is consistent.
            return isFinal ? "The tide rolls back." : nil
        case .bust(_, let burned):
            if let burned {
                return "Shell \(burned) drifts away."
            }
            return "A shell drifts away."
        }
    }

    private var shellNumber: Int? {
        switch event {
        case .took(_, let shell, _), .stole(_, _, let shell, _):
            return shell
        case .bust:
            return nil
        }
    }

}

/// Shell card chip shown inside the AI event banner. Owns its own pop
/// state so the shell springs in when the modal appears, distinct from
/// the modal's calmer fade-and-scale entrance.
private struct ShellChip: View {
    let value: Int
    let drifting: Bool
    let celebrate: Bool

    @SwiftUI.State private var popScale: CGFloat = 0.4

    var body: some View {
        let coins = GameStore.safeCoins(value)
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.safePeachLight, Color.safePeachDark],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(
                            // Dashed stroke is the only "drifting away" cue
                            // we lean on now — the fill stays peach so the
                            // shell still reads as readable.
                            drifting ? Color.treasureInk.opacity(0.8) : Color.treasureInk,
                            style: StrokeStyle(lineWidth: 2, dash: drifting ? [3, 3] : [])
                        )
                )
                .shadow(color: Color.treasureInk.opacity(drifting ? 0.15 : 0.25), radius: 0, x: 0, y: 4)
                .shadow(color: Color.coralDark.opacity(0.2), radius: 14, x: 0, y: 0)
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(28, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: coins, diameter: 7, spacing: 3)
            }
        }
        .frame(width: 68, height: 84)
        .opacity(drifting ? 0.85 : 1.0)
        // Rays of light render in `.background`, not as a sibling in
        // the ZStack: a sibling with its own larger frame would force
        // the ZStack — and ShellCardShape inside it — to that size.
        // Background sits behind the chip, so the portions of the
        // rays underneath the silhouette are hidden and only the
        // outer rays radiate beyond the shell.
        .background {
            if celebrate {
                // Brighter + slightly wider rays than the default, and
                // no dark-mode dampening — the banner's surface is now
                // constant cream regardless of system appearance, so
                // the dampening (sized for plum dark-mode card) would
                // just wash these out.
                LightRays(
                    rayWidth: 22,
                    maxOpacity: 0.9,
                    adaptToColorScheme: false
                )
                .allowsHitTesting(false)
            }
        }
        .scaleEffect(popScale)
        .onAppear {
            // Snappier spring pop: short response so the chip arrives
            // fast, low damping for a visible overshoot past 1.0 before
            // settling. Starts at 0.4 so the growth itself is obvious.
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) {
                popScale = 1.0
            }
        }
    }
}

