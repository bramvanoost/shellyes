import SwiftUI

struct SplashView: View {
    let store: GameStore
    let settings: SettingsStore
    let stats: StatsStore
    let standings: StandingsStore

    @SwiftUI.State private var logoVisible: Bool = false
    @SwiftUI.State private var actionsVisible: Bool = false
    @SwiftUI.State private var creditVisible: Bool = false
    @SwiftUI.State private var showExplainer: Bool = false
    @SwiftUI.State private var gameCenter = GameCenterEntry()

    /// The card a tapped crown opens, or nil when no card is up.
    @SwiftUI.State private var shareSubject: ShareCardSubject?

    /// The news this update brings, once per version, or nil when
    /// there is none to tell.
    @SwiftUI.State private var whatsNewNote: WhatsNew.Note?

    #if DEBUG
    /// Set from the ladybug menu, so the splash can be looked at with
    /// the How to Play button out of the way — the one row on this
    /// screen that a returning player never needs.
    @SwiftUI.State private var debugHidesHowToPlay = false
    #endif

    /// The row is for somebody who has not played. Two finished games
    /// in, it is clutter, so it goes — and because this reads the
    /// lifetime counter `StatsStore` already keeps, a player with forty
    /// games behind them loses it the first time they open this build.
    /// The rules stay reachable from Settings.
    private var showsHowToPlay: Bool {
        #if DEBUG
        if debugHidesHowToPlay { return false }
        // A capture run shares one install across its tests, so a
        // finished game in an earlier test would take the row away
        // from the screenshot that is about it.
        if ScreenshotMode.isActive { return true }
        #endif
        return stats.gamesPlayed < 2
    }

    /// False until a game has been finished. It no longer decides
    /// whether the Game Center entries appear — they always do — only
    /// whether tapping one reaches Apple's sheet or our empty one.
    private var hasPlayed: Bool { stats.gamesPlayed > 0 }

    /// Where a signed-in player reads their standings, a signed-out one
    /// reads nothing at all. This line fills that slot.
    ///
    /// It waits for a finished game, the way the Game Center entries
    /// already distinguish `hasPlayed`: it is the one thing on this
    /// screen that asks the player for something, and a first run
    /// should not be asking anybody to sign into anything.
    private var showsSignInLine: Bool {
        guard hasPlayed, !GameCenter.shared.isAuthenticated else { return false }
        #if DEBUG
        // Captures seed standings without an account; the line would
        // sit under them in every screenshot.
        if ScreenshotMode.isActive { return false }
        #endif
        return true
    }

