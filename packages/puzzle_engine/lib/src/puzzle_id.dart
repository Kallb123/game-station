import 'difficulty.dart';
import 'hash.dart';
import 'sudoku_spec.dart';

/// The name of one puzzle, and the only thing a save file stores about it
/// (`PLAN.md` §3.2).
///
/// ```
/// sudoku:9x9:hard:412
///         │   │    └── index, decimal, no leading zeros
///         │   └─────── easy | medium | hard | expert
///         └─────────── 9x9 | 6x6
/// ```
///
/// The grid is a pure function of this string, so the string is what gets
/// stored and the megabytes of grid are what do not. That is also why [parse]
/// is strict about the form: `sudoku:9x9:hard:0412` names the same puzzle to a
/// human and a different key to a map, and two keys for one puzzle means a
/// child solves it twice and it stays unsolved once.
class PuzzleId {
  /// The puzzle at [index] of the endless list for this size and difficulty.
  ///
  /// Expert at 6x6 does not exist — the grid has too little room for a genuine
  /// T4 (`PLAN.md` §3.4) — but that is not asserted here. A `const` constructor
  /// may assert only over the language's own equality and without property
  /// access, and that check needs both. It lives where it can be made:
  /// [PuzzleId.parse] refuses to spell the combination, and `generateSudoku`
  /// throws for it in release as well as in debug, because the tier has no
  /// clue-count band to aim at.
  const PuzzleId(this.spec, this.difficulty, this.index)
    : assert(index >= 0, 'a puzzle index counts from 0'),
      assert(index <= maxPuzzleIndex, 'a puzzle index stops at maxPuzzleIndex');

  /// Reads an ID back from the string a save file holds.
  ///
  /// Throws a [FormatException] on anything but the canonical form: the prefix
  /// must be `sudoku`, the size must be one this engine builds, the difficulty
  /// must name a tier that exists for that size, and the index must be the
  /// shortest decimal spelling of a non-negative number. This parses untrusted
  /// input — a file a tablet wrote months ago, possibly truncated — so phase 3
  /// catches the exception and starts fresh rather than showing a grid that
  /// does not match its own name.
  factory PuzzleId.parse(String id) {
    final parts = id.split(':');
    if (parts.length != 4) {
      throw FormatException(
        'expected four colon-separated fields, got ${parts.length}',
        id,
      );
    }
    if (parts[0] != _prefix) {
      throw FormatException('expected "$_prefix", got "${parts[0]}"', id, 0);
    }

    final spec = _specNamed(parts[1]);
    if (spec == null) {
      throw FormatException(
        'expected ${SudokuSpec.s9x9.label} or ${SudokuSpec.s6x6.label}, '
        'got "${parts[1]}"',
        id,
        _prefix.length + 1,
      );
    }

    final difficulty = _difficultyNamed(parts[2]);
    if (difficulty == null) {
      throw FormatException(
        'expected one of ${Difficulty.values.map((d) => d.name).join(', ')}, '
        'got "${parts[2]}"',
        id,
        _prefix.length + parts[1].length + 2,
      );
    }
    if (spec == SudokuSpec.s6x6 && difficulty == Difficulty.expert) {
      throw FormatException(
        '${spec.label} has no ${difficulty.name} tier',
        id,
        _prefix.length + parts[1].length + 2,
      );
    }

    final indexAt = id.length - parts[3].length;
    final index = int.tryParse(parts[3]);
    // The round trip through the canonical spelling rejects a leading zero, a
    // sign and a leading plus in one comparison.
    if (index == null || index < 0 || '$index' != parts[3]) {
      throw FormatException(
        'expected a decimal index with no leading zeros, got "${parts[3]}"',
        id,
        indexAt,
      );
    }
    if (index > maxPuzzleIndex) {
      throw FormatException(
        'expected an index of at most $maxPuzzleIndex, got "${parts[3]}"',
        id,
        indexAt,
      );
    }

    return PuzzleId(spec, difficulty, index);
  }

  static const String _prefix = 'sudoku';

  /// The largest index an ID may name.
  ///
  /// A limit rather than "whatever an int holds", because an int does not hold
  /// the same thing everywhere: on the web it is a double, exact only to 2^53,
  /// so a longer number would parse to a different puzzle there than on a
  /// 64-bit VM — a stored ID that means two things is the one failure this
  /// package exists to prevent. Nine digits is a puzzle a day for two and a
  /// half million years, so nothing is lost by drawing the line well inside
  /// what both platforms agree about.
  static const int maxPuzzleIndex = 999999999;

  /// The grid's shape.
  final SudokuSpec spec;

  /// Which tier the generator was asked for.
  final Difficulty difficulty;

  /// Which puzzle of that size and difficulty, counting from 0.
  final int index;

  /// The canonical string, which is what a save file stores.
  String get value => '$_prefix:${spec.label}:${difficulty.name}:$index';

  /// The seed the generator starts from (`PLAN.md` §3.2).
  ///
  /// A hash of the whole string rather than of the index, so `hard:1` and
  /// `easy:1` are unrelated grids instead of the same one dug differently.
  int get seed => fnv1a32(value);

  static SudokuSpec? _specNamed(String label) {
    for (final spec in const [SudokuSpec.s9x9, SudokuSpec.s6x6]) {
      if (spec.label == label) return spec;
    }
    return null;
  }

  static Difficulty? _difficultyNamed(String name) {
    for (final difficulty in Difficulty.values) {
      if (difficulty.name == name) return difficulty;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is PuzzleId &&
      other.spec == spec &&
      other.difficulty == difficulty &&
      other.index == index;

  @override
  int get hashCode => Object.hash(spec, difficulty, index);

  @override
  String toString() => value;
}

/// Day 0 of the daily puzzle, in UTC (`PLAN.md` §3.2).
///
/// `final` rather than `const`, which `PLAN-phase-2.md` §4.6 assumed: [DateTime]
/// has no const constructor, so the epoch is built once at load instead.
final DateTime puzzleEpoch = DateTime.utc(2026, 1, 1);

/// Which daily puzzle [when] falls on: whole days since [puzzleEpoch], in UTC.
///
/// UTC first, so a child who flies across a timezone neither skips a day nor
/// gets yesterday's puzzle twice, and so two devices in different places agree
/// about what today's puzzle is.
///
/// Dates before the epoch clamp to 0 rather than throwing. A tablet whose clock
/// is set to 2019 would otherwise crash on the daily card, and `AGENTS.md`
/// forbids showing a child an internal error: day 0's puzzle is wrong in a way
/// nobody can see, and a crash is not.
///
/// The comparison is between calendar days rather than instants, so an ID does
/// not change part-way through a UTC day.
int dayIndexFor(DateTime when) {
  final utc = when.toUtc();
  final midnight = DateTime.utc(utc.year, utc.month, utc.day);
  final days = midnight.difference(puzzleEpoch).inDays;
  return days < 0 ? 0 : days;
}
