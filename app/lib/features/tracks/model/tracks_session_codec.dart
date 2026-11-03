// The strings a half-finished Tracks board is stored as.
//
// `TracksInProgress` keeps `cells`, `marks` and `undoStack` opaque to the save
// codec on purpose (`PLAN-phase-9-tracks.md` §4.11), so this file owns their
// shape. As with Sudoku's `session_codec.dart`, it is the frozen half of the
// session: once a child's `save.json` holds these strings, changing any of them
// means a schema migration rather than a refactor, which is why they live apart
// from `tracks_session.dart` and have their own round-trip test.
//
// The board and the marks are fixed-width and delimiter-free within a cell, so
// decoding is arithmetic rather than parsing and a truncated string fails a
// length check instead of decoding into a plausible wrong board. Every decoder
// here reads untrusted input: a file written months ago by a build that is no
// longer installed, possibly truncated by a tablet that lost power mid-write,
// possibly hand-edited.

import 'package:puzzle_engine/puzzle_engine.dart';

/// How many moves the undo stack keeps, oldest dropped past this
/// (`PLAN-phase-9-tracks.md` §4.7).
///
/// The same figure as Sudoku's, and deliberately a second constant rather than
/// an import: the two games' saves are independent formats, and either cap
/// could be moved without a schema argument about the other. A stroke is one
/// entry, so 300 is far deeper than a child will walk back.
const int tracksUndoStackCap = 300;

/// The board as one row-major line: one lowercase hex character per cell, the
/// cell's connection mask (north 1, east 2, south 4, west 8), port bits
/// included (`PLAN-phase-9-tracks.md` §4.11).
///
/// Throws an [ArgumentError] when [masks] is not one entry per cell and a
/// [RangeError] for a mask outside 0..15, which would otherwise encode to a
/// character this file then refuses to read back.
String encodeTracksCells(TracksSpec spec, List<int> masks) {
  _checkLength(spec, masks.length, 'masks');
  final out = StringBuffer();
  for (final mask in masks) {
    if (mask < 0 || mask > _maxMask) {
      throw RangeError.range(mask, 0, _maxMask, 'masks');
    }
    out.write(_hex[mask]);
  }
  return out.toString();
}

/// Reads a board back from [encoded].
///
/// Throws a [FormatException] on the wrong length or a character outside
/// `0-9a-f`. Structure — two bits at most, reciprocity, the ports — is not
/// checked here but by the session, which also knows the puzzle's clues.
List<int> decodeTracksCells(TracksSpec spec, String encoded) {
  if (encoded.length != spec.cells) {
    throw FormatException(
      'expected ${spec.cells} characters for ${spec.label}, '
      'got ${encoded.length}',
      encoded,
    );
  }

  final masks = List<int>.filled(spec.cells, 0);
  for (var index = 0; index < spec.cells; index++) {
    final char = encoded.codeUnitAt(index);
    if (char >= _zeroChar && char < _zeroChar + 10) {
      masks[index] = char - _zeroChar;
    } else if (char >= _lowerAChar && char < _lowerAChar + 6) {
      masks[index] = char - _lowerAChar + 10;
    } else {
      // Uppercase is rejected rather than accepted: nothing writes it, so a
      // file holding it was edited by hand, and a decoder that is generous
      // about what it takes is one whose format is whatever it happens to
      // accept.
      throw FormatException(
        'expected 0-9 or a-f, got "${encoded[index]}"',
        encoded,
        index,
      );
    }
  }
  return masks;
}

/// The "no track here" marks as one `'0'` or `'1'` per cell, row-major.
///
/// The empty string when nothing is marked, which is the common case and the
/// difference between a few dozen bytes per saved puzzle and none.
String encodeTracksMarks(TracksSpec spec, List<bool> marks) {
  _checkLength(spec, marks.length, 'marks');
  if (!marks.contains(true)) return '';
  return marks.map((marked) => marked ? '1' : '0').join();
}

/// Reads marks back from [encoded], which is either empty or one character per
/// cell.
///
/// Throws a [FormatException] on the wrong length or a character that is not
/// `0` or `1`.
List<bool> decodeTracksMarks(TracksSpec spec, String encoded) {
  if (encoded.isEmpty) return List<bool>.filled(spec.cells, false);
  if (encoded.length != spec.cells) {
    throw FormatException(
      'expected ${spec.cells} characters for ${spec.label}, '
      'got ${encoded.length}',
      encoded,
    );
  }

  final marks = List<bool>.filled(spec.cells, false);
  for (var index = 0; index < spec.cells; index++) {
    final char = encoded[index];
    if (char != '0' && char != '1') {
      throw FormatException('expected 0 or 1, got "$char"', encoded, index);
    }
    marks[index] = char == '1';
  }
  return marks;
}