    private var creditAttributed: AttributedString {
        let raw = "Background music by [Alfarran Basalim](https://pixabay.com/users/farran_ez-45967570/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=456148) from [Pixabay](https://pixabay.com/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=456148)."
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    private var sfxCreditAttributed: AttributedString {
        let raw = "UI sounds by [cadecomposer](https://github.com/cadecomposer)."
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    /// What tapping a standing does.
    ///
    /// A held number one opens its share card, because that is the one
    /// rank worth showing anybody and the moment the player is proudest
    /// is the moment to offer it. Everything else goes straight to the
    /// board, which is the only useful thing to do with a twelfth
    /// place. The Leaderboards button below is untouched either way, so
    /// the direct route to Apple's screen always exists.
    private func tap(_ standing: BoardStanding) {
        guard let subject = ShareCardSubject.from(
            standing: standing,
            name: GameCenter.shared.playerFirstName
        ) else {
            gameCenter.open(.leaderboards, from: .home, hasPlayed: hasPlayed)
            return
        }
        Telemetry.shared.track("share_card_opened", props: [
            "board": standing.board?.shortKey
                ?? standing.weeklyBoard?.shortKey
                ?? "unknown",
            "period": standing.period.rawValue,
            "tier": standing.isKahuna ? "big_kahuna" : "top_banana",
        ])
        shareSubject = subject
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                // Bounded rather than a free Spacer, so the shell and
                // the wordmark sit high on the screen instead of being
                // pushed to the middle. Stacking each standing onto two
                // lines made the block below taller, and a centred
                // layout answered that by squeezing the buttons; this
                // spends the screen's slack at the top, where there is
                // nothing to lose.
                Spacer(minLength: 0)
                    .frame(maxHeight: 28)

                // Hero medallion — gold coin with a shell engraved on it.
                ShellMedallion(size: 84)
                    .shadow(color: Color.gold.opacity(0.45), radius: 22, x: 0, y: 0)
                    .shadow(color: Color.treasureInk.opacity(0.22), radius: 0, x: 0, y: 6)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(logoVisible ? 1 : 0.85)
                    .padding(.bottom, 14)

                // Wordmark — Optima at semibold for a humanist, beachy feel.
                // Uniform ink, no accent letter; tracking is light so the
                // two words read as one wordmark.
                Text("Shell Yes")
                    .font(.custom("Optima", size: 54).weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(Color.ink)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(logoVisible ? 1 : 0.92)

                Text("A beachy soft slow thinky game.")
                    .font(.avenir(13, weight: .medium, italic: true))
                    .tracking(1.5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.ink.opacity(0.6))
                    .padding(.top, 8)
                    .padding(.horizontal, 30)
                    .opacity(logoVisible ? 1 : 0)

                VStack(spacing: 18) {
                    // The greeting and the rank are one block above New
                    // Game, not tucked under the Leaderboards button: a
                    // name and a rank are the two things on this screen
                    // that are about the player rather than the game,
                    // and they belong where the eye lands first.
                    //
                    // The greeting stands with or without a rank —
                    // knowing someone's name is reason enough to use
                    // it. Tapping the rank opens the board it came
                    // from, so the line is the shortest route to the
                    // thing it talks about.
                    // Wider than the 3pt inside a standing, and that
                    // difference is the whole point: a title and its
                    // board phrase have to group more tightly than one
                    // standing does to the next, or the sublines read
                    // as a single run of small print.
                    VStack(spacing: 13) {
                        if let name = GameCenter.shared.playerFirstName {
                            Text("Aloha, \(name)")
                                .font(.avenir(15, weight: .demiBold, italic: true))
                                .tracking(1)
                                .foregroundStyle(Color.ink.opacity(0.7))
                                .padding(.bottom, 2)
                                .transition(.opacity)
                        }

                        // This week's boards, in board order rather
                        // than best-first: an order a player learns
                        // once and can then read without looking, and
                        // one that doesn't reshuffle itself the week
                        // they improve.
                        //
                        // All-time ranks are deliberately absent. They
                        // are mostly a seniority queue — see
                        // WEEKLY-BOARDS — and ten lines above New Game
                        // would be absurd. The exception is a held
                        // number one, which is the best thing about the
                        // account and is promoted below.
                        ForEach(standings.splashRanks) { standing in
                            Button {
                                tap(standing)
                            } label: {
                                StandingLine(
                                    standing: standing,
                                    reducedMotion: settings.reducedMotion
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }

                        if let crown = standings.splashCrown {
                            Button {
                                tap(crown)
                            } label: {
                                StandingLine(
                                    standing: crown,
                                    reducedMotion: settings.reducedMotion
                                )
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }

                        if showsSignInLine {
                            Button {
                                gameCenter.signIn(from: .home)
                            } label: {
                                Text("Sign in to Game Center to take a rank")
                                    // The size of a middling standing,
                                    // because that is what it stands in
                                    // for. An invitation, not a banner.
                                    .font(.avenir(12, weight: .demiBold, italic: true))
                                    .tracking(1.5)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(Color.ink.opacity(0.55))
                            }
                            .buttonStyle(.plain)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: 280)
                    // On top of the stack's own 18pt. The badges are
                    // about the player and the buttons are about what
                    // to do next; without a wider gap than the one
                    // between the buttons themselves, the bottom badge
                    // reads as the first item in the menu.
                    .padding(.bottom, 16)

                    NavigationLink(value: Route.game) {
                        Text("New Game")
                    }
                    .stampButton(primary: true, invite: true)
                    .frame(maxWidth: 280)

                    if showsHowToPlay {
                        Button {
                            showExplainer = true
                        } label: {
                            OutlineLabel(title: "How to Play")
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: 280)
                        .transition(.opacity)
                    }

                    Button {
                        gameCenter.open(.leaderboards, from: .home, hasPlayed: hasPlayed)
                    } label: {
                        OutlineLabel(title: "Leaderboards")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 280)

                    // The quiet row.
                    HStack(spacing: 4) {
                        Button {
                            gameCenter.open(.achievements, from: .home, hasPlayed: hasPlayed)
                        } label: {
                            QuietLabel(icon: "rosette", title: "achievements")
                        }
                        .buttonStyle(.plain)

                        NavigationLink(value: Route.settings) {
                            QuietLabel(icon: "gearshape", title: "settings")
                        }
                    }
                }
                .animation(.easeOut(duration: 0.4), value: standings.standings)
                .animation(.easeOut(duration: 0.3), value: showsHowToPlay)
                .animation(.easeOut(duration: 0.4), value: showsSignInLine)
                // An ask being spent, so it is counted. Fires when the
                // line turns up rather than on every return to the
                // splash, which makes it a floor — see TELEMETRY.md.
                .onChange(of: showsSignInLine, initial: true) { _, shows in
                    guard shows else { return }
                    Telemetry.shared.track("gamecenter_sign_in_shown", props: [
                        "from": GameCenterEntry.Source.home.rawValue,
                    ])
                }
                .animation(.easeOut(duration: 0.4), value: GameCenter.shared.playerName)
                .opacity(actionsVisible ? 1 : 0)
                .offset(y: actionsVisible ? 0 : 12)
                .padding(.top, 28)

                Spacer()

                VStack(spacing: 6) {
                    Text(Credits.linkedOrt("Anti-doom-scrolling soft gaming by @ort."))
                        .font(.avenir(11, weight: .medium, italic: true))
                        .tracking(0.5)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink.opacity(0.6))
                        // Same quiet treatment as the Pixabay credits
                        // below: link colour matches the line it sits in.
                        .tint(Color.ink.opacity(0.6))

                    // Pixabay attribution per their license terms.
                    Text(creditAttributed)
                        .font(.avenir(10, weight: .medium, italic: true))
                        .tracking(0.5)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink.opacity(0.42))
                        // Match link colour to the surrounding text so the
                        // attribution reads as one quiet line, not a row of
                        // highlighted hyperlinks.
                        .tint(Color.ink.opacity(0.42))

                    Text(sfxCreditAttributed)
                        .font(.avenir(10, weight: .medium, italic: true))
                        .tracking(0.5)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.ink.opacity(0.42))
                        .tint(Color.ink.opacity(0.42))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 18)
                .opacity(creditVisible ? 1 : 0)
            }
            .padding(.horizontal, 24)
        }
        .overlay(alignment: .topTrailing) {
            #if DEBUG
            if !ScreenshotMode.isActive {
                SplashDebugMenu(
                    standings: standings,
                    hidesHowToPlay: $debugHidesHowToPlay,
                    onShowWhatsNew: {
                        WhatsNew.shared.debugReset()
                        guard let note = WhatsNew.shared.debugNote() else { return }
                        withAnimation(.easeOut(duration: 0.25)) {
                            whatsNewNote = note
                        }
                    }
                )
            }
            #endif
        }
        // Over everything, including the debug menu: it is the one
        // thing on this screen that has to be dealt with before the
        // screen is, and a modal with a ladybug on top of it is a
        // screenshot waiting to go wrong.
        .overlay {
            if let note = whatsNewNote {
                WhatsNewCard(note: note, reducedMotion: settings.reducedMotion) {
                    withAnimation(.easeOut(duration: 0.25)) { whatsNewNote = nil }
                    Telemetry.shared.track("whats_new_dismissed", props: [
                        "version": note.version,
                    ])
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .sheet(isPresented: $showExplainer) {
            ExplainerView(from: "home", gamesPlayed: stats.gamesPlayed)
        }
        .sheet(item: $shareSubject) { subject in
            ShareCardSheet(subject: subject) {
                gameCenter.open(.leaderboards, from: .home, hasPlayed: hasPlayed)
            }
        }
        .gameCenterEntry(gameCenter)
        .task {
            #if DEBUG
            IconExporter.exportIfNeeded()
            // Capture support: a name the simulator has no account to
            // supply, and the share card opened over the splash.
            if let seeded = ScreenshotMode.playerName {
                GameCenter.shared.debugSetPlayerName(seeded)
            }
            if let seed = ScreenshotMode.shareCardSeed {
                let crowned = seed == .weekly
                    ? standings.weekly.first(where: \.isTop)
                    : standings.allTimeCrown
                if let crowned {
                    shareSubject = ShareCardSubject.from(
                        standing: crowned,
                        name: GameCenter.shared.playerFirstName
                    )
                }
            }
            #endif
            // Once per version, and never over a capture run. The
            // check writes as well as reads, so a second appearance of
            // this screen finds nothing left to show.
            var tellsTheNews = true
            #if DEBUG
            if ScreenshotMode.isActive { tellsTheNews = false }
            #endif
            if tellsTheNews, whatsNewNote == nil,
               let note = WhatsNew.shared.noteOnLaunch(gamesPlayed: stats.gamesPlayed) {
                whatsNewNote = note
                Telemetry.shared.track("whats_new_shown", props: [
                    "version": note.version,
                ])
            }
            // Ranks refresh every time the splash appears, which is
            // also every time a finished game lands back here — so the
            // score just submitted is the one being placed.
            Task { await standings.refresh() }
            AudioPolicy.shared.setInGame(false)
            withAnimation(.easeOut(duration: 0.7)) {
                logoVisible = true
            }
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation(.easeOut(duration: 0.5)) {
                actionsVisible = true
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            withAnimation(.easeOut(duration: 0.6)) {
                creditVisible = true
            }
        }
    }
}

/// The secondary action on the splash: an outlined stamp that carries
/// whichever job the home screen currently has for it.
private struct OutlineLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.avenir(16, weight: .demiBold))
            .textCase(.uppercase)
            .tracking(3)
            .foregroundStyle(Color.ink.opacity(0.75))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 16)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.ink.opacity(0.45), lineWidth: 1.5)
            )
    }
}

