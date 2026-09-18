import SwiftUI

@main
struct ShellYesApp: App {
    @SwiftUI.State private var settings: SettingsStore
    @SwiftUI.State private var store: GameStore
    @SwiftUI.State private var stats: StatsStore
    @SwiftUI.State private var standings: StandingsStore
    @SwiftUI.State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    @SwiftUI.State private var sessionStart: Date?

    init() {
        let s = SettingsStore()
        _settings = .init(initialValue: s)
        let st = StatsStore()
        _stats = .init(initialValue: st)
        _store = .init(initialValue: GameStore(settings: s, stats: st))
        // Last known ranks load from the cache here so the splash can
        // draw the standing on its first frame; the live refresh
        // happens when that screen appears.
        _standings = .init(initialValue: StandingsStore())
        // Before any player exists, so SFX and music share one
        // `.playback` session that ignores the ringer switch.
        AudioPolicy.shared.configureSession()
        // Self-hosted Aptabase at aptabase.fastronaut.com. App key
        // is a public identifier (like a Stripe publishable key);
        // safe to ship in the binary.
        Telemetry.shared.initialize(appKey: "A-SH-7882093279")
        // A game still running when the app went away is a game the
        // player walked out of, and it is charged as a loss here — on
        // this launch, before the splash, the boards or the
        // achievements read the stats, so they all see the corrected
        // streak rather than a stale one. See `AbandonGuard`.
        //
        // After `Telemetry.initialize`, or the event below would be
        // raised against a client that doesn't exist yet and dropped.
        // Before `GameCenter.authenticate`, so the backfill and the
        // rank refresh that follow a successful sign-in are reading
        // stats that already include this loss.
        if let abandoned = AbandonGuard.shared.armedGame {
            st.recordAbandonedGame(
                difficulty: abandoned.difficulty,
                pace: abandoned.pace
            )
            AbandonGuard.shared.disarm()
            Telemetry.shared.track("game_abandoned_on_quit", props: [
                "difficulty": abandoned.difficulty,
                "pace": abandoned.pace,
            ])
        }
        // Silent: if the player isn't signed in, GameKit hands us a
        // sheet and we hold it until they tap Leaderboards themselves.
        GameCenter.shared.authenticate()
    }

