import Foundation
import AVFoundation

/// Short one-shot game sound effects. Shared singleton; each clip is
/// pre-loaded as a small pool of AVAudioPlayer instances so overlapping
/// triggers don't cut each other off.
@MainActor
final class GameSFX {
    static let shared = GameSFX()

    private var rollPool: [AVAudioPlayer] = []
    private var confirmPool: [AVAudioPlayer] = []
    private var bankPool: [AVAudioPlayer] = []
    private var bustPool: [AVAudioPlayer] = []
    private var countPool: [AVAudioPlayer] = []
    private var winnerPool: [AVAudioPlayer] = []
    private var rivalWinPool: [AVAudioPlayer] = []
    private var aiPlayingPool: [AVAudioPlayer] = []
    private var aiClaimPool: [AVAudioPlayer] = []
    private var playerLossPool: [AVAudioPlayer] = []
    private var nextRollIdx = 0
    private var nextConfirmIdx = 0
    private var nextBankIdx = 0
    private var nextBustIdx = 0
    private var nextCountIdx = 0
    private var nextAIPlayingIdx = 0
    private var nextAIClaimIdx = 0
    private var nextPlayerLossIdx = 0
    private var aiPlayingTask: Task<Void, Never>? = nil
    private var endMusicFadeTask: Task<Void, Never>? = nil
    /// Nominal volumes for the two end-of-game stings. Kept as
    /// constants because `stopEndMusic` fades the players to zero and
    /// has to put them back before they're reused next game.
    private static let winnerVolume: Float = 0.85
    private static let rivalWinVolume: Float = 0.75

    /// Irregular cluster of inter-blip gaps (ms) for the AI-playing
    /// pattern. Mix of short bursts and longer pauses so it reads as
    /// "pondering", not a metronome. ~3.6s before the cycle repeats.
    private static let aiClusterIntervalsMs: [UInt64] = [120, 580, 180, 540, 250, 460, 140, 620, 200, 510]

    private init() {
        // The roll tick fires on every animation frame (~12/s during a
        // roll), so preload enough copies that overlapping plays don't
        // cut each other off.
        load("dice_picking", into: &rollPool, copies: 6, volume: 0.6)
        load("dice_confirm", into: &confirmPool, copies: 2, volume: 0.7)
        load("outcome-success", into: &bankPool, copies: 2, volume: 0.7)
        load("outcome-failure", into: &bustPool, copies: 2, volume: 0.75)
        // Counting ceremony: full count clip fires per pearl during the
        // tally. Pool sized for overlap at the fastest tick spacing
        // (~40ms) given the clip's full tail.
        load("count", into: &countPool, copies: 16, volume: 0.55)
        load("winner", into: &winnerPool, copies: 1, volume: Self.winnerVolume)
        load("otherwins", into: &rivalWinPool, copies: 1, volume: Self.rivalWinVolume)
        // AI-playing blip: ~480ms clip, cluster intervals as low as
        // 120ms, so size the pool for several overlaps.
        load("aiplaying", into: &aiPlayingPool, copies: 6, volume: 0.45)
        // Short confirm tone when an AI claims a shell from the beach,
        // played after the quiet-AI blip pattern stops and before the
        // banner appears. Two copies cover back-to-back turn ends.
        load("aiclaimsshell", into: &aiClaimPool, copies: 2, volume: 0.7)
        // Sting when an AI steals a shell from the human seat.
        load("playerlosesshell", into: &playerLossPool, copies: 2, volume: 0.75)
    }

