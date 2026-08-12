import 'dart:typed_data';

import 'sudoku_spec.dart';

/// A grid of digits, with the used-digit masks kept up to date as it changes.
///
/// The state is three lists of bitmasks — one per row, column and box — beside
/// the digits themselves. [place] and [remove] are four writes each, and
/// [candidateMask] is one or-and-not over three integers, so a search can walk
/// thousands of nodes without allocating anything per cell. A `Set<int>` of
/// candidates per cell, the obvious alternative, allocates one object per cell
/// per node and iterates in insertion order, which is the ordering source the
/// determinism rule bans (`PLAN-phase-2.md` §3).
///
/// The board knows the rules of placement and nothing about solving: it will
/// refuse an illegal digit, and it will let you empty a cell whose digit was
/// the only thing making the rest of the grid solvable.
class SudokuBoard {
  /// An empty grid of the given shape.
  SudokuBoard(this.spec)
    : _digits = Uint8List(spec.cells),
      _rowMask = Uint32List(spec.digits),
      _colMask = Uint32List(spec.digits),
      _boxMask = Uint32List(spec.digits);

  SudokuBoard._(
    this.spec,
    this._digits,
    this._rowMask,
    this._colMask,
    this._boxMask,
  );

  /// Reads a grid back from a clue string, as [toClueString] writes it.
  ///
  /// Throws a [FormatException] on the wrong length, an unusable character, or
  /// a grid that already breaks the rules. The string is what `puzzleCache` in
  /// `PLAN.md` §5.2 stores, so it arrives from a file a child's tablet wrote
  /// months ago and may have truncated: this is a parser of untrusted input,
  /// not a test convenience, and phase 3 catches the exception and regenerates
  /// rather than showing a grid with two 5s in a row.
  factory SudokuBoard.fromClues(SudokuSpec spec, String clues) {
    if (clues.length != spec.cells) {
      throw FormatException(
        'expected ${spec.cells} characters for ${spec.label}, '
        'got ${clues.length}',
        clues,
      );
    }

    final board = SudokuBoard(spec);
    for (var index = 0; index < clues.length; index++) {
      final char = clues.codeUnitAt(index);
      if (char == _emptyChar) continue;

      final digit = char - _zeroChar;
      if (digit < 1 || digit > spec.digits) {
        throw FormatException(
          'expected "." or 1-${spec.digits}, got "${clues[index]}"',
          clues,
          index,
        );
      }
      if (!board.place(index, digit)) {
        throw FormatException(
          '$digit at row ${spec.rowOf(index)}, column ${spec.colOf(index)} '
          'repeats a digit already in its row, column or box',
          clues,
          index,
        );
      }
    }
    return board;
  }

  static const int _emptyChar = 0x2E; // '.'
  static const int _zeroChar = 0x30; // '0'

  /// The shape of this grid.
  final SudokuSpec spec;

  /// One digit per cell, row-major; 0 means empty.
  final Uint8List _digits;

  /// Digits already used in each row, column and box, as bitmasks.
  final Uint32List _rowMask;
  final Uint32List _colMask;
  final Uint32List _boxMask;

  int _filledCount = 0;

  /// The digit in the cell at [index], or 0 when it is empty.
  int digitAt(int index) => _digits[index];

  /// How many cells hold a digit.
  int get filledCount => _filledCount;

  /// Whether every cell holds a digit.
  ///
  /// A full board is a legal one: nothing can be placed illegally, so there is
  /// no separate validity question to ask.
  bool get isFull => _filledCount == spec.cells;

  /// The digits that could legally go in the empty cell at [index], as a
  /// bitmask where bit `d - 1` stands for digit `d`.
  ///
  /// A filled cell has no candidates and returns 0. That is a choice, not an
  /// accident: the alternative — what could go here if it were empty — reads
  /// the same at the call site and quietly makes a solver consider cells it has
  /// already decided.
  int candidateMask(int index) {
    if (_digits[index] != 0) return 0;
    final used =
        _rowMask[spec.rowOf(index)] |
        _colMask[spec.colOf(index)] |
        _boxMask[spec.boxOf(index)];
    return ~used & spec.fullMask;
  }

  /// Puts [digit] in the empty cell at [index].
  ///
  /// Returns false and changes nothing when the cell is occupied or the digit
  /// is already in that row, column or box — the two ways a move can be against
  /// the rules. An index or digit outside the grid is a mistake in the caller
  /// rather than a move the rules forbid, and throws [RangeError].
  bool place(int index, int digit) {
    RangeError.checkValidIndex(index, _digits, 'index');
    if (digit < 1 || digit > spec.digits) {
      throw RangeError.range(digit, 1, spec.digits, 'digit');
    }
    if (_digits[index] != 0) return false;

    final bit = 1 << (digit - 1);
    final row = spec.rowOf(index);
    final col = spec.colOf(index);
    final box = spec.boxOf(index);
    if ((_rowMask[row] | _colMask[col] | _boxMask[box]) & bit != 0) {
      return false;
    }

    _digits[index] = digit;
    _rowMask[row] |= bit;
    _colMask[col] |= bit;
    _boxMask[box] |= bit;
    _filledCount++;
    return true;
  }

  /// Empties the cell at [index], whether or not it held anything.
  ///
  /// Tolerating an already-empty cell keeps the generator's dig loop free of a
  /// check it would otherwise repeat at every call site.
  void remove(int index) {
    RangeError.checkValidIndex(index, _digits, 'index');
    final digit = _digits[index];
    if (digit == 0) return;

    final bit = ~(1 << (digit - 1));
    _digits[index] = 0;
    _rowMask[spec.rowOf(index)] &= bit;
    _colMask[spec.colOf(index)] &= bit;
    _boxMask[spec.boxOf(index)] &= bit;
    _filledCount--;
  }

  /// The grid as one row-major line: `.` for an empty cell, `1`-`9` otherwise.
  ///
  /// This is the `puzzleCache` value in `PLAN.md` §5.2 and the line body in the
  /// golden files, so its shape is a stored format rather than a debug aid.
  String toClueString() {
    final out = StringBuffer();
    for (var index = 0; index < _digits.length; index++) {
      final digit = _digits[index];
      out.writeCharCode(digit == 0 ? _emptyChar : _zeroChar + digit);
    }
    return out.toString();
  }

  /// An independent copy, so a caller can search on it without unwinding.
  SudokuBoard copy() => SudokuBoard._(
    spec,
    Uint8List.fromList(_digits),
    Uint32List.fromList(_rowMask),
    Uint32List.fromList(_colMask),
    Uint32List.fromList(_boxMask),
  ).._filledCount = _filledCount;

  @override
  String toString() => toClueString();
}
