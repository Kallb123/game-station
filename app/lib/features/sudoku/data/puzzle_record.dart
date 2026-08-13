// One generated puzzle, in the one encoded form the app moves it around in.
//
// The same string serves two jobs (`PLAN-phase-3.md` §4.1): it is what the
// generation isolate returns — a primitive, because it crosses an isolate
// boundary — and it is what `SaveData.puzzleCache` stores. One format means one
// parser and one test, rather than two that agree until they do not.
//
// `PLAN.md` §5.2's `puzzleCache` example holds the clue string alone. The
// solution is added because immediate mistake feedback needs the true digit,
// and nothing exported from the engine can recover it from the clues
// (`PLAN-phase-3.md` §3); the phase's closing PR updates §5.2. Everything else
// on [GeneratedPuzzle] is dropped on purpose: the tier the grid earned, the
// attempt count and `widened` are the generator's business, and a widened
// puzzle is drawn like any other (`PLAN-phase-3.md` §2).

import 'package:puzzle_engine/puzzle_engine.dart';

/// The starting grid of one puzzle and its solution.
///
/// ```
/// "..3.2...|453126..."
///  │       │
///  │       └── the one completion, one character per cell
///  └────────── the clues, "." for a cell the child fills in
/// ```
class PuzzleRecord {
  /// A record holding [clues] and their [solution], both as clue strings.
  const PuzzleRecord({required this.clues, required this.solution});

  /// The record for a freshly generated [puzzle].
  factory PuzzleRecord.of(GeneratedPuzzle puzzle) =>
      PuzzleRecord(clues: puzzle.clues, solution: puzzle.solution);

  /// Reads a record back from [encoded], which is untrusted: it comes from a
  /// save file a tablet wrote months ago, possibly truncated, possibly edited.
  ///
  /// Throws a [FormatException] for anything that is not a puzzle of [spec] —
  /// a wrong length, a character that is not a digit of this size, a solution
  /// with a hole in it, a grid that repeats a digit in a row, column or box, or
  /// a clue the solution contradicts. The caller's answer to all of them is the
  /// same and it is not an error message: the id names the puzzle, so
  /// regenerating produces exactly what the entry was supposed to hold.
  factory PuzzleRecord.decode(SudokuSpec spec, String encoded) {
    final length = 2 * spec.cells + 1;
    if (encoded.length != length) {
      throw FormatException(
        'expected $length characters for ${spec.label}, got ${encoded.length}',
        encoded,
      );
    }
    if (encoded[spec.cells] != separator) {
      throw FormatException(
        'expected "$separator" between the clues and the solution',
        encoded,
        spec.cells,
      );
    }

    final clues = encoded.substring(0, spec.cells);
    final solution = encoded.substring(spec.cells + 1);
    // `SudokuBoard.fromClues` is the character check and the row, column and
    // box check in one, and it is the engine's own rather than a second copy of
    // it here. Eighty-one placements on a cache hit is nothing against the
    // 65 ms a regeneration costs, and it is the difference between rejecting a
    // corrupt entry and drawing one.
    _checkGrid(spec, clues, encoded, 0);
    _checkGrid(spec, solution, encoded, spec.cells + 1);

    final hole = solution.indexOf(emptyCell);
    if (hole >= 0) {
      throw FormatException(
        'the solution has no digit at cell $hole',
        encoded,
        spec.cells + 1 + hole,
      );
    }
    for (var index = 0; index < spec.cells; index++) {
      if (clues[index] != emptyCell && clues[index] != solution[index]) {
        throw FormatException(
          'the clue at cell $index is not what the solution puts there',
          encoded,
          index,
        );
      }
    }

    return PuzzleRecord(clues: clues, solution: solution);
  }

  /// What stands between the clues and the solution in an encoded record.
  ///
  /// Not a character either half can hold, so a truncated record cannot decode
  /// into a shorter but plausible one.
  static const String separator = '|';

  /// The character a clue string uses for a cell nobody has filled in, as
  /// `SudokuBoard.toClueString` writes it.
  static const String emptyCell = '.';

  /// The grid as the puzzle starts, one character per cell, row-major.
  final String clues;

  /// The one completion of [clues], in the same form with no [emptyCell].
  final String solution;

  /// The string [PuzzleRecord.decode] reads back.
  String encode() => '$clues$separator$solution';

  static void _checkGrid(
    SudokuSpec spec,
    String grid,
    String encoded,
    int offset,
  ) {
    try {
      SudokuBoard.fromClues(spec, grid);
    } on FormatException catch (error) {
      // Re-thrown against the whole encoded string, so an offset in a message
      // points at the character a reader would count to in the save file rather
      // than into a half nobody stored.
      throw FormatException(
        error.message,
        encoded,
        offset + (error.offset ?? 0),
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is PuzzleRecord &&
      other.clues == clues &&
      other.solution == solution;

  @override
  int get hashCode => Object.hash(clues, solution);

  @override
  String toString() => 'PuzzleRecord(${encode()})';
}
