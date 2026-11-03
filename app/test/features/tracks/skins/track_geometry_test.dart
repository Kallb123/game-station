// The shared route line (`PLAN-phase-9-tracks.md` §4.8, §6 PR 6): where the
// traveller is at the start, the middle and the end, on routes whose expected
// cells are worked out by hand from the segment lengths.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/features/tracks/skins/track_geometry.dart';
import 'package:zibo_games/features/tracks/skins/track_skin.dart';

import '../tracks_fixtures.dart';

const int _n = TrackSide.north;
const int _e = TrackSide.east;
const int _s = TrackSide.south;
const int _w = TrackSide.west;

/// Clues over a 5x5 grid. Counts and fixed pieces are irrelevant to the
/// geometry, which reads only the ports and the board it is handed.
TracksClues _clues({required int startRow, required int goalColumn}) =>
    TracksClues(
      spec: TracksSpec.s5x5,
      startRow: startRow,
      goalColumn: goalColumn,
      rowCounts: List.filled(5, 0),
      columnCounts: List.filled(5, 0),
      fixed: List.filled(25, 0),
    );

/// A 5x5 board from `(row, column): mask` entries.
List<int> _board(Map<(int, int), int> masks) {
  final cells = List<int>.filled(25, 0);
  masks.forEach((at, mask) => cells[at.$1 * 5 + at.$2] = mask);
  return cells;
}

/// Straight row from the west port, then south to the goal port:
///
///     (0,0) (0,1) (0,2)
///                   |
///                 (1,2) (2,2) (3,2) (4,2) -> goal port
final _straightThenTurn = (
  clues: _clues(startRow: 0, goalColumn: 2),
  cells: _board({
    (0, 0): _w | _e,
    (0, 1): _w | _e,
    (0, 2): _w | _s,
    (1, 2): _n | _s,
    (2, 2): _n | _s,
    (3, 2): _n | _s,
    (4, 2): _n | _s,
  }),
);

/// Five corners:
///
///     start -> (2,0) (2,1) (2,2)
///                          (1,2) (1,3)
///                                (2,3)
///                          (3,2) (3,3)
///                          (4,2) -> goal port
final _manyCorners = (
  clues: _clues(startRow: 2, goalColumn: 2),
  cells: _board({
    (2, 0): _w | _e,
    (2, 1): _w | _e,
    (2, 2): _w | _n,
    (1, 2): _s | _e,
    (1, 3): _w | _s,
    (2, 3): _n | _s,
    (3, 3): _n | _w,
    (3, 2): _e | _s,
    (4, 2): _n | _s,
  }),
);

/// Segment length of a cell holding [mask]: a straight or a quarter circle.
double _cellLength(int mask) =>
    (mask == (_n | _s) || mask == (_e | _w)) ? 1 : math.pi / 4;

