import Foundation
import AVFoundation

/// Single source of truth for "should anything play right now?".
/// SettingsStore feeds it the user's sound preference, and the views
/// tell it whether we're currently in the game vs on the splash so
/// the home music ducks while the game is on screen.
@MainActor
final class AudioPolicy {
    static let shared = AudioPolicy()

    private(set) var soundMode: SoundMode = .all
    private(set) var inGame: Bool = false

    private init() {}

    /// Configures the one shared audio session for the whole app.
    ///
    /// `.playback` is deliberate: it is the category that IGNORES the
    /// ringer/silent switch, so a player who lives on mute (most of
    /// them) still hears the game and the hardware volume buttons are
    /// the only thing that decides loudness. `.ambient` — what we used
    /// before — obeys the switch, which meant muted phones got silence
    /// and volume-up only moved the ringer.
    ///
    /// `.mixWithOthers` keeps someone's podcast or music alive
    /// underneath us; we never want to be the app that stops playback.
    ///
    /// Owned here rather than in HomeAudio because SFX must work in
    /// `.gameOnly` mode, where HomeAudio never starts at all.
    func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // Silent fail — muted game beats a crash on launch.
        }
    }

    func applySoundMode(_ mode: SoundMode) {
        soundMode = mode
        apply()
    }

    func setInGame(_ value: Bool) {
        guard inGame != value else { return }
        inGame = value
        apply()
    }

    /// SFX (rolls, picks, banks, busts) are silent only when fully muted.
    var sfxEnabled: Bool { soundMode != .muted }

    private func apply() {
        switch soundMode {
        case .muted, .gameOnly:
            HomeAudio.shared.stop(fade: 0.4)
        case .all:
            HomeAudio.shared.startIfNeeded()
            HomeAudio.shared.setVolume(inGame ? 0.15 : 0.55, fade: 0.6)
        }
    }
}
