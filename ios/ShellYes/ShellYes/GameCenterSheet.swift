import SwiftUI
import GameKit
import Observation

/// Apple's own Game Center screen, wrapped for SwiftUI. Its look is
/// Apple's and can't be themed, which is exactly why it lives behind a
/// deliberate tap in Settings rather than on any screen we designed.
struct GameCenterSheet: UIViewControllerRepresentable {
    /// Identifiable so `.sheet(item:)` can drive it — one optional
    /// instead of a bool per pane.
    enum Pane: Identifiable {
        case leaderboards
        case achievements

        var id: Self { self }

        /// Stable name for telemetry, so a rename of the case can't
        /// silently split the event in the dashboard.
        var analyticsName: String {
            switch self {
            case .leaderboards: return "leaderboards"
            case .achievements: return "achievements"
            }
        }

        var state: GKGameCenterViewControllerState {
            switch self {
            case .leaderboards: return .leaderboards
            case .achievements: return .achievements
            }
        }
    }

    let pane: Pane
    var onClose: () -> Void

    func makeUIViewController(context: Context) -> GKGameCenterViewController {
        let vc = GKGameCenterViewController(state: pane.state)
        vc.gameCenterDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: GKGameCenterViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    final class Coordinator: NSObject, GKGameCenterControllerDelegate {
        private let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }

        func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
            onClose()
        }
    }
}

/// Shared state for the two Game Center entry points (home screen and
/// Settings). Holding it in one place keeps the "what happens when the
/// player isn't signed in" decision in one place too, instead of once
/// per screen.
@MainActor
@Observable
final class GameCenterEntry {
    /// Which pane is showing, if any. Drives `.sheet(item:)`.
    var pane: GameCenterSheet.Pane?

    /// Set when there is nothing at all we can show: not signed in and
    /// GameKit never handed us a sign-in sheet, which is what happens
    /// when Game Center is switched off for the device or the account
    /// is unreachable. Without this the row is a dead tap.
    var showsUnavailableAlert = false

    /// Where the tap came from, for telemetry.
    enum Source: String {
        case home
        case settings
    }

    func open(_ pane: GameCenterSheet.Pane, from source: Source) {
        let outcome: String
        if GameCenter.shared.isAuthenticated {
            self.pane = pane
            outcome = "opened"
        } else if GameCenter.shared.presentSignInFromKeyWindow() {
            outcome = "sign_in"
        } else {
            showsUnavailableAlert = true
            outcome = "unavailable"
        }
        Telemetry.shared.track("gamecenter_opened", props: [
            "pane": pane.analyticsName,
            "from": source.rawValue,
            "outcome": outcome,
        ])
    }
}

extension View {
    /// Attaches the Game Center sheet and its unavailable alert to any
    /// screen that offers an entry point.
    func gameCenterEntry(_ entry: GameCenterEntry) -> some View {
        self
            .sheet(item: Binding(get: { entry.pane }, set: { entry.pane = $0 })) { pane in
                GameCenterSheet(pane: pane) { entry.pane = nil }
                    .ignoresSafeArea()
            }
            .alert(
                "Game Center is off",
                isPresented: Binding(
                    get: { entry.showsUnavailableAlert },
                    set: { entry.showsUnavailableAlert = $0 }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Turn Game Center on in the Settings app to see boards and badges.")
            }
    }
}
