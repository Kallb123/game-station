// What a Snake run counts, and the sequence of values that decade follows
// (`PLAN-phase-7-snake.md` §3, §4.3).
//
// [SnakeCounting] mirrors `core/storage/save_data.dart`'s enum of the same
// name and shape, deliberately declared fresh here rather than imported: PR 3
// keeps `model/` importing nothing from outside itself but `PadInput`, the
// same boundary `InvadersRules.normal`/`.easy` draws against
// `Profile.arcadeEasyMode` — a model-level rule set stays a value a test
// constructs, not a stored profile choice reaching in. `snake_screen.dart`
// (`PLAN-phase-7-snake.md` PR 4) is where the two meet, translating the
// profile's stored choice into this one when a run is built, exactly as it
// already translates `arcadeEasyMode` into [SnakeRules.normal] or `.easy`.

/// What a run counts, fixed when the run starts (`PLAN-phase-7-snake.md` §3).
enum SnakeCounting {
  /// Classic Snake: one target on the field, no numeral.
  off,

  /// 1, 2, 3 … one decade per level.
  ones,

  /// 2, 4, 6 … one decade per level.
  twos,
}

/// The `targetsPerLevel` values [level] (1-based) asks the player to eat in
/// order, in `ones` or `twos` mode (`PLAN-phase-7-snake.md` §4.3's table):
/// `ones` runs 1..10, then 11..20, then `10*(level-1)+1 .. 10*level`; `twos`
/// runs 2..20, then 22..40, then `20*(level-1)+2 .. 20*level`.
///
/// [counting] must not be [SnakeCounting.off] — classic mode has no numeral
/// sequence, and every value on its field is 0 (`SnakeSim.nextValue`).
List<int> sequenceForLevel(
  SnakeCounting counting,
  int level,
  int targetsPerLevel,
) {
  assert(counting != SnakeCounting.off, 'classic mode has no sequence');
  final step = counting == SnakeCounting.twos ? 2 : 1;
  final first = (level - 1) * targetsPerLevel * step + step;
  return [for (var i = 0; i < targetsPerLevel; i++) first + i * step];
}
