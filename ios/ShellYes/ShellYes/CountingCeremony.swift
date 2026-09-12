import SwiftUI
import StoreKit
import ShellYesEngine

/// Per-winner-card frame anchors, published from each winning card up to
/// the VStack so the shared rays layer can position itself behind every
/// winner. Hoisting the rays out of each card's `.background` is what
/// prevents the second winner's rays from painting over the first
/// winner's body in a tie — VStack siblings render later-on-top, so a
/// per-card background lands ON TOP of any earlier sibling.
private struct WinnerCardAnchorKey: PreferenceKey {
    static var defaultValue: [Int: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Int: Anchor<CGRect>], nextValue: () -> [Int: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct CountingCeremony: View {
    let players: [Player]
    let scores: [Int]
    let onNewGame: () -> Void
    /// Secondary exit: back to the splash instead of straight into
    /// another game. Kept visually quiet so "New Game" stays the
    /// obvious tap.
    let onHome: () -> Void
    /// Whether `ReviewPrompt` says this player has earned an ask. The
    /// win itself is checked here; the history lives at the call site,
    /// which is the one that can see `StatsStore`.
    var reviewEligible: Bool = false

    @Environment(\.requestReview) private var requestReview

    @SwiftUI.State private var revealedPlayer: Int = -1   // index currently or last animated
    @SwiftUI.State private var tickedTotals: [Int] = []
    @SwiftUI.State private var winnerRevealed: Bool = false
    @SwiftUI.State private var showNewGame: Bool = false
    @SwiftUI.State private var sparkleWave: Int = 0
    @SwiftUI.State private var humanWinHeadlineSparkle: Int = 0

    private var winnerIndices: [Int] {
        guard let top = scores.max() else { return [] }
        return scores.enumerated().compactMap { idx, s in s == top ? idx : nil }
    }

    private var winnerHeadline: String {
        if winnerIndices.count == 1 {
            let idx = winnerIndices[0]
            if idx == GameStore.humanSeat {
                return "You win."
            }
            return "\(players[idx].id.capitalized) wins."
        }
        return "It's a beach tie!"
    }

    private var isHumanWin: Bool {
        winnerIndices.count == 1 && winnerIndices[0] == GameStore.humanSeat
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer().frame(height: 26)

                Text("counting…")
                    .font(.avenir(28, weight: .ultraLight, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.ink)
                    .opacity(winnerRevealed ? 0 : 1)
                    .animation(.easeOut(duration: 0.4), value: winnerRevealed)

                if winnerRevealed {
                    WinHeadline(text: winnerHeadline, festive: isHumanWin)
                        .padding(.top, -34)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                        // Sits above the cards' light-ray backgrounds so
                        // the headline can never be visually swallowed
                        // by rays that radiate up from the winner card.
                        .zIndex(10)
                }

                Spacer().frame(height: winnerRevealed ? 30 : 22)

                VStack(spacing: winnerRevealed ? 28 : 14) {
                    ForEach(players.indices, id: \.self) { i in
                        playerCard(i)
                    }
                }
                .padding(.horizontal, 20)
                .backgroundPreferenceValue(WinnerCardAnchorKey.self) { anchors in
                    // Rays sit behind the whole card stack — any portion
                    // that extends into a sibling card's bounds is
                    // covered by that card's body, so a tie no longer
                    // shows card 2's rays bleeding onto card 1.
                    GeometryReader { geo in
                        ForEach(anchors.keys.sorted(), id: \.self) { idx in
                            if let anchor = anchors[idx] {
                                let rect = geo[anchor]
                                LightRays(
                                    rayCount: 14,
                                    innerRadius: 10,
                                    outerRadius: 150,
                                    rayWidth: 24,
                                    rotationDuration: 36,
                                    maxOpacity: 0.5
                                )
                                .allowsHitTesting(false)
                                .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                }
                .animation(.easeOut(duration: 0.5), value: winnerRevealed)

                Spacer()

                if showNewGame {
                    VStack(spacing: 14) {
                        Button("New Game") {
                            GameSFX.shared.stopEndMusic()
                            onNewGame()
                        }
                            .stampButton(primary: true, invite: true)
                            .frame(maxWidth: 280)

                        Button {
                            GameSFX.shared.stopEndMusic()
                            onHome()
                        } label: {
                            // Baseline-aligned, not centre-aligned: HOME is
                            // all caps, so its optical centre sits above the
                            // box centre and a centred glyph reads as
                            // sagging next to it.
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Image(systemName: "house")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("HOME")
                                    .font(.avenir(12, weight: .demiBold))
                                    .tracking(2.5)
                            }
                            .foregroundStyle(Color.stampText)
                            .shadow(color: Color.treasureInk.opacity(0.28), radius: 3, x: 0, y: 1)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .task {
            await runCeremony()
        }
    }

    @ViewBuilder
    private func playerCard(_ i: Int) -> some View {
        let isRevealed = revealedPlayer >= i
        let isCurrentlyCounting = revealedPlayer == i && !winnerRevealed
        let isWinner = winnerRevealed && winnerIndices.contains(i)
        let displayedTotal = tickedTotals.indices.contains(i) ? tickedTotals[i] : 0

        // Two-column layout: name on the left as the row anchor, stats
        // stacked on the right (shells top, score+pearl bottom). Reads
        // as a leaderboard row rather than a centered poster, leaves
        // more breathing room above the New Game button.
        HStack(alignment: .center, spacing: 14) {
            Text(players[i].id.capitalized)
                .font(.avenir(22, weight: isWinner ? .demiBold : .medium, italic: true))
                .foregroundStyle(Color.ink)
                .tracking(1)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 8) {
                // Shell row — empty state collapses to a quiet em-dash
                // so the right column keeps a consistent baseline.
                if players[i].tiles.isEmpty {
                    Text("no shells")
                        .font(.avenir(11, weight: .medium, italic: true))
                        .tracking(1.5)
                        .textCase(.lowercase)
                        .foregroundStyle(Color.ink.opacity(0.45))
                        .frame(height: 40)
                } else {
                    HStack(spacing: -4) {
                        ForEach(players[i].tiles, id: \.self) { tile in
                            tileChip(value: tile)
                        }
                    }
                }

                // Center-aligned with a hairline upward nudge: italic
                // digits have their visual mass above center. -3pt rode
                // the cap line, which read as the pearl hanging off the
                // top of the number; -1pt sits it in the middle of the
                // digit's body. The 11pt gap keeps the pearl from
                // crowding the italic's overhang.
                HStack(alignment: .center, spacing: 11) {
                    Text("\(displayedTotal)")
                        .font(.avenir(34, weight: .demiBold))
                        .foregroundStyle(Color.ink)
                        .monospacedDigit()
                    pearlGlyph(size: 24)
                        .shadow(color: Color.pearlEdge.opacity(0.35), radius: 0, x: 0, y: 1)
                        .offset(y: -1)
                }
                .opacity(isRevealed ? 1.0 : 0.25)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(winnerOrIdleFill(isWinner: isWinner))
        )
        // Each winner card publishes its bounds; the VStack reads them
        // via `backgroundPreferenceValue` and draws all rays in a single
        // shared layer behind every card, so sibling cards always cover
        // each other's bleed.
        .anchorPreference(key: WinnerCardAnchorKey.self, value: .bounds) { anchor in
            isWinner ? [i: anchor] : [:]
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isWinner ? Color.gold.opacity(0.75) : Color.ink.opacity(0.15),
                    lineWidth: isWinner ? 1.75 : 1
                )
        )
        .shadow(color: isCurrentlyCounting ? Color.gold.opacity(0.4) : .clear, radius: 12, x: 0, y: 0)
        .shadow(color: isWinner ? Color.gold.opacity(0.55) : .clear, radius: 22, x: 0, y: 0)
        .scaleEffect(isWinner ? 1.03 : 1.0)
        .animation(.easeOut(duration: 0.35), value: isWinner)
    }

    /// Winner fill is a gentle top-to-bottom gradient — warmer at the
    /// top, falling off into the deeper gold — so the card reads as
    /// catching light rather than being flatly tinted. Non-winners stay
    /// on the calm translucent paper wash.
    private func winnerOrIdleFill(isWinner: Bool) -> some ShapeStyle {
        if isWinner {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        Color.coinGoldLight.opacity(0.95),
                        Color.gold.opacity(0.78),
                        Color.gold.opacity(0.58)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        return AnyShapeStyle(Color.white.opacity(0.32))
    }

    @ViewBuilder
    private func tileChip(value: Int) -> some View {
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
                        .strokeBorder(Color.treasureInk, lineWidth: 1.25)
                )
            VStack(spacing: 2) {
                Text("\(value)")
                    .font(.avenir(12, weight: .demiBold))
                    .foregroundStyle(Color.treasureInk)
                PearlRow(count: GameStore.safeCoins(value), diameter: 4, spacing: 1.5)
            }
        }
        .frame(width: 30, height: 40)
        .shadow(color: Color.treasureInk.opacity(0.12), radius: 0, x: 0, y: 1)
    }

    @ViewBuilder
    private func pearlGlyph(size: CGFloat) -> some View {
        Pearl(diameter: size)
    }

    private func runCeremony() async {
        // Initialize tickedTotals as zeros for each player.
        tickedTotals = Array(repeating: 0, count: players.count)

        // Brief moment to let "counting…" settle in.
        try? await Task.sleep(nanoseconds: 600_000_000)

        for i in players.indices {
            revealedPlayer = i
            let target = scores[i]
            if target == 0 {
                // Just pause to acknowledge them, then move on.
                try? await Task.sleep(nanoseconds: 350_000_000)
            } else {
                // Tick from 0 to target. Per-step delay scales so the whole
                // count takes ~1.0–1.4s regardless of size.
                let stepNs: UInt64 = UInt64(max(40_000_000, min(140_000_000, 1_200_000_000 / UInt64(max(1, target)))))
                for v in 1...target {
                    tickedTotals[i] = v
                    GameSFX.shared.playCountTick()
                    try? await Task.sleep(nanoseconds: stepNs)
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
            }
        }

        // All players counted — pause, then reveal winner.
        try? await Task.sleep(nanoseconds: 400_000_000)
        if winnerIndices.contains(GameStore.humanSeat) {
            GameSFX.shared.playWinFanfare()
        } else {
            GameSFX.shared.playRivalWin()
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            winnerRevealed = true
        }

        // Pause for impact, then show New Game.
        try? await Task.sleep(nanoseconds: 900_000_000)
        withAnimation(.easeOut(duration: 0.4)) {
            showNewGame = true
        }

        // Ask for a rating on the player's own win, once the
        // celebration has landed and the buttons are up — the most
        // positive, least interrupted moment the app has. A tie
        // doesn't count; "It's a beach tie!" is not a rave review.
        //
        // Runs in its own Task so the sparkle loops below start on
        // time rather than waiting out the delay.
        if reviewEligible, isHumanWin {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                ReviewPrompt.shared.markAsked()
                Telemetry.shared.track("review_prompt_shown")
                requestReview()
            }
        }

        // Keep the winner card ringed in sparkles while the celebration is up.
        // Headline sparkles run on a slightly offset cadence so the screen
        // doesn't pulse in a single beat.
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_100_000_000)
                humanWinHeadlineSparkle += 1
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            sparkleWave += 1
        }
    }
}

/// Winner headline. For the human win we go bigger and animate each glyph
/// in with a small bounce, then keep a gentle gold shimmer running so the
/// line doesn't sit static while the player reads it.
private struct WinHeadline: View {
    let text: String
    let festive: Bool

    @SwiftUI.State private var entered: Bool = false
    @SwiftUI.State private var shimmer: Bool = false
    @SwiftUI.State private var lift: Bool = false

    var body: some View {
        if festive {
            festiveBody
        } else {
            Text(text)
                .font(.avenir(30, weight: .demiBold, italic: true))
                .tracking(2)
                .foregroundStyle(Color.gold)
                .shadow(color: Color.gold.opacity(0.6), radius: 14, x: 0, y: 0)
                .shadow(color: Color.ink.opacity(0.4), radius: 0, x: 0, y: 1)
        }
    }

    private var festiveBody: some View {
        let chars = Array(text)
        return HStack(spacing: 0) {
            ForEach(Array(chars.enumerated()), id: \.offset) { idx, ch in
                Text(String(ch))
                    .font(.avenir(40, weight: .bold, italic: true))
                    .tracking(2)
                    .foregroundStyle(Color.gold)
                    .shadow(
                        color: Color.coinGoldLight.opacity(shimmer ? 0.95 : 0.55),
                        radius: shimmer ? 22 : 12,
                        x: 0, y: 0
                    )
                    .shadow(color: Color.gold.opacity(0.55), radius: 4, x: 0, y: 0)
                    .shadow(color: Color.ink.opacity(0.45), radius: 0, x: 0, y: 1)
                    .scaleEffect(entered ? 1 : 0.25)
                    .opacity(entered ? 1 : 0)
                    .offset(y: entered ? (lift ? -2 : 0) : 22)
                    .rotationEffect(.degrees(entered ? 0 : -8))
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.5)
                            .delay(0.05 * Double(idx)),
                        value: entered
                    )
                    .animation(
                        .easeInOut(duration: 1.4).repeatForever(autoreverses: true)
                            .delay(0.08 * Double(idx)),
                        value: lift
                    )
            }
        }
        .onAppear {
            entered = true
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                shimmer = true
            }
            // Stagger the breath so each letter rides a slightly different
            // wave — reads as continuous celebration, not a metronome.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 250_000_000)
                lift = true
            }
        }
    }
}
