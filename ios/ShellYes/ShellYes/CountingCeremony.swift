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
    /// Context for the `review_prompt_shown` event: how much history
    /// the player had when we spent the ask. Counts only, no identity.
    var reviewGamesPlayed: Int = 0
    var reviewWins: Int = 0
    /// Whether `DifficultyNudge` says this player has outgrown Easy.
    /// Same split as the review ask: the policy is decided at the call
    /// site, which can see `SettingsStore` and `StatsStore`.
    var nudgeEligible: Bool = false
    /// Context for `difficulty_nudge_shown`: how much Easy it took.
    var nudgeGamesOnEasy: Int = 0
    var nudgeWinsOnEasy: Int = 0
    /// Accepting the nudge moves the setting to Normal. Owned by the
    /// caller because this view holds no settings of its own.
    var onStepUpDifficulty: () -> Void = {}

    @Environment(\.requestReview) private var requestReview
    /// The skip wave rides wall time, so it is the one thing here
    /// that has to be told to hold still.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @SwiftUI.State private var revealedPlayer: Int = -1   // index currently or last animated
    @SwiftUI.State private var tickedTotals: [Int] = []
    @SwiftUI.State private var winnerRevealed: Bool = false
    @SwiftUI.State private var showNewGame: Bool = false
    @SwiftUI.State private var sparkleWave: Int = 0
    @SwiftUI.State private var humanWinHeadlineSparkle: Int = 0
    @SwiftUI.State private var showNudge: Bool = false
    @SwiftUI.State private var nudgeAnswered: Bool = false
    /// Set once, never unset: the player has asked for the end of
    /// the count rather than the count.
    @SwiftUI.State private var skipped: Bool = false

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

    private var offersReviewAsk: Bool {
        #if DEBUG
        // A capture run asked for the difficulty card, so the rating
        // dialog would only land on top of the thing being captured.
        if ScreenshotMode.forcesDifficultyNudge { return false }
        #endif
        return reviewEligible && isHumanWin
    }

    /// The difficulty card lands on the player's own win, and yields
    /// to the rating ask when both want the same tally.
    ///
    /// On a win because the card says "you're winning on Easy" and a
    /// screen that just read "Jonas wins." makes a liar of it. Yielding
    /// because iOS caps the rating dialog at three a year and two
    /// prompts stacked on one tally is how a calm game stops being
    /// calm — the nudge can wait for the next win, the ask can't be
    /// re-spent.
    private var offersDifficultyNudge: Bool {
        #if DEBUG
        // A capture run, or a thumb on the ladybug menu, can't choose
        // whether the dice hand it a win.
        if DifficultyNudge.isDebugForced { return nudgeEligible }
        #endif
        return nudgeEligible && isHumanWin && !offersReviewAsk
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

                // A soft way out of the count. Every number on this
                // screen was decided before it appeared, so the
                // ceremony is a courtesy and a player who has seen it
                // enough times should be able to wave it past. Quiet
                // enough to miss on a first playthrough, in the same
                // language as HOME below, and gone the moment the
                // winner lands — there is nothing left to skip by then.
                if !winnerRevealed {
                    Button(action: skipCeremony) {
                        VStack(spacing: 5) {
                            Text("SKIP")
                                .font(.avenir(12, weight: .demiBold))
                                .tracking(2.5)
                            // The app's own countdown glyph, run quick.
                            // QuietAICard's calm swells are 64/44/30 and
                            // the banner countdowns are 10; 13 across
                            // this width gives four and a half crests,
                            // which still reads as water. Tighter than
                            // that and it crams into a zigzag — the
                            // hurry has to come from the phase speed
                            // rather than from the wavelength, or the
                            // wave stops being a wave. Phase rides wall
                            // time so it keeps travelling while the
                            // counters tick.
                            TimelineView(.animation) { context in
                                let t = reduceMotion
                                    ? 0
                                    : context.date.timeIntervalSinceReferenceDate
                                WaveLine(
                                    wavelength: 13,
                                    amplitude: 2.5,
                                    phase: CGFloat(t) * 5.5
                                )
                                .stroke(Color.ink.opacity(0.34), lineWidth: 1.3)
                            }
                            .frame(width: 60, height: 10)
                        }
                        .foregroundStyle(Color.ink.opacity(0.42))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 24)
                        // Quiet is a look, not a hit area. The label and
                        // wave together are about 29pt tall, which left
                        // the tappable box under Apple's 44pt minimum.
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("skipTally")
                    .accessibilityLabel("Skip the count")
                    .padding(.bottom, 10)
                    .transition(.opacity)
                }

                if showNudge {
                    DifficultyNudgeCard(
                        onAccept: {
                            answerNudge(accepted: true)
                            onStepUpDifficulty()
                        },
                        onDecline: { answerNudge(accepted: false) }
                    )
                    .padding(.horizontal, 24)
                    .padding(.bottom, 18)
                    .transition(.opacity)
                    // The card and the buttons below it are the only
                    // things on this screen with a fixed job. Given
                    // priority, the celebration above gives up its
                    // slack instead of the card losing a line.
                    .layoutPriority(1)
                }

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

    /// Both answers close the card for good; the bookkeeping was
    /// already spent when it appeared. Only the telemetry differs, and
    /// that difference is the whole question: does anyone take the
    /// step up when offered it.
    private func answerNudge(accepted: Bool) {
        guard !nudgeAnswered else { return }
        nudgeAnswered = true
        Telemetry.shared.track("difficulty_nudge_answered", props: [
            "choice": accepted ? "accepted" : "declined",
            "games_on_easy": nudgeGamesOnEasy,
            "wins_on_easy": nudgeWinsOnEasy,
        ])
        withAnimation(.easeOut(duration: 0.35)) {
            showNudge = false
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

    /// One beat of the ceremony. Returns whether the ceremony should
    /// keep going, so each step reads as "wait, then check we still
    /// want to be here".
    ///
    /// Skipping deliberately does not cancel the task. Everything after
    /// the count — the fanfare, the winner reveal, the buttons — is the
    /// destination rather than part of the wait, so the same function
    /// still has to run to the end. It just stops sleeping.
    private func settle(_ nanoseconds: UInt64) async -> Bool {
        if skipped { return false }
        try? await Task.sleep(nanoseconds: nanoseconds)
        return !skipped
    }

    /// Jumps to the end of the count.
    ///
    /// Safe by construction: the scores were final before this screen
    /// was built, `tickedTotals` is only ever a display of them, and the
    /// winner is derived from `scores` rather than from what has been
    /// counted so far. The only thing given up is the ceremony.
    private func skipCeremony() {
        guard !skipped, !winnerRevealed else { return }
        skipped = true
        Telemetry.shared.track("tally_skipped", props: [
            "players": players.count,
            // How far in they were. If this clusters at 0 the ceremony
            // is being skipped on sight and its length is the problem,
            // not its existence.
            "counted": max(0, revealedPlayer),
        ])
    }

    private func runCeremony() async {
        // Initialize tickedTotals as zeros for each player.
        tickedTotals = Array(repeating: 0, count: players.count)

        // Brief moment to let "counting…" settle in.
        if await settle(600_000_000) {
            counting: for i in players.indices {
                revealedPlayer = i
                let target = scores[i]
                if target == 0 {
                    // Just pause to acknowledge them, then move on.
                    if await settle(350_000_000) == false { break counting }
                } else {
                    // Tick from 0 to target. Per-step delay scales so the whole
                    // count takes ~1.0–1.4s regardless of size.
                    let stepNs: UInt64 = UInt64(max(40_000_000, min(140_000_000, 1_200_000_000 / UInt64(max(1, target)))))
                    for v in 1...target {
                        tickedTotals[i] = v
                        GameSFX.shared.playCountTick()
                        if await settle(stepNs) == false { break counting }
                    }
                    if await settle(350_000_000) == false { break counting }
                }
            }
        }

        // Whether the count ran or was cut short, the totals on screen
        // have to be the real ones before anyone is called the winner.
        tickedTotals = scores
        revealedPlayer = players.count - 1

        // All players counted — pause, then reveal winner.
        _ = await settle(400_000_000)
        if winnerIndices.contains(GameStore.humanSeat) {
            GameSFX.shared.playWinFanfare()
        } else {
            GameSFX.shared.playRivalWin()
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            winnerRevealed = true
        }

        // Pause for impact, then show New Game. A skipped count has
        // no impact to pause for.
        _ = await settle(900_000_000)
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
        if offersReviewAsk {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                ReviewPrompt.shared.markAsked()
                Telemetry.shared.track("review_prompt_shown", props: [
                    "games_played": reviewGamesPlayed,
                    "wins": reviewWins,
                ])
                requestReview()
            }
        }

        // The difficulty card comes after the buttons, on the same
        // beat the rating ask would have used. It is not a modal: the
        // tally is still readable behind it and both answers dismiss it
        // for good.
        if offersDifficultyNudge {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                guard !Task.isCancelled else { return }
                DifficultyNudge.shared.markShown()
                Telemetry.shared.track("difficulty_nudge_shown", props: [
                    "games_on_easy": nudgeGamesOnEasy,
                    "wins_on_easy": nudgeWinsOnEasy,
                    "won_this_game": isHumanWin,
                ])
                withAnimation(.easeOut(duration: 0.45)) {
                    showNudge = true
                }
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

/// The one-time offer to leave Easy behind. Two answers, both final:
/// the card is spent whichever way it is tapped, so neither reads as
/// "ask me again".
private struct DifficultyNudgeCard: View {
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("deeper water?")
                .font(.avenir(17, weight: .medium, italic: true))
                .tracking(1.5)
                .foregroundStyle(Color.coral)

            // Short on purpose: the tally is a tall screen and this
            // card is the last thing on it. The break is hard rather
            // than wrapped so the two sentences always split where
            // they were written to split. `fixedSize` keeps both lines
            // whole when the stack above runs out of room — without it
            // SwiftUI compresses the text to one truncated line rather
            // than shrinking anything else.
            Text("You're winning on Easy.\nNormal rivals hold out longer.")
                .font(.avenir(13, weight: .medium))
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(Color.ink.opacity(0.75))
                .padding(.horizontal, 6)

            // Both answers wear the same soft inset the difficulty
            // control in Settings wears, because this is that control
            // asked as a question. Sentence case, not the splash's
            // tracked caps: caps are for stamps you navigate with, and
            // "Normal" here has to read as the same word the Settings
            // segment spells.
            HStack(spacing: 10) {
                GhostAnswer(title: "Stay on Easy", preferred: false, action: onDecline)
                GhostAnswer(title: "Try Normal", preferred: true, action: onAccept)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.cardSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.ink.opacity(0.18), lineWidth: 1)
        )
        // The card animates in a beat after the buttons, so a capture
        // run has to wait for it rather than guess at the delay.
        .accessibilityIdentifier("difficultyNudge")
    }
}

/// One of the card's two answers. Both are the same soft inset shape;
/// only weight and ink separate the one being suggested from the one
/// that changes nothing. Nothing shouts, which is the point — a player
/// who wants to stay on Easy should not feel talked out of it.
private struct GhostAnswer: View {
    let title: String
    let preferred: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.avenir(13, weight: preferred ? .demiBold : .medium))
                .foregroundStyle(Color.ink.opacity(preferred ? 0.9 : 0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.insetSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            Color.ink.opacity(preferred ? 0.4 : 0.2),
                            lineWidth: 1
                        )
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
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