    var body: some Scene {
        WindowGroup {
            // iPad gets the phone layout scaled to its window rather
            // than a stretched one. See `PhoneCanvas`.
            PhoneCanvas {
                NavigationStack(path: $path) {
                    SplashView(
                        store: store,
                        settings: settings,
                        stats: stats,
                        standings: standings
                    )
                        .navigationDestination(for: Route.self) { route in
                            switch route {
                            case .game:
                                GameView(store: store, settings: settings, stats: stats)
                                    .onAppear {
                                        AudioPolicy.shared.setInGame(true)
                                    }
                                    .onDisappear {
                                        AudioPolicy.shared.setInGame(false)
                                    }
                            case .settings:
                                SettingsView(
                                    settings: settings,
                                    stats: stats,
                                    onNewGame: {
                                        store.newGame()
                                        // Settings sits on top of the game
                                        // screen, so dismissing lands back on
                                        // a GameView that never re-runs its
                                        // task. Without this the restart is
                                        // the one start that goes unrecorded.
                                        Telemetry.shared.track("game_started", props: [
                                            "from": "settings",
                                            "difficulty": settings.difficulty.rawValue,
                                            "pace": settings.gameSpeed.rawValue,
                                            "quiet_ai": settings.quietAITurns,
                                            "games_played": stats.gamesPlayed,
                                        ])
                                    }
                                )
                            case .stats:
                                StatsView(stats: stats)
                            }
                        }
                }
                // Home action: reset any in-progress game and pop the
                // entire nav stack back to the splash. Injected via the
                // environment so any deeper view (Settings, etc.) can
                // request "go home" without threading a closure through
                // every intermediate view.
                .environment(\.goHome, GoHomeAction {
                    store.newGame()
                    path = NavigationPath()
                })
                // Drain the stack before pushing, so tapping New Game from
                // a sheet deep in Settings lands on one game screen rather
                // than one stacked on top of the settings it came from.
                .environment(\.startGame, StartGameAction {
                    path = NavigationPath()
                    path.append(Route.game)
                })
                #if DEBUG
                .task {
                    if AchievementArtExporter.isRequestedByLaunchArgument {
                        AchievementArtExporter.exportAll()
                    }
                }
                #endif
                .preferredColorScheme(settings.colorMode.preferredScheme)
                // Lifecycle telemetry — fires regardless of whether the
                // user does anything in-game, so app_opened captures even
                // splash-bounces. Pairs with app_closed (with foreground
                // duration) on backgrounding.
                //
                // `scenePhase` can bounce `.active → .inactive → .active`
                // in a quick flurry during simulator lock or some real
                // device transitions, which would spam duplicate
                // app_opened events and clobber `sessionStart` (making
                // the next app_closed's duration_seconds drop to 0). We
                // debounce: ignore any `.active` that fires within 2s of
                // the previous one.
                // The catch-up cannot wait for `.active` alone. GameKit
                // answers its authenticate handler asynchronously, and on a
                // cold launch it is still unanswered when the scene turns
                // active — so the call below no-ops on the guard and the
                // backfill does not happen until the player backgrounds the
                // app and comes back. Nothing is lost when that happens
                // (`didBackfill` is only written after a real run), but a
                // player who updates, opens the app and looks straight at
                // Achievements sees an empty screen they had earned.
                //
                // Watching the flag covers the other order too: when auth
                // lands first, `.active` still fires and finds the guard
                // already satisfied. Both paths are idempotent.
                .onChange(of: GameCenter.shared.isAuthenticated) { _, signedIn in
                    guard signedIn else { return }
                    GameCenter.shared.backfillIfNeeded(from: stats)
                    // Ranks need the same hook, for the same reason. The
                    // splash asks for them from its `.task`, which on a
                    // cold launch runs while GameKit is still deciding who
                    // the player is — so `loadStandings` returns nothing on
                    // its `isAuthenticated` guard, and `.task` never fires
                    // again to ask a second time. A signed-in player was
                    // left looking at a splash with no rank on it until
                    // they backgrounded the app and came back.
                    //
                    // Ordered after the backfill deliberately: that call
                    // is what puts a lapsed player's history onto the
                    // boards, and this one is what reads a rank back off
                    // them.
                    Task { await standings.refresh() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        // Audio recovery runs BEFORE the telemetry debounce
                        // below. Interruptions (calls, Siri) and the screen
                        // locking mid-game leave the session deactivated and
                        // our players paused, and a lock/unlock is exactly
                        // the kind of transition that trips the 2s bounce
                        // guard — so restoring sound behind that `return`
                        // meant sound never came back.
                        AudioPolicy.shared.configureSession()
                        AudioPolicy.shared.refresh()
                        let now = Date()
                        if let start = sessionStart, now.timeIntervalSince(start) < 2 {
                            // Bounced active — same session, drop the
                            // duplicate event, keep the original start.
                            return
                        }
                        sessionStart = now
                        Telemetry.shared.track("app_opened")
                        // One-time catch-up for players who had a history
                        // before Game Center existed. No-ops if unsigned or
                        // already done.
                        GameCenter.shared.backfillIfNeeded(from: stats)
                    case .background:
                        let seconds = sessionStart.map { Int(Date().timeIntervalSince($0)) } ?? 0
                        Telemetry.shared.track("app_closed", props: [
                            "duration_seconds": seconds,
                        ])
                        sessionStart = nil
                    default:
                        break
                    }
                }
            }
        }
    }
}

/// Value-based navigation routes. Value-pushing onto the
/// NavigationStack path lets `goHome` actually drain the stack;
/// destination-pushing NavigationLinks don't update the path so
/// resetting it would leave them stuck.
enum Route: Hashable {
    case game
    case settings
    case stats
}

/// Closure-wrapped environment value. Wrapped in a struct so it
/// conforms to `Equatable`/identifiable for SwiftUI's environment
/// machinery without callers having to compare closure references.
struct GoHomeAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct GoHomeKey: EnvironmentKey {
    static let defaultValue = GoHomeAction(action: {})
}

extension EnvironmentValues {
    var goHome: GoHomeAction {
        get { self[GoHomeKey.self] }
        set { self[GoHomeKey.self] = newValue }
    }
}

/// The mirror of `goHome`: pushes the game onto the nav path from
/// anywhere. Needed because a sheet can't hold a `NavigationLink` into
/// the stack that presents it, and the empty Game Center sheet offers
/// New Game from both the splash and Settings.
struct StartGameAction {
    let action: () -> Void
    func callAsFunction() { action() }
}

private struct StartGameKey: EnvironmentKey {
    static let defaultValue = StartGameAction(action: {})
}

extension EnvironmentValues {
    var startGame: StartGameAction {
        get { self[StartGameKey.self] }
        set { self[StartGameKey.self] = newValue }
    }
}
