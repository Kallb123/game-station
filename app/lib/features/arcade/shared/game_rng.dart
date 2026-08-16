// The seeded source every Invaders run draws from: which column an alien
// fires from, the UFO's crossing time and its score (`PLAN-phase-4.md` §4.3).
//
// `dart:math`'s `Random(seed)` stays out of `app/lib` for the same reason
// `PLAN-phase-1.md` §1 kept it out of the engine: it carries no guarantee of a
// stable sequence across Dart versions. Here that would only make a recorded
// run unreplayable — nothing in a save depends on it — but an unreplayable run
// is exactly what would let the fixed-step equivalence test in
// `invaders_sim_test.dart` go quietly green while comparing two different
// games. `no_random_test.dart` is the mechanism that keeps `Random(` out;
// this file is why one is needed.

/// The mask that keeps every intermediate a 32-bit word.
const int _mask32 = 0xFFFFFFFF;

/// 2^32, as a literal: `1 << 32` is 0 on the web, where shifts are 32-bit.
const int _uint32Size = 4294967296;

/// `(a * b) & _mask32`, computed in halves so it stays exact on the web.
///
/// A direct `a * b` of two 32-bit words reaches 2^64, and a JavaScript number
/// silently rounds above 2^53. Splitting `a` into 16-bit halves keeps every
/// intermediate under 2^48 — the same technique as the engine's `mul32`
/// (`packages/puzzle_engine/lib/src/uint32.dart`), copied rather than shared
/// because that file is private to a package this one does not depend on.
int _mul32(int a, int b) {
  final low = (a & 0xFFFF) * b;
  final high = ((a >> 16) * b) & 0xFFFF;
  return (low + (high << 16)) & _mask32;
}

/// The seeded source behind every non-deterministic choice Invaders makes.
///
/// Xorshift32, seeded by one round of SplitMix32 — the same shape as the
/// engine's `Rng`, and for one of its reasons: masking to 32 bits at every
/// step means a web target added later plays the same game rather than a
/// different one (`packages/puzzle_engine/lib/src/rng.dart`).
///
/// **Unlike the engine's `Rng`, this class is not frozen.** Nothing persists
/// a run, so there is no saved value whose meaning would change under a
/// different sequence — only whether a test written against one sequence
/// still passes against another. `game_rng_test.dart` pins the first outputs
/// to literals so an unintended change shows up as a diff of numbers rather
/// than a game that plays differently for no visible reason.
///
/// Not exported past `features/arcade/shared/`: reusing the engine's `Rng`
/// instead was rejected in `PLAN-phase-4.md` §3 because exporting a frozen
/// sequence generator for a use that must not be frozen undoes the reason it
/// is frozen at all.
class GameRng {
  /// Creates a generator for [seed]; the same seed always replays the same
  /// sequence.
  ///
  /// Only the low 32 bits of [seed] are used, so callers may pass a hash — or
  /// the clock's raw milliseconds — without masking it first.
  GameRng(int seed) : _state = _seedFrom(seed);

  int _state;

  /// One round of SplitMix32, avalanching [seed] before it becomes the
  /// xorshift state.
  ///
  /// Xorshift32's only fixed point is a state of zero: `x ^ (x << k)` and
  /// `x ^ (x >> k)` both leave zero at zero, so a run seeded into it would
  /// draw zero forever. SplitMix32 is a bijection on 32 bits, so exactly one
  /// seed reaches it — unlike the engine's four-word expansion, where every
  /// one of four independently-mixed words would have to land on zero at
  /// once, which is unreachable and so left unguarded there. A single word
  /// hits it for one specific seed, so the guard here is real, and
  /// `game_rng_test.dart` seeds that value and asserts the stream still
  /// advances.
  static int _seedFrom(int seed) {
    var z = (seed + 0x9E3779B9) & _mask32;
    z = _mul32(z ^ (z >> 16), 0x21F0AAAD);
    z = _mul32(z ^ (z >> 15), 0x735A2D97);
    z = (z ^ (z >> 15)) & _mask32;
    return z == 0 ? 1 : z;
  }

  /// The raw generator step: a uniform value in 0..2^32-1.
  int nextUint32() {
    var x = _state;
    x = (x ^ (x << 13)) & _mask32;
    x ^= x >> 17;
    x = (x ^ (x << 5)) & _mask32;
    _state = x;
    return x;
  }

  /// A uniform value in 0..[bound]-1, where [bound] is in 1..2^32.
  ///
  /// Rejection rather than `% bound`, as the engine's `Rng.nextInt` is: the
  /// remainder of a 32-bit draw is biased low for a bound that does not
  /// divide 2^32.
  int nextInt(int bound) {
    if (bound < 1 || bound > _uint32Size) {
      throw RangeError.range(bound, 1, _uint32Size, 'bound');
    }
    if (bound == 1) return 0;

    // Values at or above the limit are the partial final block of the range;
    // dropping them leaves a whole number of blocks, so every outcome is
    // equally likely.
    final limit = _uint32Size - (_uint32Size % bound);
    while (true) {
      final draw = nextUint32();
      if (draw < limit) return draw % bound;
    }
  }

  /// A uniform value in `[0, 1)`, for jitter like the UFO's crossing interval.
  double nextDouble() => nextUint32() / _uint32Size;

  /// One element of [candidates], drawn uniformly — "which column fires."
  int pick(List<int> candidates) => candidates[nextInt(candidates.length)];
}
