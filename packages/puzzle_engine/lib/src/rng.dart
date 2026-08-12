import 'dart:typed_data';

import 'uint32.dart';

/// The frozen pseudo-random source every generated puzzle draws from.
///
/// Xoshiro128+: four 32-bit words of state, seeded by expanding a single seed
/// through SplitMix32. `dart:math`'s `Random(seed)` is deliberately not used —
/// it carries no guarantee of a stable sequence across Dart versions, and a
/// saved puzzle is stored as an ID rather than a grid, so a changed sequence
/// turns a solved puzzle into a different unsolved one (`PLAN.md` §3.1).
///
/// **This class is frozen.** The word order, the seeding, the rejection loop in
/// [nextInt] and the direction of [shuffle] are all part of the save format.
/// Changing any of them changes every puzzle, which means bumping
/// `generatorVersion`, regenerating the goldens, keeping the old generator
/// reachable and shipping a save migration, all in one commit.
/// `test/rng_test.dart` asserts the first outputs against literals so a change
/// shows up as a diff of numbers rather than as a puzzle nobody recognises.
///
/// It is not exported from `puzzle_engine.dart`: freezing a sequence is only
/// meaningful if nothing outside the package can start a different one, so
/// `Rng(DateTime.now().millisecond)` in the app does not compile. Tests import
/// this file by path.
class Rng {
  /// Creates a generator for [seed]; the same seed always replays the same
  /// sequence.
  ///
  /// Only the low 32 bits of [seed] are used, so callers may pass a hash
  /// without masking it first.
  Rng(int seed) : _s = _expand(seed);

  final Uint32List _s;

  /// SplitMix32, applied to four successive counter values.
  ///
  /// The state array does the masking: writing to a [Uint32List] truncates, so
  /// a missed `& mask32` cannot leave a word wider than 32 bits on native while
  /// the web build wraps it.
  ///
  /// `PLAN.md` §3.1's sketch seeds two words directly and then discards eight
  /// outputs to wash out a low-entropy state. SplitMix32 avalanches the seed
  /// before it reaches the state, so the discard loop is not needed — and its
  /// iteration count would itself have been a frozen constant.
  ///
  /// The all-zero state that never advances is unreachable here rather than
  /// guarded against: SplitMix32 is a bijection on 32 bits (xor-shift and
  /// odd-constant multiply both are), so exactly one input maps to zero and at
  /// most one of the four words can be zero. A guard for it would be a branch
  /// no test could ever enter. `PLAN-phase-2.md` §4.1 called for the guard;
  /// this is why it is absent.
  static Uint32List _expand(int seed) {
    final state = Uint32List(4);
    var counter = seed & mask32;
    for (var i = 0; i < 4; i++) {
      counter = (counter + 0x9E3779B9) & mask32;
      var z = counter;
      z = mul32(z ^ (z >> 16), 0x21F0AAAD);
      z = mul32(z ^ (z >> 15), 0x735A2D97);
      state[i] = z ^ (z >> 15);
    }
    return state;
  }

  /// The raw generator step: a uniform value in 0..2^32-1.
  int nextUint32() {
    final result = (_s[0] + _s[3]) & mask32;
    final t = (_s[1] << 9) & mask32;

    _s[2] ^= _s[0];
    _s[3] ^= _s[1];
    _s[1] ^= _s[2];
    _s[0] ^= _s[3];
    _s[2] ^= t;
    _s[3] = rotl32(_s[3], 11);

    return result;
  }

  /// A uniform value in 0..[bound]-1, where [bound] is in 1..2^32.
  ///
  /// Rejection rather than `% bound`: taking the remainder of a 32-bit draw is
  /// biased towards low values for any bound that does not divide 2^32. The
  /// bias is tiny, but the sequence is frozen either way, so there is no reason
  /// to freeze the biased one.
  ///
  /// A bound of 1 returns without drawing, which keeps a [shuffle] of a
  /// one-element list from consuming the stream.
  int nextInt(int bound) {
    if (bound < 1 || bound > uint32Size) {
      throw RangeError.range(bound, 1, uint32Size, 'bound');
    }
    if (bound == 1) return 0;

    // Values at or above the limit are the partial final block of the range;
    // dropping them leaves a whole number of blocks, so every outcome is
    // equally likely. The loop terminates with probability 1 and, for the
    // bounds this engine uses (at most 81), rejects less than one draw in 50
    // million.
    final limit = uint32Size - (uint32Size % bound);
    while (true) {
      final draw = nextUint32();
      if (draw < limit) return draw % bound;
    }
  }

  /// Fisher-Yates, descending, in place.
  ///
  /// The direction is written down because it is load-bearing: the ascending
  /// variant consumes the same stream in a different order and so produces
  /// different puzzles from the same seed.
  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final held = list[i];
      list[i] = list[j];
      list[j] = held;
    }
  }
}
