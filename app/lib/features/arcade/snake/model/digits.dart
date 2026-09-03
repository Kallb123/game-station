// Numeral glyphs for counting mode, as row bitmasks rather than a font
// (`PLAN-phase-7-snake.md` §4.5) — the same trick `invaders/model/sprites.dart`
// uses and for the same reasons: no binary in the diff, no licence line, and
// exact at any resolution. `snake_game.dart` (PR 4) is the first reader.
//
// Each entry is 3 wide, 5 tall, one row per list entry, most significant of
// the three bits leftmost — `sprites.dart`'s own convention, kept the same so
// a reader does not have to learn a second bit order for the second game.

/// `digitGlyphs[n]` is the glyph for digit `n`, `0` through `9`.
const List<List<int>> digitGlyphs = [
  // 0
  [0x7, 0x5, 0x5, 0x5, 0x7],
  // 1
  [0x2, 0x6, 0x2, 0x2, 0x7],
  // 2
  [0x7, 0x1, 0x7, 0x4, 0x7],
  // 3
  [0x7, 0x1, 0x7, 0x1, 0x7],
  // 4
  [0x5, 0x5, 0x7, 0x1, 0x1],
  // 5
  [0x7, 0x4, 0x7, 0x1, 0x7],
  // 6
  [0x7, 0x4, 0x7, 0x5, 0x7],
  // 7
  [0x7, 0x1, 0x1, 0x1, 0x1],
  // 8
  [0x7, 0x5, 0x7, 0x5, 0x7],
  // 9
  [0x7, 0x5, 0x7, 0x1, 0x7],
];
