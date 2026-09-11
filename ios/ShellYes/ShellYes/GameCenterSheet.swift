import SwiftUI
import GameKit

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
