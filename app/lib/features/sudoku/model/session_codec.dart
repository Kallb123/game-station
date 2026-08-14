// The three strings a half-finished puzzle is stored as.
//
// `PuzzleInProgress` keeps `grid`, `notes` and `undoStack` opaque to the save
// codec on purpose (`PLAN-phase-1.md` §4.2), so this file owns their shape.
// It is the frozen half of the session (`PLAN-phase-3.md` §3): once a child's
// `save.json` holds these strings, changing any of the three means a schema
// migration rather than a refactor, which is why they live apart from
// `sudoku_session.dart` — a format with its own file and its own round-trip
// test is harder to change by accident than three methods on a class that
// changes every pull request.
//
// The grid and the notes are fixed-width and delimiter-free within a cell, so
// decoding is arithmetic rather than parsing and a truncated string fails a
// length check instead of decoding into a plausible wrong board. Every decoder
// here reads untrusted input: a file written months ago by a build that is no
// longer installed, possibly truncated by a tablet that lost power mid-write,
// possibly hand-edited.

import 'package:puzzle_engine/puzzle_engine.dart';

import '../data/puzzle_record.dart';

/// How many moves the undo stack keeps, oldest dropped past this
/// (`PLAN-phase-3.md` §4.4).
///
/// Toggling pencil marks can produce thousands of moves in one puzzle, and the
/// save is meant to be a few kilobytes after 500 puzzles (`PLAN.md` §5.2). 300
/// moves back is deeper than any child will walk.
const int undoStackCap = 300;

/// The grid as one row-major line, in the engine's clue-string format: one
/// character per cell, [PuzzleRecord.emptyCell] for an empty one.
///
/// Clues and entered digits alike, so the string is the board a child sees
/// rather than the difference from the one they were given. Which cells are
/// givens is recoverable from the puzzle's own clue string, which the id names.
String encodeGrid(SudokuSpec spec, List<int> digits) {
  _checkLength(spec, digits.length, 'digits');
  final out = StringBuffer();
  for (final digit in digits) {
    // Checked rather than trusted: an out-of-range digit would encode to a
    // character outside the alphabet — ":" for a 10 in a 9x9 — which writes a
    // save this same file then refuses to read back.
    if (digit < 0 || digit > spec.digits) {
      throw RangeError.range(digit, 0, spec.digits, 'digits');
    }
    out.writeCharCode(digit == 0 ? _emptyChar : _zeroChar + digit);
  }
  return out.toString();
}

/// Reads a grid back from [encoded].
///
/// Throws a [FormatException] on the wrong length or a character that is not a
/// digit of this size. Unlike `SudokuBoard.fromClues` it does not reject a grid
/// that repeats a digit in a row, column or box: a child's wrong entry is
/// exactly that, and a board that refused to hold one could not be resumed
/// (`PLAN-phase-3.md` §4.3).
List<int> decodeGrid(SudokuSpec spec, String encoded) {
  if (encoded.length != spec.cells) {
    throw FormatException(
      'expected ${spec.cells} characters for ${spec.label}, '
      'got ${encoded.length}',
      encoded,
    );
  }

  final digits = List<int>.filled(spec.cells, 0);
  for (var index = 0; index < spec.cells; index++) {
    final char = encoded.codeUnitAt(index);
    if (char == _emptyChar) continue;

    final digit = char - _zeroChar;
    if (digit < 1 || digit > spec.digits) {
      throw FormatException(
        'expected "${PuzzleRecord.emptyCell}" or 1-${spec.digits}, '
        'got "${encoded[index]}"',
        encoded,
        index,
      );
    }
    digits[index] = digit;
  }
  return digits;
}

/// The pencil marks as two base-36 characters per cell, zero-padded, row-major.
///
/// The empty string when no cell has a note, which is the common case and the
/// difference between 162 bytes per saved puzzle and none.
///
/// Two base-36 characters hold a mask of up to ten digits, which covers both
/// sizes a puzzle id can spell with room to spare; an eleven-digit grid would
/// need a wider field, and that is a format change rather than a size the
/// engine could simply be handed.
String encodeNotes(SudokuSpec spec, List<int> notes) {
  _checkLength(spec, notes.length, 'notes');
  if (notes.every((mask) => mask == 0)) return '';

  final out = StringBuffer();
  for (final mask in notes) {
    if (mask < 0 || mask > spec.fullMask) {
      throw RangeError.range(mask, 0, spec.fullMask, 'notes');
    }
    out
      ..writeCharCode(_base36Char(mask ~/ _base36))
      ..writeCharCode(_base36Char(mask % _base36));
  }
  return out.toString();
}

