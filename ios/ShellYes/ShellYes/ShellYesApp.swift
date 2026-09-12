import SwiftUI

@main
struct ShellYesApp: App {
    @SwiftUI.State private var settings: SettingsStore
    @SwiftUI.State private var store: GameStore
    @SwiftUI.State private var stats: StatsStore
    @SwiftUI.State private var path = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    @SwiftUI.State private var sessionStart: Date?

    init() {
        let s = SettingsStore()
        _settings = .init(initialValue: s)
        _store = .init(initialValue: GameStore(settings: s))
        _stats = .init(initialValue: StatsStore())
        // Before any player exists, so SFX and music share one
        // `.playback` session that ignores the ringer switch.
        AudioPolicy.shared.configureSession()
        // Self-hosted Aptabase at aptabase.fastronaut.com. App key
        // is a public identifier (like a Stripe publishable key);
        // safe to ship in the binary.
        Telemetry.shared.initialize(appKey: "A-SH-7882093279")
        // Silent: if the player isn't signed in, GameKit hands us a
        // sheet and we hold it until they tap Leaderboards themselves.
        GameCenter.shared.authenticate()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: $path) {
                SplashView(store: store, settings: settings, stats: stats)
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
                                onNewGame: { store.newGame() }
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
