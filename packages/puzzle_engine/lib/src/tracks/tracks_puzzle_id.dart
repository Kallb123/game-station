import '../difficulty.dart';
import '../hash.dart';
import '../puzzle_id.dart';
import 'tracks_spec.dart';

/// The name of one Tracks puzzle, and the only thing a save file stores about
/// it (`PLAN-phase-9-tracks.md` §4.2).
///
/// ```
/// tracks:7x7:medium:412
///          │   │      └── index, decimal, no leading zeros
///          │   └───────── easy | medium | hard
///          └───────────── 5x5 | 7x7 | 9x9
/// ```
///
/// The prefix `tracks` is frozen once the first save holds one: it is what
/// keeps a Tracks key from ever colliding with a Sudoku key in the shared
/// `solved` map. [parse] is strict for the reason [PuzzleId.parse] is: two
/// spellings of one puzzle are two keys, and a child would solve it twice.
class TracksPuzzleId {
  /// The puzzle at [index] of the endless list for this size and difficulty.
  ///
  /// The asserts match [PuzzleId]'s. That Expert does not exist is not asserted
  /// here for the reason [PuzzleId] gives: a `const` constructor cannot make the
  /// check, so [parse] refuses it and `generateTracks` will throw for it.
  const TracksPuzzleId(this.spec, this.difficulty, this.index)
    : assert(index >= 0, 'a puzzle index counts from 0'),
      assert(index <= maxPuzzleIndex, 'a puzzle index stops at maxPuzzleIndex');

  /// Reads an ID back from the string a save file holds.
  ///
  /// Throws a [FormatException] on anything but the canonical form. Expert is
  /// refused for every size: Tracks has no such tier
  /// (`PLAN-phase-9-tracks.md` §1, §4.1).
  ///
  /// 5x5 Hard is accepted for now. PR 3 measures whether a 5x5 grid can express
  /// Hard at all, and narrows this parser to refuse the combination if not;
  /// until then refusing it here would be a guess frozen into a stored format.
  factory TracksPuzzleId.parse(String id) {
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
        'expected one of ${TracksSpec.supported.map((s) => s.label).join(', ')}, '
        'got "${parts[1]}"',
        id,
        _prefix.length + 1,
      );
    }

    final difficultyAt = _prefix.length + parts[1].length + 2;
    final difficulty = _difficultyNamed(parts[2]);
    if (difficulty == null) {
      throw FormatException(
        'expected one of ${_tiers.map((d) => d.name).join(', ')}, '
        'got "${parts[2]}"',
        id,
        difficultyAt,
      );
    }
    if (difficulty == Difficulty.expert) {
      throw FormatException('tracks has no expert tier', id, difficultyAt);
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

    return TracksPuzzleId(spec, difficulty, index);
  }

  static const String _prefix = 'tracks';

  /// The tiers Tracks offers, in order.
  static const List<Difficulty> _tiers = [
    Difficulty.easy,
    Difficulty.medium,
    Difficulty.hard,
  ];

  /// The largest index an ID may name.
  ///
  /// The same limit as [PuzzleId.maxPuzzleIndex], referenced rather than
  /// copied so the two cannot drift; that field's documentation explains why
  /// the limit exists (an `int` is only exact to 2^53 on the web).
  static const int maxPuzzleIndex = PuzzleId.maxPuzzleIndex;

  /// The grid's size.
  final TracksSpec spec;

  /// Which tier the generator was asked for.
  final Difficulty difficulty;

  /// Which puzzle of that size and difficulty, counting from 0.
  final int index;

  /// The canonical string, which is what a save file stores.
  String get value => '$_prefix:${spec.label}:${difficulty.name}:$index';

  /// The seed the generator starts from.
  ///
  /// A hash of the whole string, so `hard:1` and `easy:1` are unrelated
  /// puzzles, as for [PuzzleId.seed].
  int get seed => fnv1a32(value);

  static TracksSpec? _specNamed(String label) {
    for (final spec in TracksSpec.supported) {
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
      other is TracksPuzzleId &&
      other.spec == spec &&
      other.difficulty == difficulty &&
      other.index == index;

  @override
  int get hashCode => Object.hash(spec, difficulty, index);

  @override
  String toString() => value;
}
