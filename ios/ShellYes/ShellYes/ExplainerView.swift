import SwiftUI

struct ExplainerView: View {
    /// Which door the sheet was opened from: `"home"` or `"settings"`.
    let from: String

    @Environment(\.dismiss) private var dismiss
    @SwiftUI.State private var currentPage: Int = 0
    /// Highest page reached, not the page left on. A player who reads
    /// to the end and swipes back would otherwise look like a bounce.
    @SwiftUI.State private var furthestPage: Int = 0

    private let pages = ExplainerPage.allCases

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Text("\(currentPage + 1) / \(pages.count)")
                        .font(.avenir(11, weight: .medium, italic: true))
                        .tracking(2)
                        .foregroundStyle(Color.ink.opacity(0.55))
                    Spacer()
                }
                .padding(.top, 18)

                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { i in
                        ExplainerPageView(page: pages[i])
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if currentPage < pages.count - 1 {
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        currentPage += 1
                                    }
                                }
                            }
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Swipe hint, first page only. It's teaching, not
                // chrome: once the player has moved off page one they
                // know how, and a hint drifting through all seven
                // pages is just noise. The height is reserved either
                // way so the dot row doesn't jump when it goes.
                //
                // Sits above the dots, not beside them. Level with the
                // dot row it lands on the painted palms, where a 15pt
                // glyph — ink or gold — disappears into the
                // silhouette. Up here it's on clean gradient, in the
                // gap the page copy leaves empty.
                ZStack {
                    if currentPage == 0 {
                        SwipeNudge()
                            .transition(.opacity)
                    }
                }
                .frame(height: 30)
                .padding(.bottom, 16)
                .animation(.easeOut(duration: 0.3), value: currentPage == 0)

                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        ShellCardShape()
                            .fill(
                                i == currentPage
                                    ? LinearGradient(
                                        // Bright gold for the active shell —
                                        // reads as "you're here", warm and
                                        // sunny rather than alarmed-coral.
                                        colors: [Color.coinGoldLight, Color.coinGoldDark],
                                        startPoint: .top, endPoint: .bottom
                                      )
                                    : LinearGradient(
                                        colors: [Color.ink.opacity(0.15), Color.ink.opacity(0.2)],
                                        startPoint: .top, endPoint: .bottom
                                      )
                            )
                            .overlay(
                                ShellCardShape()
                                    .strokeBorder(
                                        i == currentPage ? Color.gold : Color.ink.opacity(0.35),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: i == currentPage ? Color.gold.opacity(0.5) : .clear, radius: 6, x: 0, y: 0)
                            .frame(width: 16, height: 20)
                            .scaleEffect(i == currentPage ? 1.15 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentPage)
                    }
                }

                Button("Close") { dismiss() }
                    .stampButton(primary: false)
                    .frame(maxWidth: 240)
                    .padding(.bottom, 24)
                    .padding(.horizontal, 28)
            }
        }
        .navigationBarHidden(true)
        // Both events hang off appear/disappear rather than the Close
        // button, because a swipe-down dismiss is the common exit and
        // never touches that button.
        .onAppear {
            Telemetry.shared.track("explainer_opened", props: ["from": from])
        }
        .onChange(of: currentPage) { _, page in
            furthestPage = max(furthestPage, page)
        }
        .onDisappear {
            Telemetry.shared.track("explainer_closed", props: [
                "from": from,
                "furthest_page": furthestPage + 1,
                "pages": pages.count,
                "finished": furthestPage == pages.count - 1,
            ])
        }
    }
}

/// The swipe affordance: the word, then a chevron that breathes to the
/// right. A lone glyph was tried first and lost — at this size, on this
/// background, it read as a speck of the beach painting. The word is
/// what actually teaches; the drift is what draws the eye to the word.
///
/// Coral and lowercase italic to match the "the goal" eyebrow above it,
/// so it reads as the page's own voice rather than system chrome.
/// Non-interactive on purpose: the page itself takes the tap.
private struct SwipeNudge: View {
    @SwiftUI.State private var drifting = false

    var body: some View {
        HStack(spacing: 12) {
            Text("swipe")
                .font(.avenir(18, weight: .demiBold, italic: true))
                .tracking(3.5)

            Image(systemName: "chevron.right")
                .font(.system(size: 19, weight: .semibold))
                .offset(x: drifting ? 8 : 0)
        }
        // Cream on the lavender sky, lifted off it by a soft ink
        // shadow — the same pairing the HOME label uses on the tally.
        // Coral was tried first and sank into the background: it's a
        // mid-tone against a mid-tone.
        .foregroundStyle(Color.stampText)
        .shadow(color: Color.treasureInk.opacity(0.35), radius: 4, x: 0, y: 1)
        .opacity(drifting ? 1.0 : 0.55)
        .animation(
            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
            value: drifting
        )
        .allowsHitTesting(false)
        .onAppear { drifting = true }
    }
}

