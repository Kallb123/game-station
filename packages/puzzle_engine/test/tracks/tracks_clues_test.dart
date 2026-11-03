// The clue line is what the cache and the PR 3 goldens store, so its spelling
// is frozen: the hand-written line below is the format's record, and the
// rejects are what stop two spellings of one puzzle from existing.

import 'package:puzzle_engine/src/tracks/track_side.dart';
import 'package:puzzle_engine/src/tracks/tracks_clues.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';
import 'package:test/test.dart';

const String line = '7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5,24:12';

TracksClues sevenBySeven() {
  final fixed = List<int>.filled(49, 0);
  fixed[10] = TrackSide.north | TrackSide.south;
  fixed[24] = TrackSide.south | TrackSide.west;
  return TracksClues(
    spec: TracksSpec.s7x7,
    startRow: 3,
    goalColumn: 4,
    rowCounts: const [2, 4, 3, 1, 3, 2, 1],
    columnCounts: const [1, 2, 3, 3, 2, 4, 1],
    fixed: fixed,
  );
}

TracksClues fiveByFive({
  int startRow = 1,
  int goalColumn = 2,
  List<int>? rowCounts,
  List<int>? columnCounts,
  Map<int, int> fixed = const {},
}) {
  final cells = List<int>.filled(25, 0);
  fixed.forEach((i, mask) => cells[i] = mask);
  return TracksClues(
    spec: TracksSpec.s5x5,
    startRow: startRow,
    goalColumn: goalColumn,
    rowCounts: rowCounts ?? const [1, 3, 2, 1, 2],
    columnCounts: columnCounts ?? const [2, 2, 3, 1, 1],
    fixed: cells,
  );
}

