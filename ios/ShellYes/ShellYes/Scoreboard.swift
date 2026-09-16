import SwiftUI
import ShellYesEngine

struct Scoreboard: View {
    let players: [Player]
    let scores: [Int]
    let current: Int
    var revealed: Bool = true
    var stolenFrom: Int? = nil

    /// One trigger per seat. Increments when that seat becomes the active
    /// player; the column overlays a sparkle burst keyed off this value.
    /// Used to make AI turns visually obvious — "Jones is up" reads as a
    /// little firework over their tile instead of just a wordmark change.
    @SwiftUI.State private var activeSparkleTriggers: [Int: Int] = [:]

    /// One trigger per seat. Increments when this seat just had a shell
    /// stolen — a SmokePoof fires over their vault so the loss reads as
    /// "*poof*, gone" rather than the top tile silently fading out.
    @SwiftUI.State private var poofTriggers: [Int: Int] = [:]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(players.indices, id: \.self) { i in
                column(playerIndex: i)
                    .frame(maxWidth: .infinity)
                    .opacity(revealed ? 1 : 0)
                    .offset(y: revealed ? 0 : 24)
                    .animation(
                        .spring(response: 0.55, dampingFraction: 0.78).delay(Double(i) * 0.12),
                        value: revealed
                    )
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: current) { _, newCurrent in
            // Only sparkle for non-human seats — the human knows it's their
            // turn from the action bar. The AI turn cue is what's missing.
            guard newCurrent != GameStore.humanSeat else { return }
            let t = (activeSparkleTriggers[newCurrent] ?? 0) + 1
            activeSparkleTriggers[newCurrent] = t
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                if activeSparkleTriggers[newCurrent] == t {
                    activeSparkleTriggers[newCurrent] = 0
                }
            }
        }
        .onChange(of: stolenFrom) { _, newStolen in
            guard let victim = newStolen else { return }
            let t = (poofTriggers[victim] ?? 0) + 1
            poofTriggers[victim] = t
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 900_000_000)
                if poofTriggers[victim] == t {
                    poofTriggers[victim] = 0
                }
            }
        }
    }

    @ViewBuilder
    private func column(playerIndex i: Int) -> some View {
        let isActive = i == current
        let isStolen = stolenFrom == i
        VStack(spacing: 8) {
            Text(players[i].id.capitalized)
                .font(.avenir(14, weight: isActive ? .demiBold : .medium))
                .foregroundStyle(Color.ink)

            // Always reserve the vault area height so columns don't jump.
            // `alignment: .top` on the ZStack anchors children at the top
            // of the slot — without it, when VaultStack shrinks (losing a
            // shell) SwiftUI re-centres the smaller frame and the stack
            // appears to slide downward before settling.
            //
            // Placeholder + VaultStack are layered (not if/else swapped)
            // so VaultStack's view identity persists across the empty →
            // non-empty boundary; otherwise the first stolen tile lands
            // in a freshly-created stack and skips both the scale-in
            // transition and the addSparkle onChange.
            ZStack(alignment: .top) {
                safePlaceholder()
                    .opacity(players[i].tiles.isEmpty ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: players[i].tiles.isEmpty)

                VaultStack(safes: players[i].tiles, activeSeat: isActive)

                // Steal poof — fires over the vault when this seat lost a
                // shell. Sized to the shell footprint so the burst centres
                // on the disappearing top tile rather than the column.
                if let trigger = poofTriggers[i], trigger > 0 {
                    SmokePoof()
                        .frame(width: 40, height: 40)
                        .id(trigger)
                }
            }
            .frame(height: 54, alignment: .top)

            Text(players[i].tiles.isEmpty ? "0 shells" : "\(players[i].tiles.count) shell\(players[i].tiles.count == 1 ? "" : "s")")
                .font(.avenir(10, weight: .medium, italic: true))
                .tracking(1)
                .foregroundStyle(Color.ink.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.vertical, 12)
        .padding(.horizontal, 6)
        // The active card is gently lit: warm gold fill, softer gold
        // border, modest scale + lift below. Shadow alone got eaten by
        // the light pastel sky, but breathing reads as anxious — kept
        // steady so it's a quiet "you're up" rather than a heartbeat.
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    isStolen ? Color.coral.opacity(0.45) :
                    isActive ? Color.coinGoldLight.opacity(0.40) :
                    Color.white.opacity(0.18)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    isStolen ? Color.coral :
                    isActive ? Color.gold.opacity(0.7) :
                    Color.ink.opacity(0.15),
                    lineWidth: isStolen ? 2.5 : (isActive ? 1.5 : 1)
                )
        )
        // Active player's card gets a layered warm-gold breathing halo.
        // Two shadows: the outer amber gives the active cue contrast
        // against the light pastel sky (coinGoldLight alone got washed
        // out), the inner cream gives it a hot core so it reads as lit,
        // not just shadowed. Coral stays reserved for the steal flash so
        // the two cues never collide.
        .shadow(
            color: {
                if isStolen { return Color.coral.opacity(0.75) }
                if isActive { return Color.gold.opacity(0.45) }
                return .clear
            }(),
            radius: {
                if isStolen { return 18 }
                if isActive { return 22 }
                return 12
            }(),
            x: 0, y: 0
        )
        .shadow(
            color: isActive ? Color.coinGoldLight.opacity(0.55) : .clear,
            radius: isActive ? 8 : 0,
            x: 0, y: 0
        )
        .overlay {
            if let trigger = activeSparkleTriggers[i], trigger > 0 {
                SparkleField(count: 40, startRadius: 36, spread: 75, duration: 1.2)
                    .id(trigger)
                    .allowsHitTesting(false)
            }
        }
        .scaleEffect(isStolen ? 1.04 : (isActive ? 1.03 : 1.0))
        .offset(y: isActive && !isStolen ? -2 : 0)
        .overlay(alignment: .top) {
            if isStolen {
                Text("taken.")
                    .font(.avenir(13, weight: .demiBold, italic: true))
                    .tracking(2)
                    .textCase(.lowercase)
                    .foregroundStyle(Color.coral)
                    .shadow(color: Color.paper.opacity(0.8), radius: 3, x: 0, y: 0)
                    .offset(y: -16)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .zIndex(isActive || isStolen ? 1 : 0)
        .animation(.spring(response: 0.35, dampingFraction: 0.65), value: isStolen)
        .animation(.spring(response: 0.45, dampingFraction: 0.75), value: isActive)
    }

    @ViewBuilder
    private func safePlaceholder() -> some View {
        ShellCardShape()
            .strokeBorder(
                Color.treasureInk.opacity(0.4),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
            )
            .frame(width: 38, height: 42)
    }
}
