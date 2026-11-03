import 'track_side.dart';
import 'tracks_spec.dart';

/// A Tracks puzzle as the player sees it: the ports, the row and column
/// counts, and the pieces already laid.
///
/// This is what the cache line and the goldens encode (`PLAN-phase-9-tracks.md`
/// §4.3). It is not the whole of the generator's result: the solution, tier and
/// widened flag join it in `TracksPuzzle`, which arrives with `generateTracks`
/// in PR 3 once it is known what the generator reports.
///
/// The constructor checks that the clues are well-formed, not that they are
/// solvable or consistent with each other: two fixed neighbours that disagree
/// about their shared edge are a puzzle with no solution, which is the
/// counter's question to answer, and answering it in two places would let the
/// two drift.
class TracksClues {
  /// Builds clues, storing unmodifiable copies of the lists.
  ///
  /// Throws an [ArgumentError] for structural nonsense: a list of the wrong
  /// length, a port outside the grid, a count outside `0..side`, a fixed entry
  /// that is not empty or a piece, or a fixed piece that points off the grid
  /// other than through its port.
  TracksClues({
    required this.spec,
    required this.startRow,
    required this.goalColumn,
    required List<int> rowCounts,
    required List<int> columnCounts,
    required List<int> fixed,
  }) : rowCounts = List.unmodifiable(rowCounts),
       columnCounts = List.unmodifiable(columnCounts),
       fixed = List.unmodifiable(fixed) {
    final side = spec.side;
    if (startRow < 0 || startRow >= side) {
      throw ArgumentError.value(
        startRow,
        'startRow',
        'must be in 0..${side - 1}',
      );
    }
    if (goalColumn < 0 || goalColumn >= side) {
      throw ArgumentError.value(
        goalColumn,
        'goalColumn',
        'must be in 0..${side - 1}',
      );
    }
    _checkCounts('rowCounts', this.rowCounts, side);
    _checkCounts('columnCounts', this.columnCounts, side);
    if (this.fixed.length != spec.cells) {
      throw ArgumentError.value(
        this.fixed.length,
        'fixed',
        'must have ${spec.cells} entries',
      );
    }
    for (var i = 0; i < this.fixed.length; i++) {
      final mask = this.fixed[i];
      if (mask == 0) continue;
      if (!TrackSide.isPiece(mask)) {
        throw ArgumentError.value(mask, 'fixed[$i]', 'must be 0 or a piece');
      }
      final row = spec.rowOf(i);
      final column = spec.columnOf(i);
      // A bit that leaves the grid is legal only through a port, because the
      // ports are the only places the track enters or leaves.
      if (mask & TrackSide.north != 0 && row == 0) {
        throw ArgumentError.value(
          mask,
          'fixed[$i]',
          'points off the north edge',
        );
      }
      if (mask & TrackSide.east != 0 && column == side - 1) {
        throw ArgumentError.value(
          mask,
          'fixed[$i]',
          'points off the east edge',
        );
      }
      if (mask & TrackSide.west != 0 && column == 0 && i != startCell) {
        throw ArgumentError.value(
          mask,
          'fixed[$i]',
          'points off the west edge away from the start port',
        );
      }
      if (mask & TrackSide.south != 0 && row == side - 1 && i != goalCell) {
        throw ArgumentError.value(
          mask,
          'fixed[$i]',
          'points off the south edge away from the goal port',
        );
      }
    }
  }

