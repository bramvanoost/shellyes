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

/// A die bent toward the high faces. Mirror of `luckyRng` in
/// `src/engine.ts` — change one, change both, then run
/// `node parity/diff.mjs`.
///
/// `luck` is the total probability mass moved; `faceWeights` says
/// where it goes. The remap is an inverse CDF: find which face the
/// draw falls on under the bent distribution, then return a number
/// inside that face's own fair slice. Exactly one draw from `base` per
/// die, so a seed still replays a game step for step, and at `luck` 0
/// every draw passes through untouched.
///
/// It wraps rather than replaces the source, and hands the advanced
/// `base` back out again, so a game can bend one seat's dice and leave
/// every other seat rolling the same stream it always did.
public struct LuckyRandom<Base: ShellYesRandom>: ShellYesRandom {
    /// The source underneath, advanced by every draw taken here.
    public var base: Base
    private let weights: [Double]
    private let cumulative: [Double]
    private let bent: Bool

    public init(base: Base, luck: Double) {
        self.base = base
        let moved = max(0, min(luck, maxLuck))
        self.bent = moved > 0
        self.weights = faceWeights(moved)
        var acc = 0.0
        self.cumulative = weights.map { acc += $0; return acc }
    }

    public mutating func next() -> Double {
        let u = base.next()
        guard bent else { return u }
        var i = 0
        while i < 5 && u >= cumulative[i] { i += 1 }
        let low = i == 0 ? 0 : cumulative[i - 1]
        // Clamped just under 1 so the result can never round up into
        // the next face's slice. The literal is spelled the same in
        // both engines; the bias it introduces is a part in a trillion.
        let within = min((u - low) / weights[i], 0.999999999999)
        return (Double(i) + within) / 6.0
    }
}
