import Foundation

/// SplitMix64 — the deterministic PRNG that makes every player's daily board identical.
/// Uses wrapping arithmetic (`&+`, `&*`) so it reproduces bit-for-bit across platforms.
///
/// Verification vectors (seed = 0): the first five `next()` outputs are
/// 0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F, 0xF88BB8A8724C81EC,
/// 0x1B39896A51A8749B. (seed = 1) first output 0x910A2DEC89025CC1. These are asserted
/// in the engine tests, so any drift from the reference stream fails the build.
struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
