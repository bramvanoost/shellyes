/// A deterministic pseudo-random source returning Doubles in [0, 1).
/// Matches the contract of TS `Rng` from src/engine.ts.
public protocol ShellYesRandom {
    mutating func next() -> Double
}

/// Bit-identical port of the mulberry32 PRNG used in sim/regression.ts.
/// Must produce the same sequence as the TS implementation for the same seed,
/// since parity tests rely on this.
public struct Mulberry32: ShellYesRandom {
    private var a: UInt32

    public init(seed: UInt32) {
        self.a = seed
    }

    public mutating func next() -> Double {
        a = a &+ 0x6d2b79f5
        var t: UInt32 = a
        t = (t ^ (t &>> 15)) &* (t | 1)
        t = t ^ (t &+ ((t ^ (t &>> 7)) &* (t | 61)))
        let result: UInt32 = t ^ (t &>> 14)
        return Double(result) / 4_294_967_296.0
    }
}

/// A die that lands on the coin a little more often than a fair one,
/// and on the 1 a little less. Mirror of `luckyRng` in `src/engine.ts`
/// — change one, change both, then run `node parity/diff.mjs`.
///
/// `luck` is the probability mass moved: the coin comes up
/// `1/6 + luck` of the time, the 1 comes up `1/6 - luck`, the other
/// four faces are untouched. Exactly one draw from `base` per die, so
/// a seed still replays a game step for step.
///
/// It wraps rather than replaces the source, and hands the advanced
/// `base` back out again, so a game can bend one seat's dice and leave
/// every other seat rolling the same stream it always did.
public struct LuckyRandom<Base: ShellYesRandom>: ShellYesRandom {
    /// The source underneath, advanced by every draw taken here.
    public var base: Base
    private let moved: Double

    public init(base: Base, luck: Double) {
        self.base = base
        self.moved = max(0, min(luck, maxLuck))
    }

    public mutating func next() -> Double {
        let u = base.next()
        guard moved > 0 else { return u }
        let sixth = 1.0 / 6.0
        let keptLow = sixth - moved
        // The top slice of the 1's range is folded into the coin's.
        if u >= keptLow && u < sixth {
            return 5.0 / 6.0 + ((u - keptLow) / moved) * sixth
        }
        return u
    }
}
