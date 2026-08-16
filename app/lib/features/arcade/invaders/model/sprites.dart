// Pixel-art sprites for Invaders, as row bitmasks rather than an asset file
// (`PLAN-phase-4.md` §4.7): no binary in the diff, no licence line, exact at
// any resolution, and a change to a shape is a diff to numbers a reviewer can
// read. Nothing in this phase draws them — `invaders_game.dart` (PR 4) is the
// first reader — but they are declared now so the render pass has nothing
// left to invent, and the numbers below match `invaders_sim.dart`'s
// `alienWidth`/`alienHeight`/`playerWidth`/`playerHeight`/`ufoWidth`/
// `ufoHeight`/`shotWidth`/`shotHeight`, so a hit-box and the shape drawn in it
// are never two different sizes by accident.
//
// One row per list entry, most significant relevant bit leftmost.

/// 16 wide, 8 tall — an alien in the back two rows (`PLAN.md` §4.1's
/// highest-scoring band).
const List<int> alienBack = [
  0x0FF0,
  0x3FFC,
  0x7EF7,
  0xFFFF,
  0xDFFB,
  0x2004,
  0x4002,
  0x8001,
];

/// 16 wide, 8 tall — an alien in the middle two rows.
const List<int> alienMiddle = [
  0x0810,
  0x0C30,
  0x1FF8,
  0x3EFC,
  0x7FFE,
  0x1C38,
  0x3204,
  0x0402,
];

/// 16 wide, 8 tall — an alien in the front row (`PLAN.md` §4.1's
/// lowest-scoring band).
const List<int> alienFront = [
  0x0210,
  0x0138,
  0x03FC,
  0x37EC,
  0x3FFC,
  0x0FF0,
  0x1818,
  0x2004,
];

/// 16 wide, 8 tall — the player's ship.
const List<int> player = [
  0x0180,
  0x03C0,
  0x03C0,
  0x1FF8,
  0x3FFC,
  0x7FFE,
  0xFFFF,
  0xFFFF,
];

/// 16 wide, 8 tall — the UFO that crosses periodically.
const List<int> ufo = [
  0x03C0,
  0x0FF0,
  0x1FF8,
  0x3FFC,
  0x7FFE,
  0x0FF0,
  0x1818,
  0x2004,
];

/// 2 wide, 6 tall — a shot, from either direction.
const List<int> shot = [0x3, 0x3, 0x3, 0x3, 0x3, 0x3];