    private func load(_ name: String, into pool: inout [AVAudioPlayer], copies: Int, volume: Float) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "m4a") else { return }
        for _ in 0..<copies {
            guard let p = try? AVAudioPlayer(contentsOf: url) else { continue }
            p.volume = volume
            p.prepareToPlay()
            pool.append(p)
        }
    }

    func playRoll() {
        play(from: &rollPool, cursor: &nextRollIdx)
    }

    func playConfirm() {
        play(from: &confirmPool, cursor: &nextConfirmIdx)
    }

    func playBank() {
        play(from: &bankPool, cursor: &nextBankIdx)
    }

    func playBust() {
        play(from: &bustPool, cursor: &nextBustIdx)
    }

    func playCount() {
        play(from: &countPool, cursor: &nextCountIdx)
    }

    func playCountTick() {
        play(from: &countPool, cursor: &nextCountIdx)
    }

    func playAIClaim() {
        play(from: &aiClaimPool, cursor: &nextAIClaimIdx)
    }

    func playPlayerShellLoss() {
        play(from: &playerLossPool, cursor: &nextPlayerLossIdx)
    }

    func playWinFanfare() {
        cancelEndMusicFade()
        winnerPool.first?.volume = Self.winnerVolume
        playSingle(winnerPool.first)
    }

    func playRivalWin() {
        cancelEndMusicFade()
        rivalWinPool.first?.volume = Self.rivalWinVolume
        playSingle(rivalWinPool.first)
    }

    /// Fades out whichever end-of-game sting is playing. Leaving the
    /// fanfare running under a fresh board (or under the splash) makes
    /// the previous game bleed into the next one, so both exits from
    /// the tally screen call this. Volume is restored afterwards
    /// because the pool players are reused for the next game.
    func stopEndMusic(fade: TimeInterval = 0.45) {
        cancelEndMusicFade()
        let fading = endMusicPlayers.filter { $0.player.isPlaying }
        guard !fading.isEmpty else { return }
        for entry in fading {
            entry.player.setVolume(0, fadeDuration: fade)
        }
        endMusicFadeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((fade + 0.05) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            for entry in fading {
                entry.player.stop()
                entry.player.currentTime = 0
                entry.player.volume = entry.volume
            }
        }
    }

    /// Ends any in-flight fade and puts the stings back at full volume,
    /// so a cancelled fade can't leave the next game's fanfare silent.
    private func cancelEndMusicFade() {
        guard endMusicFadeTask != nil else { return }
        endMusicFadeTask?.cancel()
        endMusicFadeTask = nil
        for entry in endMusicPlayers {
            entry.player.stop()
            entry.player.currentTime = 0
            entry.player.volume = entry.volume
        }
    }

    private var endMusicPlayers: [(player: AVAudioPlayer, volume: Float)] {
        var out: [(AVAudioPlayer, Float)] = []
        if let p = winnerPool.first { out.append((p, Self.winnerVolume)) }
        if let p = rivalWinPool.first { out.append((p, Self.rivalWinVolume)) }
        return out
    }

    /// Begins the irregular AI-playing blip pattern. Idempotent —
    /// re-calling stops the prior task before starting a fresh one.
    func startAIPlayingPattern() {
        stopAIPlayingPattern()
        guard AudioPolicy.shared.sfxEnabled else { return }
        aiPlayingTask = Task { @MainActor [weak self] in
            var step = 0
            while !Task.isCancelled {
                guard let self else { return }
                self.play(from: &self.aiPlayingPool, cursor: &self.nextAIPlayingIdx)
                let gapMs = Self.aiClusterIntervalsMs[step % Self.aiClusterIntervalsMs.count]
                step += 1
                try? await Task.sleep(nanoseconds: gapMs * 1_000_000)
            }
        }
    }

    func stopAIPlayingPattern() {
        aiPlayingTask?.cancel()
        aiPlayingTask = nil
    }

    private func playSingle(_ player: AVAudioPlayer?) {
        guard AudioPolicy.shared.sfxEnabled, let player else { return }
        player.currentTime = 0
        player.play()
    }

    private func play(from pool: inout [AVAudioPlayer], cursor: inout Int) {
        guard AudioPolicy.shared.sfxEnabled, !pool.isEmpty else { return }
        let p = pool[cursor % pool.count]
        cursor += 1
        p.currentTime = 0
        p.play()
    }
}