private struct ExplainerPageView: View {
    let page: ExplainerPage

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            page.illustration
                .frame(maxWidth: .infinity)
                .frame(height: 140)
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.avenir(11, weight: .demiBold, italic: true))
                    .tracking(3)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.coral)
                Text(page.headline)
                    .font(.avenir(22, weight: .demiBold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink)
                    .padding(.horizontal, 24)
                Text(page.body)
                    .font(.avenir(14, weight: .medium, italic: true))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink.opacity(0.75))
                    .padding(.horizontal, 36)
                    .lineSpacing(2)
            }
            Spacer()
        }
    }
}

private enum ExplainerPage: Int, CaseIterable {
    case intro, dice, pearl, pick, keep, bust, count

    var title: String {
        switch self {
        case .intro: return "the goal"
        case .dice:  return "your dice"
        case .pearl: return "the pearl"
        case .pick:  return "picking"
        case .keep:  return "keeping"
        case .bust:  return "busting"
        case .count: return "winning"
        }
    }

    var headline: String {
        switch self {
        case .intro: return "Collect the most pearls."
        case .dice:  return "Start with eight dice.\nGet as high as you can."
        case .pearl: return "You need a pearl."
        case .pick:  return "Pick all dice of one number."
        case .keep:  return "Get the shells with the pearls."
        case .bust:  return "Bust = lose your top shell."
        case .count: return "Count the pearls."
        }
    }

    var body: String {
        switch self {
        case .intro:
            return "Super easy soft think game, a dash of strategy mixed with a bit of luck.\nClaim sea shells with pearls. You win by ending the game with the most pearls."
        case .dice:
            return "A pearl counts as five."
        case .pearl:
            return "At least one pearl in your number lets you claim or steal a shell. Try without and you missed the wave."
        case .pick:
            return "Picking 3 here takes those three dice out of the pool — your count is nine. 3 is off the table this turn."
        case .keep:
            return "Stop and the ocean gives you the highest shell up to your number. More pearls is better. Match a rival's top shell exactly and you steal theirs."
        case .bust:
            return "Roll into nothing pickable, or stop without a pearl in hand. Your top shell drifts back to the beach — and the largest shell on the sand washes away with it. No rival took it; the tide did."
        case .count:
            return "When the sand is empty, every pearl on every shell you've claimed adds up. Most pearls wins the tide."
        }
    }

    @ViewBuilder
    var illustration: some View {
        switch self {
        case .intro: IntroIllustration()
        case .dice:  DiceIllustration()
        case .pearl: PearlIllustration()
        case .pick:  PickIllustration()
        case .keep:  KeepIllustration()
        case .bust:  BustIllustration()
        case .count: CountIllustration()
        }
    }
}

// MARK: - Page illustrations

private struct IntroIllustration: View {
    /// Show one shell from each pearl-count bracket so the player sees
    /// the supply at a glance: a 1-pearl, a 2-pearl, a 3-pearl, a 4-pearl.
    var body: some View {
        HStack(spacing: 8) {
            shell(value: 23, pearls: 1)
            shell(value: 27, pearls: 2)
            shell(value: 31, pearls: 3)
            shell(value: 35, pearls: 4)
        }
    }

    @ViewBuilder
    private func shell(value: Int, pearls: Int) -> some View {
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.pearlHighlight, Color.safePeachLight],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape().strokeBorder(Color.treasureInk, lineWidth: 1.5)
                )
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(15, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: pearls, diameter: 5, spacing: 2)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 46, height: 58)
    }
}

private struct PearlIllustration: View {
    var body: some View {
        Pearl(diameter: 90)
            .shadow(color: Color.gold.opacity(0.5), radius: 22, x: 0, y: 0)
    }
}

private struct CountIllustration: View {
    /// Three claimed shells in a row with a running pearl total, mirroring
    /// the counting-ceremony reveal at the end of a game.
    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 8) {
                shell(value: 24, pearls: 1)
                shell(value: 29, pearls: 3)
                shell(value: 33, pearls: 4)
            }
            HStack(spacing: 8) {
                Text("8")
                    .font(.avenir(30, weight: .demiBold))
                    .foregroundStyle(Color.coral)
                PearlRow(count: 8, diameter: 8, spacing: 3)
                    .frame(maxWidth: 110)
            }
        }
    }

    @ViewBuilder
    private func shell(value: Int, pearls: Int) -> some View {
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.pearlHighlight, Color.safePeachLight],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape().strokeBorder(Color.treasureInk, lineWidth: 1.5)
                )
            VStack(spacing: 4) {
                Text("\(value)")
                    .font(.avenir(15, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: pearls, diameter: 5, spacing: 2)
            }
            .padding(.bottom, 4)
        }
        .frame(width: 46, height: 58)
    }
}

private struct DiceIllustration: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                MiniDie(face: i == 3 ? "★" : "\(i + 1)", isPearl: i == 3)
            }
        }
    }
}

