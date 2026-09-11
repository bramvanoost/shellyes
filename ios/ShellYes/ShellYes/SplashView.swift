import SwiftUI

struct SplashView: View {
    let store: GameStore
    let settings: SettingsStore
    let stats: StatsStore

    @SwiftUI.State private var logoVisible: Bool = false
    @SwiftUI.State private var actionsVisible: Bool = false
    @SwiftUI.State private var creditVisible: Bool = false
    @SwiftUI.State private var showExplainer: Bool = false
    @SwiftUI.State private var gameCenter = GameCenterEntry()

    /// False until a game has been finished. It no longer decides
    /// whether the Game Center entries appear — they always do — only
    /// whether tapping one reaches Apple's sheet or our empty one.
    private var hasPlayed: Bool { stats.gamesPlayed > 0 }

    private var creditAttributed: AttributedString {
        let raw = "Background music by [Alfarran Basalim](https://pixabay.com/users/farran_ez-45967570/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=456148) from [Pixabay](https://pixabay.com/?utm_source=link-attribution&utm_medium=referral&utm_campaign=music&utm_content=456148)."
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    private var sfxCreditAttributed: AttributedString {
        let raw = "UI sounds by [cadecomposer](https://github.com/cadecomposer)."
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    var body: some View {
        ZStack {
            Background()

            VStack(spacing: 0) {
                Spacer()

                // Hero medallion — gold coin with a shell engraved on it.
                ShellMedallion(size: 124)
                    .shadow(color: Color.gold.opacity(0.45), radius: 22, x: 0, y: 0)
                    .shadow(color: Color.treasureInk.opacity(0.22), radius: 0, x: 0, y: 6)
                    .opacity(logoVisible ? 1 : 0)
                    .scaleEffect(logoVisible ? 1 : 0.85)
                    .padding(.bottom, 18)

                // Wordmark — Optima at semibold for a humanist, beachy feel.
                // Uniform ink, no accent letter; tracking is light so the
                // two words read as one wordmark.
                Text("Shell Yes")
                    .font(.custom("Optima", size: 64).weight(.semibold))
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
                    NavigationLink(value: Route.game) {
                        Text("New Game")
                    }
                    .stampButton(primary: true, invite: true)
                    .frame(maxWidth: 280)

                    Button {
                        showExplainer = true
                    } label: {
                        OutlineLabel(title: "How to Play")
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: 280)

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
                .opacity(actionsVisible ? 1 : 0)
                .offset(y: actionsVisible ? 0 : 12)
                .padding(.top, 36)

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
        .navigationBarHidden(true)
        .sheet(isPresented: $showExplainer) {
            ExplainerView()
        }
        .gameCenterEntry(gameCenter)
        .task {
            #if DEBUG
            IconExporter.exportIfNeeded()
            #endif
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
