import 'dart:typed_data';

import '../digit_mask.dart';
import '../sudoku_board.dart';
import '../sudoku_spec.dart';

/// The cells of every row, column and box, as index lists.
///
/// Built once per solve and walked in a fixed order — rows top to bottom, then
/// columns left to right, then boxes — because a technique that scanned units
/// in an unspecified order would deduce the same facts in a different sequence,
/// and the generator judges a puzzle by which technique came first
/// (`PLAN-phase-2.md` §4.5).
class SudokuUnits {
  /// The units of a grid shaped like [spec].
  SudokuUnits(SudokuSpec spec)
    : rows = List.generate(
        spec.digits,
        (row) => List.generate(spec.digits, (col) => spec.indexAt(row, col)),
        growable: false,
      ),
      cols = List.generate(
        spec.digits,
        (col) => List.generate(spec.digits, (row) => spec.indexAt(row, col)),
        growable: false,
      ),
      boxes = List.generate(spec.digits, (box) {
        final topRow = (box ~/ spec.boxesPerRow) * spec.boxRows;
        final leftCol = (box % spec.boxesPerRow) * spec.boxCols;
        return List.generate(
          spec.digits,
          (cell) => spec.indexAt(
            topRow + cell ~/ spec.boxCols,
            leftCol + cell % spec.boxCols,
          ),
          growable: false,
        );
      }, growable: false);

  /// Each row's cells, left to right.
  final List<List<int>> rows;

  /// Each column's cells, top to bottom.
  final List<List<int>> cols;

  /// Each box's cells, row-major within the box.
  final List<List<int>> boxes;

  /// Every unit, rows then columns then boxes: the order the unit-scanning
  /// techniques use.
  Iterable<List<int>> get all sync* {
    yield* rows;
    yield* cols;
    yield* boxes;
  }
}

/// A board being solved by technique, with the candidates that placements and
/// eliminations have left.
///
/// [SudokuBoard.candidateMask] answers "what do the rules still allow here",
/// which is where a solve starts. It is not where a solve stays: ruling a 4 out
/// of a cell because of a naked pair elsewhere is a deduction the board cannot
/// represent, since nothing was placed. This class holds those narrowed masks,
/// and it is the reason the techniques compose — a pointing pair sets up the
/// naked single that follows it.
///
/// It owns a copy of the board it was given. `solveWithTechniques` runs while
/// the generator is still digging the caller's grid, so mutating the argument
/// would corrupt the puzzle being judged.
class CandidateGrid {
  /// A grid over a copy of [board], with candidates as the rules allow them.
  factory CandidateGrid(SudokuBoard board) => CandidateGrid._(board.copy());

  CandidateGrid._(SudokuBoard owned)
    : board = owned,
      units = SudokuUnits(owned.spec),
      _masks = Uint32List(owned.spec.cells) {
    for (var index = 0; index < board.spec.cells; index++) {
      _masks[index] = board.candidateMask(index);
    }
  }

  /// The grid's own board, which [place] fills in.
  final SudokuBoard board;

  /// The units of this board's shape.
  final SudokuUnits units;

  /// The digits still possible in each cell; 0 for a cell already filled.
  final Uint32List _masks;

  /// The shape being solved.
  SudokuSpec get spec => board.spec;

  /// The digits still possible at [index], as a bitmask.
  int maskAt(int index) => _masks[index];

  /// Whether [digit] is still possible at [index].
  bool has(int index, int digit) => _masks[index] & bitFor(digit) != 0;

  /// Rules [digit] out of [index], reporting whether that changed anything.
  ///
  /// A technique calls this for every cell it can rule the digit out of and
  /// keeps the answers: an inference that eliminates nothing is not progress,
  /// and reporting it as a step would let the solver loop forever on it.
  bool eliminate(int index, int digit) {
    final bit = bitFor(digit);
    if (_masks[index] & bit == 0) return false;
    _masks[index] &= ~bit;
    return true;
  }

  /// Puts [digit] in [index] and takes it out of every peer's candidates.
  ///
  /// Throws [StateError] when the board refuses the placement, which would mean
  /// a technique deduced a digit the rules forbid. That is a bug in the
  /// technique rather than a state a puzzle can reach, so it fails loudly here
  /// instead of leaving a grid that disagrees with its own candidates.
  void place(int index, int digit) {
    if (!board.place(index, digit)) {
      throw StateError('cannot place $digit at $index: the board refused it');
    }
    _masks[index] = 0;
    for (final peer in units.rows[spec.rowOf(index)]) {
      eliminate(peer, digit);
    }
    for (final peer in units.cols[spec.colOf(index)]) {
      eliminate(peer, digit);
    }
    for (final peer in units.boxes[spec.boxOf(index)]) {
      eliminate(peer, digit);
    }
  }
}