/// Where the player sits on one board. Three states, and the gap
/// between them is the point.
///
/// A middling rank is the size of a credit line, because a rank in the
/// middle of a board is a fact, not an achievement. Rank one this week
/// is Top Banana, with a crown. Rank one *all time* is Big Kahuna, in
/// palms — SF Symbols calls them laurels, but at this size and on this
/// beach they read as palm fronds, which is the better joke.
///
/// The weekly crown is winnable by anyone who has a good week; the
/// all-time one means nobody who has ever played has done better. The
/// palms carry that by being wider and taller than the crown rather
/// than by being a grander version of it.
private struct StandingLine: View {
    let standing: BoardStanding
    let reducedMotion: Bool

    /// Drives the Top Banana breath. One flag, flipped once, animated
    /// forever — the glow and the scale read off the same phase so the
    /// pill swells and brightens together rather than beating against
    /// itself.
    @SwiftUI.State private var glowing = false

    /// The crown's own halo, brightest at the top of the breath.
    private var crownGlow: Double { glowing ? 0.75 : 0.35 }

    /// Rank one on a board that never resets. Rarer than the weekly
    /// crown by definition, and dressed accordingly. The rule lives on
    /// the standing, so the share card crowns exactly what this line
    /// crowns.
    private var isKahuna: Bool { standing.isKahuna }