/// Reads pencil marks back from [encoded], which is either empty or two
/// characters per cell.
///
/// Throws a [FormatException] on the wrong length, a character outside `0-9a-z`
/// or a mask holding a digit this size does not have.
List<int> decodeNotes(SudokuSpec spec, String encoded) {
  if (encoded.isEmpty) return List<int>.filled(spec.cells, 0);
  if (encoded.length != 2 * spec.cells) {
    throw FormatException(
      'expected ${2 * spec.cells} characters for ${spec.label}, '
      'got ${encoded.length}',
      encoded,
    );
  }

  final notes = List<int>.filled(spec.cells, 0);
  for (var index = 0; index < spec.cells; index++) {
    final at = 2 * index;
    final mask =
        _base36Digit(encoded, at) * _base36 + _base36Digit(encoded, at + 1);
    if (mask > spec.fullMask) {
      throw FormatException(
        'the note at cell $index holds a digit ${spec.label} does not have',
        encoded,
        at,
      );
    }
    notes[index] = mask;
  }
  return notes;
}

/// One entry of the undo stack: what a cell held **before** a move.
///
/// Undo is therefore a restore rather than an inverse operation, so a move type
/// added later needs no new opcode (`PLAN-phase-3.md` §4.4) — a move that
/// changes a cell in some way nobody has thought of yet still undoes correctly,
/// because the entry says what to put back rather than what was done.
class SudokuMove {
  /// The state to restore at [index]: its [digit], 0 for empty, and its pencil
  /// [notes] as a candidate bitmask.
  const SudokuMove({
    required this.index,
    required this.digit,
    required this.notes,
  });

  /// Reads a move back from [encoded], as [encode] writes it.
  ///
  /// Throws a [FormatException] on anything but three unsigned decimal fields
  /// naming a cell, a digit and a mask this size has.
  factory SudokuMove.decode(SudokuSpec spec, String encoded) {
    final parts = encoded.split(fieldSeparator);
    if (parts.length != 3) {
      throw FormatException(
        'expected three "$fieldSeparator"-separated fields, '
        'got ${parts.length}',
        encoded,
      );
    }

    final index = _parseUnsigned(parts[0], encoded, 'a cell index');
    final digit = _parseUnsigned(parts[1], encoded, 'a digit');
    final notes = _parseUnsigned(parts[2], encoded, 'a note mask');
    if (index >= spec.cells) {
      throw FormatException(
        'cell $index is outside a ${spec.label} grid',
        encoded,
        0,
      );
    }
    if (digit > spec.digits) {
      throw FormatException(
        'digit $digit is outside a ${spec.label} grid',
        encoded,
        parts[0].length + 1,
      );
    }
    if (notes > spec.fullMask) {
      throw FormatException(
        'the note mask holds a digit ${spec.label} does not have',
        encoded,
        parts[0].length + parts[1].length + 2,
      );
    }

    return SudokuMove(index: index, digit: digit, notes: notes);
  }

  /// What separates the three fields of an encoded move.
  static const String fieldSeparator = '.';

  /// The cell the move changed.
  final int index;

  /// The digit that cell held before the move, 0 for empty.
  final int digit;

  /// The pencil marks it held before the move, as a bitmask where bit `d - 1`
  /// stands for digit `d` — the convention the engine's own masks use.
  final int notes;

  /// The string [SudokuMove.decode] reads back: `"<index>.<digit>.<mask>"`.
  String encode() => '$index$fieldSeparator$digit$fieldSeparator$notes';

  @override
  bool operator ==(Object other) =>
      other is SudokuMove &&
      other.index == index &&
      other.digit == digit &&
      other.notes == notes;

  @override
  int get hashCode => Object.hash(index, digit, notes);

  @override
  String toString() => 'SudokuMove(${encode()})';
}

/// The code unit of [PuzzleRecord.emptyCell], read once rather than spelled a
/// second time here: one definition of what an empty cell looks like.
final int _emptyChar = PuzzleRecord.emptyCell.codeUnitAt(0);

const int _zeroChar = 0x30; // '0'
const int _lowerAChar = 0x61; // 'a'
const int _base36 = 36;

void _checkLength(SudokuSpec spec, int length, String name) {
  if (length != spec.cells) {
    throw ArgumentError.value(
      length,
      name,
      'expected one entry per cell of ${spec.label} (${spec.cells})',
    );
  }
}

int _base36Char(int value) =>
    value < 10 ? _zeroChar + value : _lowerAChar + value - 10;

int _base36Digit(String encoded, int at) {
  final char = encoded.codeUnitAt(at);
  if (char >= _zeroChar && char < _zeroChar + 10) return char - _zeroChar;
  if (char >= _lowerAChar && char < _lowerAChar + 26) {
    return char - _lowerAChar + 10;
  }
  // Uppercase is rejected rather than accepted: nothing writes it, so a file
  // holding it was edited by hand, and a decoder that is generous about what it
  // takes is a decoder whose format is whatever it happens to accept.
  throw FormatException(
    'expected 0-9 or a-z, got "${encoded[at]}"',
    encoded,
    at,
  );
}

int _parseUnsigned(String field, String encoded, String what) {
  final value = field.isEmpty ? null : int.tryParse(field);
  // `int.tryParse` takes a leading sign and this format has none, so the round
  // trip through the canonical spelling is the check: it rejects "+1", "-1" and
  // a leading zero in one comparison.
  if (value == null || value < 0 || '$value' != field) {
    throw FormatException(
      'expected $what as a decimal with no leading zeros, got "$field"',
      encoded,
    );
  }
  return value;
}