private struct PickIllustration: View {
    /// Three matching 3s pop with the gold highlight (the "you'd pick
    /// these" set), two others are dimmed. Reads as "select every die
    /// of one face" at a glance.
    var body: some View {
        HStack(spacing: 8) {
            MiniDie(face: "3", isPearl: false, highlighted: true)
            MiniDie(face: "1", isPearl: false).opacity(0.4)
            MiniDie(face: "3", isPearl: false, highlighted: true)
            MiniDie(face: "5", isPearl: false).opacity(0.4)
            MiniDie(face: "3", isPearl: false, highlighted: true)
        }
    }
}

private struct KeepIllustration: View {
    /// Two scenarios side by side: claim shell 22 from the supply OR
    /// take 22 from a rival's stack if it sits on top of theirs.
    var body: some View {
        HStack(spacing: 18) {
            // Left: a slice of the supply with 22 lit up as the claim.
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    sandShell(value: 21, highlighted: false)
                    sandShell(value: 22, highlighted: true)
                    sandShell(value: 23, highlighted: false)
                }
                Text("from the sand")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .tracking(1)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.ink.opacity(0.55))
            }

            Text("or")
                .font(.avenir(11, weight: .demiBold, italic: true))
                .tracking(1)
                .textCase(.lowercase)
                .foregroundStyle(Color.coral)

            // Right: a rival's vault stack with 22 sitting on top —
            // matching your number gets you that shell instead.
            VStack(spacing: 6) {
                rivalStack(top: 22, underneath: [19, 25])
                Text("from a rival")
                    .font(.avenir(9, weight: .medium, italic: true))
                    .tracking(1)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.ink.opacity(0.55))
            }
        }
    }

    @ViewBuilder
    private func sandShell(value: Int, highlighted: Bool) -> some View {
        ZStack {
            ShellCardShape()
                .fill(
                    LinearGradient(
                        colors: [Color.pearlHighlight, Color.safePeachLight],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    ShellCardShape()
                        .strokeBorder(
                            highlighted ? Color.gold : Color.treasureInk,
                            lineWidth: highlighted ? 2 : 1.2
                        )
                )
                .shadow(color: highlighted ? Color.gold.opacity(0.7) : .clear, radius: 10, x: 0, y: 0)
            VStack(spacing: 3) {
                Text("\(value)")
                    .font(.avenir(12, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: 1, diameter: 4, spacing: 2)
            }
            .padding(.bottom, 3)
        }
        .frame(width: 36, height: 48)
        .opacity(highlighted ? 1.0 : 0.55)
    }

    @ViewBuilder
    private func rivalStack(top: Int, underneath: [Int]) -> some View {
        ZStack(alignment: .top) {
            // Stacked shells below the top, offset down to suggest depth.
            ForEach(Array(underneath.enumerated()), id: \.offset) { i, value in
                ShellCardShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.safePeachLight, Color.safePeachDark],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(ShellCardShape().strokeBorder(Color.treasureInk, lineWidth: 1.2))
                    .frame(width: 38, height: 40)
                    .offset(y: CGFloat(underneath.count - i) * 5)
                    .zIndex(Double(-i - 1))
            }
            // Top shell — the one a matching number would take.
            ZStack {
                ShellCardShape()
                    .fill(
                        LinearGradient(
                            colors: [Color.pearlHighlight, Color.safePeachLight],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(ShellCardShape().strokeBorder(Color.gold, lineWidth: 2))
                    .shadow(color: Color.gold.opacity(0.7), radius: 10, x: 0, y: 0)
                VStack(spacing: 3) {
                    Text("\(top)")
                        .font(.avenir(12, weight: .demiBold))
                        .foregroundStyle(Color.treasureInk)
                    PearlRow(count: 1, diameter: 4, spacing: 2)
                }
                .padding(.bottom, 3)
            }
            .frame(width: 38, height: 40)
        }
        .frame(width: 38, height: 56)
    }
}

private struct BustIllustration: View {
    var body: some View {
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
                        Color.treasureInk.opacity(0.8),
                        style: StrokeStyle(lineWidth: 2, dash: [3, 3])
                    )
            )
            .frame(width: 76, height: 92)
            .opacity(0.85)
            .shadow(color: Color.coralDark.opacity(0.4), radius: 14, x: 0, y: 0)
    }
}


private struct MiniDie: View {
    let face: String
    let isPearl: Bool
    var highlighted: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isPearl
                        ? LinearGradient(
                            colors: [Color.coinGoldLight, Color.coinGoldDark],
                            startPoint: .top, endPoint: .bottom
                          )
                        : LinearGradient(
                            colors: [Color.safePeachLight, Color.safePeachDark],
                            startPoint: .top, endPoint: .bottom
                          )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(
                            highlighted ? Color.gold : Color.treasureInk,
                            lineWidth: highlighted ? 2.5 : 1.5
                        )
                )
                .shadow(color: highlighted ? Color.gold.opacity(0.7) : .clear, radius: 10, x: 0, y: 0)
            if isPearl {
                Pearl(diameter: 22)
            } else {
                Text(face)
                    .font(.avenir(16, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
            }
        }
        .frame(width: 44, height: 44)
    }
}

#Preview {
    ExplainerView(from: "preview")
}