    /// Gold at full strength, not the pale coin cream. `coinGoldLight`
    /// is a highlight colour meant to sit on top of something darker;
    /// alone on the sand it all but disappeared, which is what made
    /// both marks hard to see. `goldMark` is that gold in light mode
    /// and the highlight in dark, where the pill it sits on is dark
    /// enough to swallow a hairline palm frond.
    private var markColor: Color { Color.goldMark }

    /// The capsule behind a crowned title, and nothing at all behind a
    /// plain rank. It wraps the title alone now rather than the title
    /// plus its board phrase, which is what makes it read as a badge.
    @ViewBuilder
    private var pill: some View {
        if standing.isTop {
            Capsule()
                .fill(Color.coinGoldLight.opacity(
                    isKahuna ? (glowing ? 0.44 : 0.28) : (glowing ? 0.30 : 0.18)
                ))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            Color.gold.opacity(glowing ? 0.75 : 0.4),
                            lineWidth: isKahuna ? 1.5 : 1
                        )
                )
                // The halo the pill casts on the sand behind it. Two
                // shadows: a tight one for definition, a wide one that
                // does the breathing.
                .shadow(
                    color: Color.gold.opacity(glowing ? (isKahuna ? 0.6 : 0.45) : 0.12),
                    radius: glowing ? (isKahuna ? 24 : 18) : 8,
                    x: 0, y: 0
                )
                .shadow(color: Color.pearlGlow.opacity(glowing ? 0.5 : 0.2), radius: 4, x: 0, y: 0)
        }
    }

    /// The claim itself. Crowned standings get their title flanked by
    /// a mark on each side — symmetrical, so it reads as a badge and
    /// not as a sentence that happens to start with an icon. A plain
    /// standing is just its rank.
    @ViewBuilder
    private var titleRow: some View {
        if standing.isTop {
            HStack(spacing: isKahuna ? 4 : 7) {
                mark(isKahuna ? "laurel.leading" : "crown.fill")

                Text(standing.crownTitle ?? "")
                    // Both titles at one size. The tier is carried by
                    // the marks around the words, not by the words
                    // being bigger.
                    .font(.avenir(13, weight: .demiBold))
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(Color.ink)
                    // The title never shrinks. It is the whole
                    // message, and a Big Kahuna smaller than a Top
                    // Banana would say the opposite of what it means.
                    .minimumScaleFactor(1)
                    .layoutPriority(1)

                // Both marks come in pairs now. A single crown made
                // the pill lopsided once the board phrase moved out
                // from beside it and the capsule closed up around the
                // title alone.
                mark(isKahuna ? "laurel.trailing" : "crown.fill")
            }
        } else {
            Text(standing.summary)
                .font(.avenir(12, weight: .demiBold, italic: true))
                .tracking(1.5)
                .foregroundStyle(Color.ink.opacity(0.6))
                .monospacedDigit()
        }
    }

    /// Which board the claim is about: "easy · this week", "easy · all
    /// time". Inside the capsule on a crowned standing, so it is a
    /// little darker there than it would be out on the sand — it has
    /// gold behind it rather than open background.
    private var contextText: some View {
        Text(standing.isTop ? standing.crownContextLine : standing.contextLine)
            .font(.avenir(13, weight: .medium, italic: true))
            .tracking(1)
            .foregroundStyle(Color.ink.opacity(standing.isTop ? 0.62 : 0.45))
    }

    /// One mark, sized to its tier. The crown for a week, a palm for
    /// all time.
    private func mark(_ name: String) -> some View {
        Image(systemName: name)
            // The palms are drawn in strokes and the crown as a solid
            // shape, so the same weight does not buy them the same
            // presence. Semibold is what makes a frond hold its own
            // beside a filled crown.
            .font(.system(size: isKahuna ? 17 : 15, weight: isKahuna ? .semibold : .medium))
            .foregroundStyle(markColor)
            .shadow(
                color: Color.coinGoldLight.opacity(crownGlow),
                radius: glowing ? 9 : 5,
                x: 0, y: 0
            )
    }

    var body: some View {
        // Two lines, centred: the claim, then the board it applies to.
        // Previously both ran along one row, which made a crowned
        // standing as wide as the sentence describing it and left the
        // stack reading as a list of ragged strips.
        //
        // On a crowned standing both lines live inside the capsule, so
        // the badge is the whole claim — the title and the board it is
        // a claim about — rather than a title with a caption loose
        // underneath it.
        Group {
            if standing.isTop {
                VStack(spacing: 1) {
                    titleRow
                        // One height for both crowned tiers, so the two
                        // pills are the same object at different
                        // brightness rather than two sizes of badge.
                        // The palms are taller than the crown and would
                        // otherwise stretch their row.
                        .frame(height: 18)
                    contextText
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 18)
                .background { pill }
            } else {
                VStack(spacing: 3) {
                    titleRow
                    contextText
                }
            }
        }
        .lineLimit(1)
        // Longest case is "biggest keep · this week" inside a capsule.
        // Shrinking a little beats wrapping, and the floor is high
        // enough that it never looks like a different type size.
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity)
        // A breath, not a blink: three and a half seconds each way, and
        // the swell is small enough to notice only once the eye has
        // settled on it. Held still entirely when the player has asked
        // for less motion — the gold alone still marks rank one.
        .scaleEffect(standing.isTop && glowing ? 1.035 : 1.0)
        .animation(
            reducedMotion || !standing.isTop
                ? nil
                : .easeInOut(duration: 3.5).repeatForever(autoreverses: true),
            value: glowing
        )
        .onAppear {
            guard standing.isTop, !reducedMotion else { return }
            glowing = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            standing.isTop
                ? "\(standing.crownTitle ?? ""), \(standing.summary), \(standing.boardPhrase)"
                : "\(standing.summary) \(standing.boardPhrase)"
        )
    }
}