void main() {
  group('trace', () {
    test('builds the route square by square, ports included', () {
      final route = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      expect(route.route, [
        (0, -1),
        (0, 0),
        (0, 1),
        (0, 2),
        (1, 2),
        (2, 2),
        (3, 2),
        (4, 2),
        (5, 2),
      ]);
    });

    test('is null for a board with nothing laid', () {
      expect(
        TrackGeometry.trace(_straightThenTurn.clues, List.filled(25, 0)),
        isNull,
      );
    });

    test('is null when the goal cell does not leave south', () {
      final cells = [..._straightThenTurn.cells];
      cells[4 * 5 + 2] = _n | _e;
      cells[4 * 5 + 3] = _w | _e;
      expect(TrackGeometry.trace(_straightThenTurn.clues, cells), isNull);
    });

    test('is null for a dangling end', () {
      final cells = [..._straightThenTurn.cells];
      // A one-bit stub where the neighbour returns the bit but cannot go on.
      cells[3 * 5 + 2] = _n;
      expect(TrackGeometry.trace(_straightThenTurn.clues, cells), isNull);
      // A neighbour that does not return the bit at all.
      cells[3 * 5 + 2] = 0;
      expect(TrackGeometry.trace(_straightThenTurn.clues, cells), isNull);
    });

    test('is null for a cell holding three bits', () {
      final cells = [..._straightThenTurn.cells];
      cells[1 * 5 + 2] = _n | _s | _e;
      expect(TrackGeometry.trace(_straightThenTurn.clues, cells), isNull);
    });

    test('is null for a loop that never reaches the goal', () {
      // The ring returns to the start cell, which has no bit to take the
      // walk back in, so the walk cannot run on.
      final cells = _board({
        (0, 0): _w | _s,
        (1, 0): _n | _e,
        (1, 1): _w | _n,
        (0, 1): _s | _w,
      });
      expect(
        TrackGeometry.trace(_clues(startRow: 0, goalColumn: 2), cells),
        isNull,
      );
    });

    test('is null when the track leaves the grid away from the goal', () {
      final cells = _board({(0, 0): _w | _n});
      expect(
        TrackGeometry.trace(_clues(startRow: 0, goalColumn: 2), cells),
        isNull,
      );
    });
  });

  group('length', () {
    test('is two half ports, the straights and pi/4 per corner', () {
      final a = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      // Straights: (0,0) (0,1) (1,2) (2,2) (3,2) (4,2) = 6. One corner.
      expect(a.length, closeTo(0.5 + 0.5 + 6 + 1 * math.pi / 4, 1e-9));

      final b = TrackGeometry.trace(_manyCorners.clues, _manyCorners.cells)!;
      // Straights: (2,0) (2,1) (2,3) (4,2) = 4. Five corners.
      expect(b.length, closeTo(0.5 + 0.5 + 4 + 5 * math.pi / 4, 1e-9));
    });
  });

  group('positionAt on a fixture route', () {
    test('straight row then a turn south', () {
      final route = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      expect(route.positionAt(0), (0, -1));
      // Half of 7.785 is 3.893. Segments end at 0.5 (port), 1.5, 2.5 (row
      // straights), 3.285 (the corner), 4.285 (cell (1,2)): 3.893 is in the
      // last of those.
      expect(route.positionAt(0.5), (1, 2));
      expect(route.positionAt(1), (5, 2));
    });

    test('a route with several corners', () {
      final route = TrackGeometry.trace(
        _manyCorners.clues,
        _manyCorners.cells,
      )!;
      expect(route.positionAt(0), (2, -1));
      // Half of 8.927 is 4.464. Segments end at 0.5, 1.5, 2.5, then the
      // corners at (2,2) 3.285, (1,2) 4.071 and (1,3) 4.856: 4.464 is in
      // (1,3).
      expect(route.positionAt(0.5), (1, 3));
      expect(route.positionAt(1), (5, 2));
    });

    test('a route from a generated puzzle', () {
      final puzzle = puzzleFor('tracks:7x7:medium:0');
      final route = TrackGeometry.trace(puzzle.clues, puzzle.solution)!;
      final spec = puzzle.id.spec;

      // The reference: walk the solution's cells summing segment lengths, the
      // two ports being half a cell each, and take the square whose segment
      // holds half the total.
      final squares = [
        (puzzle.clues.startRow, -1),
        for (final cell in solutionPath(puzzle)) positionOf(spec, cell),
        (spec.side, puzzle.clues.goalColumn),
      ];
      final lengths = [
        0.5,
        for (final cell in solutionPath(puzzle))
          _cellLength(puzzle.solution[cell]),
        0.5,
      ];
      final total = lengths.reduce((a, b) => a + b);
      var reached = 0.0;
      var expected = squares.last;
      for (var i = 0; i < lengths.length; i++) {
        if (total / 2 < reached + lengths[i]) {
          expected = squares[i];
          break;
        }
        reached += lengths[i];
      }

      expect(route.route, squares);
      expect(route.length, closeTo(total, 1e-9));
      expect(route.positionAt(0), squares.first);
      expect(route.positionAt(0.5), expected);
      expect(route.positionAt(1), squares.last);
    });

    test('the grid edge is where the port ends and the first cell begins', () {
      final route = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      // The edge is 0.5 grid units in. Either side of it, not on it, because
      // t * length does not round-trip exactly; the boundary rule itself
      // (the later square owns it) is the `>` in the lookup.
      expect(route.positionAt(0.4999 / route.length), (0, -1));
      expect(route.positionAt(0.5001 / route.length), (0, 0));
    });
  });

  group('pointAt and directionAt', () {
    test('the ends are the port centres', () {
      final a = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      expect(a.pointAt(0), const Offset(-0.5, 0.5));
      expect(a.pointAt(1).dx, closeTo(2.5, 1e-9));
      expect(a.pointAt(1).dy, closeTo(5.5, 1e-9));

      final b = TrackGeometry.trace(_manyCorners.clues, _manyCorners.cells)!;
      expect(b.pointAt(0), const Offset(-0.5, 2.5));
      expect(b.pointAt(1).dx, closeTo(2.5, 1e-9));
      expect(b.pointAt(1).dy, closeTo(5.5, 1e-9));
    });

    test('t is clamped to 0..1', () {
      final a = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      expect(a.pointAt(-3), a.pointAt(0));
      expect(a.pointAt(7), a.pointAt(1));
    });

    test('the direction is a unit vector all along both routes', () {
      for (final fixture in [_straightThenTurn, _manyCorners]) {
        final route = TrackGeometry.trace(fixture.clues, fixture.cells)!;
        for (var i = 0; i <= 200; i++) {
          expect(route.directionAt(i / 200).distance, closeTo(1, 1e-9));
        }
      }
    });

    test('the direction points the way the route goes', () {
      final a = TrackGeometry.trace(
        _straightThenTurn.clues,
        _straightThenTurn.cells,
      )!;
      expect(a.directionAt(0), const Offset(1, 0));
      expect(a.directionAt(1), const Offset(0, 1));
      // Moving west on the route that doubles back: (1,2) to (1,3) heads east
      // while (3,3) to (3,2) heads west.
      final b = TrackGeometry.trace(_manyCorners.clues, _manyCorners.cells)!;
      var sawWest = false;
      for (var i = 0; i <= 400; i++) {
        if (b.directionAt(i / 400).dx < -0.5) sawWest = true;
      }
      expect(sawWest, isTrue);
    });

    test(
      'a corner is a quarter circle of radius 0.5 about the cell corner',
      () {
        final a = TrackGeometry.trace(
          _straightThenTurn.clues,
          _straightThenTurn.cells,
        )!;
        // The corner in (0,2) turns about (2, 1): the point halfway along it is
        // 0.5 from there.
        final middle = (2.5 + math.pi / 8) / a.length;
        expect(
          (a.pointAt(middle) - const Offset(2, 1)).distance,
          closeTo(0.5, 1e-9),
        );
      },
    );
  });

  group('toPath', () {
    final layout = BoardLayout.fit(const Size(400, 400), 5);

    test('a partial path stays within the full path\'s bounds', () {
      for (final fixture in [_straightThenTurn, _manyCorners]) {
        final route = TrackGeometry.trace(fixture.clues, fixture.cells)!;
        final full = route.toPath(layout).getBounds().inflate(1e-6);
        for (final upTo in [0.25, 0.5, 0.75]) {
          final partial = route.toPath(layout, upTo: upTo).getBounds();
          expect(full.contains(partial.topLeft), isTrue, reason: '$upTo');
          expect(full.contains(partial.bottomRight), isTrue, reason: '$upTo');
        }
      }
    });

    test('ends where pointAt says, in canvas coordinates', () {
      final route = TrackGeometry.trace(
        _manyCorners.clues,
        _manyCorners.cells,
      )!;
      for (final upTo in [0.3, 0.5, 1.0]) {
        final metrics = route.toPath(layout, upTo: upTo).computeMetrics();
        final last = metrics.last;
        final end = last.getTangentForOffset(last.length)!.position;
        final expected = layout.toCanvas(route.pointAt(upTo));
        expect((end - expected).distance, lessThan(0.5), reason: '$upTo');
      }
    });

    test('a longer reach makes a longer path', () {
      final route = TrackGeometry.trace(
        _manyCorners.clues,
        _manyCorners.cells,
      )!;
      double lengthOf(double upTo) => route
          .toPath(layout, upTo: upTo)
          .computeMetrics()
          .fold(0.0, (sum, m) => sum + m.length);
      expect(lengthOf(0.5), lessThan(lengthOf(1)));
      expect(lengthOf(1), closeTo(route.length * layout.cellSize, 1.0));
    });
  });
}