  /// Reads clues back from the line [encode] writes.
  ///
  /// Throws a [FormatException] on anything but the canonical spelling. This
  /// parses untrusted input — a cache file written by an older build, possibly
  /// truncated — so the caller discards the entry rather than showing a board
  /// that does not match its own name.
  factory TracksClues.decode(String line) {
    final parts = line.split('|');
    if (parts.length != 6) {
      throw FormatException(
        'expected six |-separated fields, got ${parts.length}',
        line,
      );
    }

    TracksSpec? spec;
    for (final candidate in TracksSpec.supported) {
      if (candidate.label == parts[0]) spec = candidate;
    }
    if (spec == null) {
      throw FormatException(
        'expected one of ${TracksSpec.supported.map((s) => s.label).join(', ')}, '
        'got "${parts[0]}"',
        line,
        0,
      );
    }

    final startRow = _decimal(parts[1], line, 'start row');
    final goalColumn = _decimal(parts[2], line, 'goal column');
    final rowCounts = [
      for (final text in parts[3].split(',')) _decimal(text, line, 'row count'),
    ];
    final columnCounts = [
      for (final text in parts[4].split(','))
        _decimal(text, line, 'column count'),
    ];

    final fixed = List<int>.filled(spec.cells, 0);
    if (parts[5].isNotEmpty) {
      var previous = -1;
      for (final pair in parts[5].split(',')) {
        final halves = pair.split(':');
        if (halves.length != 2) {
          throw FormatException('expected index:mask, got "$pair"', line);
        }
        final index = _decimal(halves[0], line, 'fixed index');
        final mask = _decimal(halves[1], line, 'fixed mask');
        if (index >= spec.cells) {
          throw FormatException(
            'expected a fixed index below ${spec.cells}, got $index',
            line,
          );
        }
        // Strictly ascending, so one puzzle has one spelling.
        if (index <= previous) {
          throw FormatException(
            'expected ascending fixed indices, got $index after $previous',
            line,
          );
        }
        previous = index;
        fixed[index] = mask;
      }
    }

    final TracksClues decoded;
    try {
      decoded = TracksClues(
        spec: spec,
        startRow: startRow,
        goalColumn: goalColumn,
        rowCounts: rowCounts,
        columnCounts: columnCounts,
        fixed: fixed,
      );
    } on ArgumentError catch (e) {
      throw FormatException('${e.message}', line);
    }
    // The checks above refuse the spellings they know about; this refuses any
    // they do not, and is what makes the form canonical: a line is accepted
    // only if re-encoding the board it describes gives back that exact line.
    // A mask of 0 written out as "5:0", for one, parses to a board with no
    // fixed cell there and fails here.
    if (decoded.encode() != line) {
      throw FormatException('not the canonical spelling', line);
    }
    return decoded;
  }

  /// Rejects a count list of the wrong length or with an impossible count.
  static void _checkCounts(String name, List<int> counts, int side) {
    if (counts.length != side) {
      throw ArgumentError.value(counts.length, name, 'must have $side entries');
    }
    for (final count in counts) {
      if (count < 0 || count > side) {
        throw ArgumentError.value(count, name, 'must be in 0..$side');
      }
    }
  }

  /// A canonical non-negative decimal, or a [FormatException].
  static int _decimal(String text, String line, String what) {
    final value = int.tryParse(text);
    // The round trip through the canonical spelling rejects a leading zero, a
    // sign and a leading plus in one comparison.
    if (value == null || value < 0 || '$value' != text) {
      throw FormatException(
        'expected a decimal $what with no leading zeros, got "$text"',
        line,
      );
    }
    return value;
  }

  /// The grid's size.
  final TracksSpec spec;

  /// The start port's row: it is on the west edge, so cell `(startRow, 0)` has
  /// its west bit.
  final int startRow;

  /// The goal port's column: it is on the south edge, so cell
  /// `(side - 1, goalColumn)` has its south bit.
  final int goalColumn;

  /// Track cells per row, north to south.
  final List<int> rowCounts;

  /// Track cells per column, west to east.
  final List<int> columnCounts;

  /// Per cell, row-major: 0, or the piece already laid there.
  final List<int> fixed;

  /// The index of the start cell.
  int get startCell => spec.indexAt(startRow, 0);

  /// The index of the goal cell.
  int get goalCell => spec.indexAt(spec.side - 1, goalColumn);

  /// The one-line form for the cache and the goldens, frozen by PR 2:
  ///
  /// ```
  /// 7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5,24:12
  /// ```
  ///
  /// Size, start row, goal column, the row counts, the column counts, then the
  /// fixed cells as `index:mask` pairs in ascending index order, all decimal.
  /// The last field is empty when nothing is fixed, so the line then ends in
  /// `|`. It contains no spaces, so a golden can put it after other
  /// space-separated fields.
  ///
  /// The solution is not in the line. It is regenerated, or recovered from the
  /// clues by the solver, which is cheap, and leaving it out keeps the line
  /// short (`PLAN-phase-9-tracks.md` §4.3).
  String encode() {
    final pairs = <String>[];
    for (var i = 0; i < fixed.length; i++) {
      if (fixed[i] != 0) pairs.add('$i:${fixed[i]}');
    }
    return '${spec.label}|$startRow|$goalColumn|'
        '${rowCounts.join(',')}|${columnCounts.join(',')}|${pairs.join(',')}';
  }

  @override
  bool operator ==(Object other) =>
      other is TracksClues &&
      other.spec == spec &&
      other.startRow == startRow &&
      other.goalColumn == goalColumn &&
      _same(other.rowCounts, rowCounts) &&
      _same(other.columnCounts, columnCounts) &&
      _same(other.fixed, fixed);

  @override
  int get hashCode => Object.hash(
    spec,
    startRow,
    goalColumn,
    Object.hashAll(rowCounts),
    Object.hashAll(columnCounts),
    Object.hashAll(fixed),
  );

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => encode();
}