/// The quietest tier on the splash: lowercase italic with a hairline
/// icon, for the things a player goes looking for rather than lands on.
private struct QuietLabel: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .light))
            Text(title)
                .font(.avenir(13, weight: .medium, italic: true))
                .tracking(2)
                .textCase(.lowercase)
        }
        .foregroundStyle(Color.ink.opacity(0.5))
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

#if DEBUG
/// The splash's own ladybug. The standing line is the one piece of this
/// screen a simulator can never produce on its own — there is no Game
/// Center account behind it — so the ranks are handed in by hand.
///
/// Same corner and same icon as the in-game menu, and hidden by
/// `-screenshotMode` for the same reason.
private struct SplashDebugMenu: View {
    let standings: StandingsStore
    @Binding var hidesHowToPlay: Bool
    /// Clears the bookkeeping and puts the card straight up, so the
    /// menu shows what it just reset instead of promising it for the
    /// next launch.
    let onShowWhatsNew: () -> Void

    var body: some View {
        Menu {
            Button("Standing: mid-table", systemImage: "list.number") {
                withAnimation { standings.debugSeed(top: false) }
            }
            Button("Standing: Top Banana", systemImage: "crown.fill") {
                withAnimation { standings.debugSeed(top: true) }
            }
            Button("Standing: none", systemImage: "xmark.circle") {
                withAnimation { standings.debugClear() }
            }
            Divider()
            Button("Name: Bram van Oost", systemImage: "person.fill") {
                withAnimation { GameCenter.shared.debugSetPlayerName("Bram van Oost") }
            }
            Button("Name: none", systemImage: "person.slash") {
                withAnimation { GameCenter.shared.debugSetPlayerName(nil) }
            }
            Divider()
            Button(
                hidesHowToPlay ? "Show How to Play" : "Hide How to Play",
                systemImage: hidesHowToPlay ? "eye" : "eye.slash"
            ) {
                withAnimation { hidesHowToPlay.toggle() }
            }
            Divider()
            Button("Reset difficulty nudge", systemImage: "arrow.counterclockwise") {
                DifficultyNudge.shared.debugReset()
                DifficultyNudge.debugForce = false
            }
            Button("Show what's new", systemImage: "sparkles", action: onShowWhatsNew)
        } label: {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 18))
                .foregroundStyle(Color.coral.opacity(0.85))
                .padding(8)
        }
        .accessibilityLabel("Debug menu")
        .padding(.trailing, 16)
        .padding(.top, 16)
    }
}
#endif
