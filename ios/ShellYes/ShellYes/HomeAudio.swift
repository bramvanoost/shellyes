import Foundation
import AVFoundation

/// Looping home-screen music. Singleton so SplashView, GameView, and
/// SettingsView can all reach it through AudioPolicy without owning
/// instances themselves.
@MainActor
final class HomeAudio {
    static let shared = HomeAudio()

    private var player: AVAudioPlayer?
    private let resourceName = "farran_ez-minimal-piano-underscore-456148"

    private init() {}

    /// Idempotent — only spins up an AVAudioPlayer the first time, and
    /// resumes playback if a previous `stop(fade:)` paused it.
    func startIfNeeded() {
        if let existing = player {
            if !existing.isPlaying { existing.play() }
            return
        }
        let url = Bundle.main.url(forResource: resourceName, withExtension: "mp3")
              ?? Bundle.main.url(forResource: resourceName, withExtension: "m4a")
        guard let url else { return }
        // Session category/activation lives in AudioPolicy.configureSession(),
        // called once at launch. Don't set it here: SFX need the same
        // session even when the home music never starts.
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.numberOfLoops = -1
            p.volume = 0.55
            p.prepareToPlay()
            p.play()
            player = p
        } catch {
            // Silent fail — no music is better than a crash.
        }
    }

    func setVolume(_ volume: Float, fade: TimeInterval = 0.5) {
        player?.setVolume(volume, fadeDuration: fade)
    }

    func stop(fade: TimeInterval = 0.4) {
        guard let p = player else { return }
        if fade <= 0 {
            p.stop()
            player = nil
            return
        }
        p.setVolume(0, fadeDuration: fade)
        let deadline = DispatchTime.now() + fade + 0.05
        DispatchQueue.main.asyncAfter(deadline: deadline) { [weak self] in
            guard let self else { return }
            self.player?.stop()
            self.player = nil
        }
    }
}