void main() {
  group('encode', () {
    test('matches the hand-written line exactly', () {
      expect(sevenBySeven().encode(), line);
      expect(sevenBySeven().toString(), line);
    });

    test('ends in a bar when nothing is fixed', () {
      expect(fiveByFive().encode(), '5x5|1|2|1,3,2,1,2|2,2,3,1,1|');
    });

    test('contains no spaces', () {
      expect(sevenBySeven().encode().contains(' '), isFalse);
    });

    test('lists fixed cells in ascending index order', () {
      final clues = fiveByFive(fixed: {18: 6, 7: 5, 12: 10});
      expect(clues.encode().split('|').last, '7:5,12:10,18:6');
    });
  });

  group('decode', () {
    test('reads the hand-written line', () {
      expect(TracksClues.decode(line), sevenBySeven());
    });

    test('round-trips for several shapes, with and without fixed cells', () {
      final shapes = [
        sevenBySeven(),
        fiveByFive(),
        fiveByFive(fixed: {7: 5, 12: 10}),
        // The port cells themselves may be fixed, with their outward bit.
        fiveByFive(
          startRow: 4,
          goalColumn: 0,
          fixed: {20: TrackSide.south | TrackSide.west},
        ),
        fiveByFive(fixed: {5: TrackSide.east | TrackSide.west}),
      ];
      for (final clues in shapes) {
        final decoded = TracksClues.decode(clues.encode());
        expect(decoded, clues, reason: clues.encode());
        expect(decoded.hashCode, clues.hashCode);
        expect(decoded.encode(), clues.encode());
      }
    });

    test('derives the port cells', () {
      final clues = sevenBySeven();
      expect(clues.startCell, 21);
      expect(clues.goalCell, 46);
    });

    void rejects(String text) {
      expect(
        () => TracksClues.decode(text),
        throwsA(isA<FormatException>()),
        reason: text,
      );
    }

    test('non-canonical numbers', () {
      rejects('7x7|03|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5,24:12');
      rejects('7x7|+3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5,24:12');
      rejects('7x7|3|4|2,4,3,1,3,2,01|1,2,3,3,2,4,1|10:5,24:12');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|010:5,24:12');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:05,24:12');
      rejects('7x7|-3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5');
    });

    test('unsorted or duplicate fixed indices', () {
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|24:12,10:5');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5,10:5');
    });

    test('a fixed entry that is malformed or out of range', () {
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|49:5');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5:1');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:5,');
    });

    test('a mask that is not a piece', () {
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:0');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:1');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:7');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|10:15');
    });

    test('an off-grid bit away from a port', () {
      // West bit in column 0 on a cell that is not the start cell (start is
      // row 3, so index 7 is (1, 0)): SW = 12.
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|7:12');
      // North bit in row 0.
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|2:5');
      // East bit in the last column (index 13 is (1, 6)).
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|13:3');
      // South bit in the last row away from the goal column (index 42 is
      // (6, 0); the goal column is 4).
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|42:6');
    });

    test('an unknown size', () {
      rejects('8x8|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|');
      rejects('6x6|3|4|2,4,3,1,3,2|1,2,3,3,2,4|');
      rejects('|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|');
    });

    test('a count list of the wrong length or range', () {
      rejects('7x7|3|4|2,4,3,1,3,2|1,2,3,3,2,4,1|');
      rejects('7x7|3|4|2,4,3,1,3,2,1,1|1,2,3,3,2,4,1|');
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4|');
      rejects('7x7|3|4|2,4,3,1,3,2,8|1,2,3,3,2,4,1|');
      rejects('7x7|3|4||1,2,3,3,2,4,1|');
    });

    test('a port outside the grid', () {
      rejects('7x7|7|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1|');
      rejects('7x7|3|7|2,4,3,1,3,2,1|1,2,3,3,2,4,1|');
    });

    test('the wrong number of fields', () {
      rejects('7x7|3|4|2,4,3,1,3,2,1|1,2,3,3,2,4,1');
      rejects('$line|');
      rejects('');
    });

    test('trailing or leading whitespace', () {
      rejects('$line ');
      rejects('$line\n');
      rejects(' $line');
    });
  });

  group('the constructor', () {
    test('keeps unmodifiable copies, so a caller cannot edit the puzzle', () {
      final rows = [1, 3, 2, 1, 2];
      final cells = List<int>.filled(25, 0);
      final clues = TracksClues(
        spec: TracksSpec.s5x5,
        startRow: 1,
        goalColumn: 2,
        rowCounts: rows,
        columnCounts: const [2, 2, 3, 1, 1],
        fixed: cells,
      );
      rows[0] = 5;
      cells[7] = 5;
      expect(clues.rowCounts[0], 1);
      expect(clues.fixed[7], 0);
      expect(() => clues.rowCounts[0] = 2, throwsUnsupportedError);
      expect(() => clues.columnCounts[0] = 2, throwsUnsupportedError);
      expect(() => clues.fixed[0] = 5, throwsUnsupportedError);
    });

    test('accepts the port bits on the port cells', () {
      // Start cell (1, 0) = index 5, goal cell (4, 2) = index 22.
      fiveByFive(fixed: {5: TrackSide.east | TrackSide.west});
      fiveByFive(fixed: {22: TrackSide.north | TrackSide.south});
    });

    test('does not check solvability or neighbour agreement', () {
      // Two fixed neighbours that disagree about their shared edge: the
      // counter's question, not the constructor's.
      fiveByFive(fixed: {7: TrackSide.north | TrackSide.south, 8: 5});
      fiveByFive(
        rowCounts: const [0, 0, 0, 0, 0],
        columnCounts: const [0, 0, 0, 0, 0],
      );
    });

    void throwsFor(String reason, TracksClues Function() build) {
      test('throws an ArgumentError for $reason', () {
        expect(build, throwsArgumentError);
      });
    }

    throwsFor('a start row off the grid', () => fiveByFive(startRow: 5));
    throwsFor('a negative start row', () => fiveByFive(startRow: -1));
    throwsFor('a goal column off the grid', () => fiveByFive(goalColumn: 5));
    throwsFor(
      'a short row-count list',
      () => fiveByFive(rowCounts: const [1, 3, 2, 1]),
    );
    throwsFor(
      'a long column-count list',
      () => fiveByFive(columnCounts: const [2, 2, 3, 1, 1, 0]),
    );
    throwsFor(
      'a count above the side',
      () => fiveByFive(rowCounts: const [1, 3, 2, 1, 6]),
    );
    throwsFor(
      'a negative count',
      () => fiveByFive(columnCounts: const [2, 2, 3, 1, -1]),
    );
    throwsFor(
      'a fixed entry that is not a piece',
      () => fiveByFive(fixed: {7: 1}),
    );
    throwsFor('a fixed entry with three bits', () => fiveByFive(fixed: {7: 7}));
    throwsFor('a north bit in row 0', () => fiveByFive(fixed: {2: 5}));
    throwsFor(
      'an east bit in the last column',
      () => fiveByFive(fixed: {9: 3}),
    );
    throwsFor(
      'a west bit in column 0 away from the start',
      () => fiveByFive(fixed: {10: TrackSide.south | TrackSide.west}),
    );
    throwsFor(
      'a south bit in the last row away from the goal',
      () => fiveByFive(fixed: {20: TrackSide.east | TrackSide.south}),
    );
    test('throws an ArgumentError for a fixed list of the wrong length', () {
      expect(
        () => TracksClues(
          spec: TracksSpec.s5x5,
          startRow: 1,
          goalColumn: 2,
          rowCounts: const [1, 3, 2, 1, 2],
          columnCounts: const [2, 2, 3, 1, 1],
          fixed: List<int>.filled(24, 0),
        ),
        throwsArgumentError,
      );
    });
  });

  test('equality distinguishes every field', () {
    final base = fiveByFive();
    expect(base, fiveByFive());
    expect(base, isNot(fiveByFive(startRow: 2)));
    expect(base, isNot(fiveByFive(goalColumn: 3)));
    expect(base, isNot(fiveByFive(rowCounts: const [1, 3, 2, 2, 2])));
    expect(base, isNot(fiveByFive(columnCounts: const [2, 2, 3, 2, 1])));
    expect(base, isNot(fiveByFive(fixed: {7: 5})));
  });
}