/// What one cell held **before** a move: its connection [mask] and whether it
/// carried a "no track here" [marked] flag.
class TracksCellState {
  /// The state to restore at [index].
  const TracksCellState({
    required this.index,
    required this.mask,
    required this.marked,
  });

  /// The cell, row-major.
  final int index;

  /// Its connection bits, port bits included.
  final int mask;

  /// Whether it carried a mark.
  final bool marked;

  @override
  bool operator ==(Object other) =>
      other is TracksCellState &&
      other.index == index &&
      other.mask == mask &&
      other.marked == marked;

  @override
  int get hashCode => Object.hash(index, mask, marked);

  @override
  String toString() => 'TracksCellState($index.$mask.${marked ? 1 : 0})';
}

/// One entry of the undo stack: the pre-move state of every cell a move
/// changed.
///
/// Undo is a restore rather than an inverse operation, as in Sudoku
/// (`PLAN-phase-3.md` §4.4), and an entry holds several cells because one
/// stroke lays a whole run of connections and one stroke is one undo
/// (`PLAN-phase-9-tracks.md` §4.7).
class TracksMove {
  /// A move restoring [cells], which must be non-empty and in strictly
  /// ascending index order.
  TracksMove(List<TracksCellState> cells) : cells = List.unmodifiable(cells) {
    if (cells.isEmpty) throw ArgumentError.value(cells, 'cells', 'is empty');
    for (var i = 1; i < cells.length; i++) {
      if (cells[i].index <= cells[i - 1].index) {
        throw ArgumentError.value(
          cells,
          'cells',
          'must be in strictly ascending index order',
        );
      }
    }
  }

  /// Reads a move back from [encoded], as [encode] writes it.
  ///
  /// Throws a [FormatException] on an empty string, a cell that is not three
  /// unsigned canonical decimals, an index outside the grid, a mask above 15 or
  /// with more than two bits, a mark that is not 0 or 1, or indices that do not
  /// strictly ascend. The last is what makes one move one spelling.
  factory TracksMove.decode(TracksSpec spec, String encoded) {
    if (encoded.isEmpty) {
      throw FormatException('a move holds at least one cell', encoded);
    }

    final cells = <TracksCellState>[];
    var previous = -1;
    for (final entry in encoded.split(cellSeparator)) {
      final parts = entry.split(fieldSeparator);
      if (parts.length != 3) {
        throw FormatException(
          'expected three "$fieldSeparator"-separated fields, '
          'got ${parts.length} in "$entry"',
          encoded,
        );
      }

      final index = _parseUnsigned(parts[0], encoded, 'a cell index');
      final mask = _parseUnsigned(parts[1], encoded, 'a mask');
      final mark = _parseUnsigned(parts[2], encoded, 'a mark');
      if (index >= spec.cells) {
        throw FormatException(
          'cell $index is outside a ${spec.label} grid',
          encoded,
        );
      }
      if (mask > _maxMask || _bitCount(mask) > 2) {
        throw FormatException(
          'mask $mask is not at most two connections',
          encoded,
        );
      }
      if (mark > 1) {
        throw FormatException('expected a mark of 0 or 1, got $mark', encoded);
      }
      if (index <= previous) {
        throw FormatException(
          'expected ascending cell indices, got $index after $previous',
          encoded,
        );
      }
      previous = index;
      cells.add(TracksCellState(index: index, mask: mask, marked: mark == 1));
    }
    return TracksMove(cells);
  }

  /// What separates the cells of an encoded move.
  static const String cellSeparator = ',';

  /// What separates the three fields of one cell.
  static const String fieldSeparator = '.';

  /// The cells to restore, ascending by index, never empty.
  final List<TracksCellState> cells;

  /// The string [TracksMove.decode] reads back:
  /// `"<index>.<mask>.<0|1>,<index>.<mask>.<0|1>"`, all decimal.
  String encode() => cells
      .map(
        (cell) =>
            '${cell.index}$fieldSeparator${cell.mask}$fieldSeparator'
            '${cell.marked ? 1 : 0}',
      )
      .join(cellSeparator);

  @override
  bool operator ==(Object other) {
    if (other is! TracksMove || other.cells.length != cells.length) {
      return false;
    }
    for (var i = 0; i < cells.length; i++) {
      if (other.cells[i] != cells[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(cells);

  @override
  String toString() => 'TracksMove(${encode()})';
}

const String _hex = '0123456789abcdef';
const int _maxMask = 15;
const int _zeroChar = 0x30; // '0'
const int _lowerAChar = 0x61; // 'a'

void _checkLength(TracksSpec spec, int length, String name) {
  if (length != spec.cells) {
    throw ArgumentError.value(
      length,
      name,
      'expected one entry per cell of ${spec.label} (${spec.cells})',
    );
  }
}

int _bitCount(int mask) {
  var count = 0;
  for (var bits = mask; bits != 0; bits >>= 1) {
    count += bits & 1;
  }
  return count;
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
