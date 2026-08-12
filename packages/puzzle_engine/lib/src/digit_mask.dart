/// The digit-set bitmask every part of the engine passes around: bit `d - 1`
/// stands for digit `d`, so a 9x9 cell's candidates fit in nine bits of one
/// integer.
///
/// `SudokuBoard` sets the convention and the solvers follow it. These helpers
/// live together rather than being reimplemented per caller because a bit
/// numbered from the wrong end is the kind of mistake that produces a plausible
/// grid instead of an error.
library;

/// The bit standing for [digit].
int bitFor(int digit) => 1 << (digit - 1);

/// How many digits [mask] holds.
///
/// Kernighan's method: one iteration per digit present rather than one per
/// digit the grid allows. The counting solver asks this at every node, and the
/// subset techniques ask it once per cell per unit.
int bitCount(int mask) {
  var remaining = mask;
  var count = 0;
  while (remaining != 0) {
    remaining &= remaining - 1;
    count++;
  }
  return count;
}

/// The one digit in a [mask] that holds exactly one.
///
/// Asserted rather than checked: every caller has just established the count,
/// and a silent wrong answer here would place a digit that nothing else would
/// question.
int soleDigit(int mask) {
  assert(bitCount(mask) == 1, 'expected one digit, got ${bitCount(mask)}');
  var remaining = mask;
  var digit = 1;
  while (remaining > 1) {
    remaining >>= 1;
    digit++;
  }
  return digit;
}
