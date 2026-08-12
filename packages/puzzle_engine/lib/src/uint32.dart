/// 32-bit integer arithmetic that gives the same answer on every platform.
///
/// Dart's `int` is 64-bit on native and a JavaScript double on the web, where
/// only 53 bits are exact and bitwise operators truncate to 32 bits. Every
/// value in the PRNG and the hash is a 32-bit word, so the two agree — provided
/// nothing computes an intermediate above 2^53. That is the whole reason
/// [mul32] exists (`PLAN-phase-2.md` §4.2).
///
/// These helpers are shared by `rng.dart` and `hash.dart` so the multiply is
/// written once: two copies of a subtle masked multiply is two chances to fix
/// one of them, and puzzle IDs stored in saves depend on the answer never
/// changing.
library;

/// The low 32 bits of a value: `x & mask32` after any addition or shift.
const int mask32 = 0xFFFFFFFF;

/// 2^32, as a literal.
///
/// `1 << 32` is 0 on the web, where shifts are 32-bit, so the bound of the
/// PRNG's output range cannot be written as a shift.
const int uint32Size = 4294967296;

/// `(a * b) & mask32`, computed in halves so it stays exact on the web.
///
/// A direct `a * b` of two 32-bit words reaches 2^64, and a JavaScript number
/// silently rounds above 2^53 — the puzzles would diverge between a native and
/// a web build with nothing to show for it but different grids. Splitting `a`
/// into 16-bit halves keeps every intermediate under 2^48.
///
/// Both arguments must already be 32-bit words: a negative `a` would be shifted
/// arithmetically on native and logically on the web, which is the divergence
/// this function exists to prevent.
int mul32(int a, int b) {
  assert(a >= 0 && a <= mask32, 'a must be a 32-bit word, was $a');
  assert(b >= 0 && b <= mask32, 'b must be a 32-bit word, was $b');
  final low = (a & 0xFFFF) * b;
  final high = ((a >> 16) * b) & 0xFFFF;
  return (low + (high << 16)) & mask32;
}

/// Rotates a 32-bit word left by [bits].
///
/// [bits] must be in 1..31: JavaScript takes a shift count modulo 32, so a
/// rotation by 0 or 32 would be the identity on the web and produce something
/// else on a 64-bit VM. Asserted rather than left to the doc comment, because
/// the two platforms have to agree for the goldens to mean anything.
int rotl32(int x, int bits) {
  assert(x >= 0 && x <= mask32, 'x must be a 32-bit word, was $x');
  assert(bits >= 1 && bits <= 31, 'bits must be in 1..31, was $bits');
  return ((x << bits) | (x >> (32 - bits))) & mask32;
}
