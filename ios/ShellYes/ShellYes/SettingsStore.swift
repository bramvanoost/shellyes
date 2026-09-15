import Foundation
import Observation
import SwiftUI

enum ColorMode: String, Codable, CaseIterable {
    case system, light, dark

    var preferredScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum SoundMode: String, Codable, CaseIterable {
    case all      // music + game SFX
    case gameOnly // SFX only, home music silent
    case muted    // silent everywhere
}

enum GameSpeed: String, Codable, CaseIterable {
    case slow
    case fast

    /// Multiplier on per-action delays. fast = 1.0 (current pace), slow
    /// stretches dice rolls + AI moves + pick confirmations.
    var factor: Double {
        switch self {
        case .slow: return 1.7
        case .fast: return 1.0
        }
    }
}

@MainActor
@Observable
final class SettingsStore {
    private static let difficultyKey = "ching.difficulty"
    private static let colorModeKey = "ching.colorMode"
    private static let reducedMotionKey = "ching.reducedMotion"
    private static let soundModeKey = "ching.soundMode"
    private static let gameSpeedKey = "ching.gameSpeed"
    private static let quietAITurnsKey = "ching.quietAITurns"
    private static let autoContinueKey = "ching.autoContinue"
    /// Tracks whether the user has been opted-in to a default yet. New
    /// installs land on quietAITurns = true (Tine-shaped audience).
    /// Existing players upgrading keep quietAITurns = false so the
    /// behavior they've been seeing doesn't silently change underneath
    /// them — they can still flip the toggle on in Settings.
    private static let quietAITurnsSeenKey = "ching.quietAITurnsSeen"

    var difficulty: Difficulty {
        didSet {
            UserDefaults.standard.set(difficulty.rawValue, forKey: Self.difficultyKey)
        }
    }

    var colorMode: ColorMode {
        didSet {
            UserDefaults.standard.set(colorMode.rawValue, forKey: Self.colorModeKey)
        }
    }

    var reducedMotion: Bool {
        didSet {
            UserDefaults.standard.set(reducedMotion, forKey: Self.reducedMotionKey)
        }
    }

    var soundMode: SoundMode {
        didSet {
            UserDefaults.standard.set(soundMode.rawValue, forKey: Self.soundModeKey)
            AudioPolicy.shared.applySoundMode(soundMode)
        }
    }

    var gameSpeed: GameSpeed {
        didSet {
            UserDefaults.standard.set(gameSpeed.rawValue, forKey: Self.gameSpeedKey)
        }
    }

    var quietAITurns: Bool {
        didSet {
            UserDefaults.standard.set(quietAITurns, forKey: Self.quietAITurnsKey)
        }
    }

    /// Lets an AI seat's outcome banner dismiss itself, so a round of
    /// bot turns plays out without the player tapping through it. Off
    /// by default: tapping is how the game has always read, and a
    /// banner that leaves on its own is a thing to opt into rather
    /// than to discover mid-game.
    var autoContinue: Bool {
        didSet {
            UserDefaults.standard.set(autoContinue, forKey: Self.autoContinueKey)
        }
    }

    init() {
        let rawDiff = UserDefaults.standard.string(forKey: Self.difficultyKey) ?? ""
        // Fresh installs open on Easy so a first game can't feel
        // punishing. Only the fallback changes: anyone who has already
        // picked a difficulty has the key written and keeps their
        // choice. The Easy leaderboard is the default board in Game
        // Center for the same reason.
        self.difficulty = Difficulty(rawValue: rawDiff) ?? .easy

        let rawMode = UserDefaults.standard.string(forKey: Self.colorModeKey) ?? ""
        self.colorMode = ColorMode(rawValue: rawMode) ?? .system

        self.reducedMotion = UserDefaults.standard.bool(forKey: Self.reducedMotionKey)

        let rawSound = UserDefaults.standard.string(forKey: Self.soundModeKey) ?? ""
        self.soundMode = SoundMode(rawValue: rawSound) ?? .all

        let rawSpeed = UserDefaults.standard.string(forKey: Self.gameSpeedKey) ?? ""
        self.gameSpeed = GameSpeed(rawValue: rawSpeed) ?? .slow

        // First-launch default for quiet AI turns: ON for fresh installs,
        // OFF for anyone who already played the noisy version. The
        // `seen` flag is what distinguishes them; once written, both
        // populations track their own preference.
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.quietAITurnsSeenKey) == nil {
            let isFreshInstall = defaults.object(forKey: Self.difficultyKey) == nil
                && defaults.object(forKey: Self.gameSpeedKey) == nil
                && defaults.object(forKey: Self.soundModeKey) == nil
            defaults.set(isFreshInstall, forKey: Self.quietAITurnsKey)
            defaults.set(true, forKey: Self.quietAITurnsSeenKey)
        }
        self.quietAITurns = defaults.bool(forKey: Self.quietAITurnsKey)

        // No fresh-install split here, unlike quiet turns: off for
        // everybody until they ask for it.
        self.autoContinue = defaults.bool(forKey: Self.autoContinueKey)

        AudioPolicy.shared.applySoundMode(soundMode)
    }
}
