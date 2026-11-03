// The Tracks session's tests: every stroke rule of `PLAN-phase-9-tracks.md`
// §4.7 is a case here, which is PR 5's done-criterion.
//
// Plain `test()` calls with no `pumpWidget`, because the model imports nothing
// of Flutter beyond `foundation.dart`, so the whole file runs in milliseconds.
//
// The puzzles are real, from `generateTracks`. Cases that need a particular
// shape (a start cell that is not fixed, a cell beside a fixed piece) find one
// by scanning indices in `tracks_fixtures.dart` and fail loudly if the scan
// finds nothing, so a generator change cannot make a test silently skip its
// own subject. The 500-puzzle replay lives in `tracks_replay_test.dart`.

import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/model/tracks_session.dart';
import 'package:zibo_games/features/tracks/model/tracks_session_codec.dart';

import '../tracks_fixtures.dart';

const int _n = TrackSide.north;
const int _e = TrackSide.east;
const int _s = TrackSide.south;
const int _w = TrackSide.west;

/// A puzzle whose first stretch of track is open ground, so a test can lay
/// along the solution without meeting a fixed piece.
typedef Plain = ({List<int> path, int? sideCell, int wrongCell});

/// The probe for [Plain]: the start, the next two path cells and the goal hold
/// nothing at the start; some empty cell sits beside the second path cell (to
/// bump into a cell with two connections) and some beside the first that the
/// solution does not use (to lay a wrong connection into).
Plain? plainProbe(TracksPuzzle puzzle) {
  final spec = puzzle.id.spec;
  final board = initialBoard(puzzle.clues);
  final path = solutionPath(puzzle);
  if (path.length < 4) return null;
  for (final cell in [path[0], path[1], path[2], path.last]) {
    if (board[cell] != 0) return null;
  }
  int? sideCell;
  for (final n in neighboursOf(spec, path[1])) {
    if (!path.take(3).contains(n.cell) && board[n.cell] == 0) {
      sideCell = n.cell;
    }
  }
  int? wrongCell;
  for (final n in neighboursOf(spec, path[0])) {
    if (n.cell != path[1] && board[n.cell] == 0) wrongCell = n.cell;
  }
  if (sideCell == null || wrongCell == null) return null;
  return (path: path, sideCell: sideCell, wrongCell: wrongCell);
}

/// The top-left (row, column) of a 3x3 block of cells that all start empty.
Position? emptyBlock(TracksPuzzle puzzle) {
  final spec = puzzle.id.spec;
  final board = initialBoard(puzzle.clues);
  for (var row = 0; row + 2 < spec.side; row++) {
    for (var column = 0; column + 2 < spec.side; column++) {
      var empty = true;
      for (var dr = 0; dr < 3; dr++) {
        for (var dc = 0; dc < 3; dc++) {
          if (board[spec.indexAt(row + dr, column + dc)] != 0) empty = false;
        }
      }
      if (empty) return (row, column);
    }
  }
  return null;
}

/// A fixed piece with an open end: a side of the piece that points at a free
/// cell, which starts with nothing on it.
typedef OpenEnd = ({int fixed, int side, int free});

OpenEnd? openEnd(TracksPuzzle p) {
  final spec = p.id.spec;
  for (var cell = 0; cell < spec.cells; cell++) {
    if (p.clues.fixed[cell] == 0) continue;
    for (final n in neighboursOf(spec, cell)) {
      if (p.clues.fixed[cell] & n.side != 0 && p.clues.fixed[n.cell] == 0) {
        return (fixed: cell, side: n.side, free: n.cell);
      }
    }
  }
  return null;
}

/// A fixed piece with a closed side that faces a free cell.
OpenEnd? closedSide(TracksPuzzle p) {
  final spec = p.id.spec;
  for (var cell = 0; cell < spec.cells; cell++) {
    if (p.clues.fixed[cell] == 0) continue;
    for (final n in neighboursOf(spec, cell)) {
      if (p.clues.fixed[cell] & n.side == 0 && p.clues.fixed[n.cell] == 0) {
        return (fixed: cell, side: n.side, free: n.cell);
      }
    }
  }
  return null;
}

void main() {
  final plain = findPuzzle<Plain>(plainProbe);
  final puzzle = plain.puzzle;
  final spec = puzzle.id.spec;
  final clues = puzzle.clues;
  final path = plain.found.path;
  final startRow = clues.startRow;

  TracksSession start({MistakeFeedback feedback = MistakeFeedback.immediate}) =>
      startSession(puzzle, feedback: feedback);

  Position at(int cell) => positionOf(spec, cell);

  /// The side of [from] that faces the adjacent [to].
  int facing(int from, int to) {
    for (final n in neighboursOf(spec, from)) {
      if (n.cell == to) return n.side;
    }
    throw StateError('$from and $to are not adjacent');
  }

  group('a fresh session', () {
    test('holds the fixed pieces exactly, open ends unanswered', () {
      // A fixed piece's bit toward a free cell is an open end: seeding the
      // neighbour's answer would complete cells the child never touched.
      final withFixed = findPuzzle<int>(
        (p) => openEnd(p) == null ? null : 1,
      ).puzzle;
      final session = startSession(withFixed);
      final end = openEnd(withFixed)!;

      expect(session.cells, withFixed.clues.fixed);
      expect(session.maskAt(end.free), 0);
      expect(session.maskAt(end.fixed) & end.side, end.side);
      for (var cell = 0; cell < withFixed.id.spec.cells; cell++) {
        expect(session.isFixed(cell), withFixed.clues.fixed[cell] != 0);
        expect(session.isMarked(cell), isFalse);
      }
    });

    test('is not solved when a free cell sits between two fixed pieces', () {
      // The first puzzle of the first combination: 13% of 5x5 Easy puzzles
      // opened already solved while the neighbours' reciprocals were seeded.
      final first = puzzleFor('tracks:5x5:easy:0');
      final session = startSession(first);

      expect(session.isJoined, isFalse);
      expect(session.isSolved, isFalse);
    });

    test('no offered puzzle opens solved', () {
      for (final (size, difficulty) in offeredCombos) {
        for (var index = 0; index < 200; index++) {
          final p = puzzleFor('tracks:${size.label}:${difficulty.name}:$index');
          expect(startSession(p).isSolved, isFalse, reason: '${p.id}');
        }
      }
    });

    test('starts clean: no mistakes, hints or history, and not solved', () {
      final session = start();

      expect(session.mistakes, 0);
      expect(session.hints, 0);
      expect(session.elapsed, Duration.zero);
      expect(session.canUndo, isFalse);
      expect(session.canRedo, isFalse);
      expect(session.isSolved, isFalse);
      expect(session.isJoined, isFalse);
      expect(session.isStroking, isFalse);
      expect(session.pointedAt, isNull);
      expect(session.takeEvent(), isNull);
    });

    test('exposes cells as a view that cannot be written', () {
      expect(() => start().cells[0] = 1, throwsUnsupportedError);
    });

    test('refuses a solution of the wrong length or clues of another size', () {
      expect(
        () => TracksSession.start(
          id: puzzle.id,
          clues: clues,
          solution: puzzle.solution.sublist(1),
        ),
        throwsArgumentError,
      );
      final other = puzzleFor('tracks:7x7:easy:0');
      expect(
        () => TracksSession.start(
          id: puzzle.id,
          clues: other.clues,
          solution: puzzle.solution,
        ),
        throwsArgumentError,
      );
    });

    test('fixedSides is the part of a cell that can never be lifted', () {
      final probe = findPuzzle<int>((p) => openEnd(p) == null ? null : 1);
      final session = startSession(probe.puzzle);
      final end = openEnd(probe.puzzle)!;

      expect(
        session.fixedSides(end.fixed),
        probe.puzzle.clues.fixed[end.fixed],
      );
      // The free cell beside an open end has nothing fixed on it, even once
      // its own half of the join is laid: that half is the child's to lift.
      expect(session.isFixed(end.free), isFalse);
      expect(session.fixedSides(end.free), 0);
      stroke(session, [
        positionOf(probe.puzzle.id.spec, end.free),
        positionOf(probe.puzzle.id.spec, end.fixed),
      ]);
      expect(session.maskAt(end.free), isNot(0));
      expect(session.fixedSides(end.free), 0);
    });
  });

  group('a stroke', () {
    test('lays connections between adjacent cells, both halves', () {
      final session = start();

      stroke(session, [at(path[0]), at(path[1]), at(path[2])]);

      expect(session.maskAt(path[0]), facing(path[0], path[1]));
      expect(
        session.maskAt(path[1]),
        facing(path[1], path[0]) | facing(path[1], path[2]),
      );
      expect(session.maskAt(path[2]), facing(path[2], path[1]));
      expect(session.takeEvent(), TracksEvent.laid);
    });

    test('from the start port sets the start cell\'s west bit', () {
      final session = start()..beginStroke(startRow, -1);

      session.strokeTo(startRow, 0);

      expect(session.maskAt(clues.startCell), _w);
      expect(session.takeEvent(), TracksEvent.laid);
    });

    test('into the goal port sets the goal cell\'s south bit', () {
      final goal = clues.goalCell;
      final session = start()..beginStroke(spec.side - 1, clues.goalColumn);

      session.strokeTo(spec.side, clues.goalColumn);

      expect(session.maskAt(goal), _s);
      expect(session.takeEvent(), TracksEvent.laid);
    });

    test('into the start port from the first cell does the same', () {
      final session = start()..beginStroke(startRow, 0);

      session.strokeTo(startRow, -1);

      expect(session.maskAt(clues.startCell), _w);
    });

    test('a port that is not the start or the goal is off the board', () {
      final otherRow = (startRow + 1) % spec.side;
      final cell = spec.indexAt(otherRow, 0);
      final session = start()..beginStroke(otherRow, 0);

      session.strokeTo(otherRow, -1);

      expect(session.maskAt(cell), 0);
      expect(session.takeEvent(), TracksEvent.refused);
    });

    test('is a stroke only between begin and end', () {
      final session = start();
      expect(session.isStroking, isFalse);

      session.beginStroke(startRow, -1);
      expect(session.isStroking, isTrue);

      session.endStroke();
      expect(session.isStroking, isFalse);
    });

    test(
      'strokeTo without a stroke, or to where the finger is, does nothing',
      () {
        final session = start();
        var notifications = 0;
        session.addListener(() => notifications++);

        session.strokeTo(startRow, 0);
        session.endStroke();
        session.beginStroke(startRow, -1);
        session.strokeTo(startRow, -1);

        expect(session.cells, initialBoard(clues));
        expect(notifications, 0);
      },
    );

    test('notifies once per call, however many cells the call walked', () {
      final session = start();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.beginStroke(startRow, -1);
      expect(notifications, 0);
      session.strokeTo(startRow, 2);
      expect(notifications, 1);
      session.endStroke();
      expect(notifications, 2);
    });
  });

  group('retracing', () {
    test('lifts the connection just laid', () {
      final session = start();
      final before = snapshotOf(session);

      session.beginStroke(at(path[0]).$1, at(path[0]).$2);
      session.strokeTo(at(path[1]).$1, at(path[1]).$2);
      expect(session.maskAt(path[0]), isNot(0));
      session.takeEvent();
      session.strokeTo(at(path[0]).$1, at(path[0]).$2);

      expectBoard(session, before);
      expect(session.takeEvent(), TracksEvent.lifted);
    });

    test('lifts several in a row, as far back as the finger goes', () {
      final session = start();
      final before = snapshotOf(session);
      final positions = [for (var i = 0; i < 4; i++) at(path[i])];

      session.beginStroke(positions[0].$1, positions[0].$2);
      for (final p in positions.skip(1)) {
        session.strokeTo(p.$1, p.$2);
      }
      for (final p in positions.reversed.skip(1)) {
        session.strokeTo(p.$1, p.$2);
      }

      expectBoard(session, before);
    });

    test('over a connection that existed before the stroke lifts nothing', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      final laid = snapshotOf(session);
      final undoable = session.canUndo;

      session.beginStroke(at(path[0]).$1, at(path[0]).$2);
      session.strokeTo(at(path[1]).$1, at(path[1]).$2);
      session.strokeTo(at(path[0]).$1, at(path[0]).$2);
      session.endStroke();

      expectBoard(session, laid);
      expect(undoable, isTrue);
      session.undo();
      // One entry only: the retraced stroke added none of its own.
      expect(session.canUndo, isFalse);
    });

    test('a drag across a marked cell and straight back is no move', () {
      final session = start()..toggleMark(path[1]);
      final marked = snapshotOf(session);
      session.undo();
      session.redo();

      session.beginStroke(at(path[0]).$1, at(path[0]).$2);
      session.strokeTo(at(path[1]).$1, at(path[1]).$2);
      expect(session.isMarked(path[1]), isFalse, reason: 'laid over the mark');
      session.strokeTo(at(path[0]).$1, at(path[0]).$2);
      session.endStroke();

      expectBoard(session, marked);
      // The mark's own toggle is the only entry; the stroke added none.
      session.undo();
      expect(session.isMarked(path[1]), isFalse);
      expect(session.canUndo, isFalse);
    });
  });

  group('refusals', () {
    test('a cell with two connections takes no third', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1]), at(path[2])]);
      final laid = snapshotOf(session);
      final side = plain.found.sideCell!;
      session.takeEvent();

      session.beginStroke(at(side).$1, at(side).$2);
      session.strokeTo(at(path[1]).$1, at(path[1]).$2);
      session.endStroke();

      expectBoard(session, laid);
      expect(session.takeEvent(), TracksEvent.refused);
    });

    test('the cursor follows the finger, so the next step lays from there', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1]), at(path[2])]);
      final side = plain.found.sideCell!;
      // An empty neighbour of `side`, to lay into after the bump.
      final free = [
        for (final n in neighboursOf(spec, side))
          if (!path.take(3).contains(n.cell) &&
              session.maskAt(n.cell) == 0 &&
              !session.isFixed(n.cell))
            n.cell,
      ].first;
      final full = session.maskAt(path[1]);

      // path[1] is full, so the step into `side` is refused; the finger is
      // now at `side`, and the next step lays from there, not from path[1].
      session.beginStroke(at(path[1]).$1, at(path[1]).$2);
      session.strokeTo(at(side).$1, at(side).$2);
      expect(session.takeEvent(), TracksEvent.refused);
      session.strokeTo(at(free).$1, at(free).$2);
      session.endStroke();

      expect(session.maskAt(path[1]), full);
      expect(session.maskAt(side), facing(side, free));
      expect(session.maskAt(free), facing(free, side));
    });

    test('a fixed cell refuses a stroke into it along a closed side', () {
      final probe = findPuzzle<int>((p) => closedSide(p) == null ? null : 1);
      final p = probe.puzzle;
      final s = p.id.spec;
      final session = startSession(p);
      final before = snapshotOf(session);
      final end = closedSide(p)!;

      final free = positionOf(s, end.free);
      final fixed = positionOf(s, end.fixed);
      session.beginStroke(free.$1, free.$2);
      session.strokeTo(fixed.$1, fixed.$2);
      session.endStroke();

      expectBoard(session, before);
      expect(session.takeEvent(), TracksEvent.refused);
      expect(session.canUndo, isFalse);
    });

    test('a fixed cell refuses a stroke out of it along a closed side', () {
      final probe = findPuzzle<int>((p) => closedSide(p) == null ? null : 1);
      final s = probe.puzzle.id.spec;
      final session = startSession(probe.puzzle);
      final before = snapshotOf(session);
      final end = closedSide(probe.puzzle)!;

      final free = positionOf(s, end.free);
      final fixed = positionOf(s, end.fixed);
      session.beginStroke(fixed.$1, fixed.$2);
      session.strokeTo(free.$1, free.$2);
      session.endStroke();

      expectBoard(session, before);
      expect(session.takeEvent(), TracksEvent.refused);
    });

    group('an open end of a fixed piece', () {
      final probe = findPuzzle<int>((p) => openEnd(p) == null ? null : 1);
      final p = probe.puzzle;
      final s = p.id.spec;
      final end = openEnd(p)!;
      final freePos = positionOf(s, end.free);
      final fixedPos = positionOf(s, end.fixed);
      // The side of the free cell that faces the piece.
      final towards = TrackSide.opposite(end.side);

      test('takes a stroke from the free cell, laying only its half', () {
        final session = startSession(p);
        final before = snapshotOf(session);

        stroke(session, [freePos, fixedPos]);

        expect(session.maskAt(end.free), towards);
        expect(session.maskAt(end.fixed), p.clues.fixed[end.fixed]);
        expect(session.takeEvent(), TracksEvent.laid);
        expect(session.mistakes, 0);
        expect(session.canUndo, isTrue);

        session.undo();
        expectBoard(session, before);
        expect(session.canUndo, isFalse);
      });

      test('takes a stroke out of the piece the same way', () {
        final session = startSession(p);

        stroke(session, [fixedPos, freePos]);

        expect(session.maskAt(end.free), towards);
        expect(session.maskAt(end.fixed), p.clues.fixed[end.fixed]);
        expect(session.takeEvent(), TracksEvent.laid);
      });

      test('a stroke along the join once laid lifts nothing', () {
        final session = startSession(p);
        stroke(session, [freePos, fixedPos]);
        final laid = snapshotOf(session);

        session.beginStroke(fixedPos.$1, fixedPos.$2);
        session.strokeTo(freePos.$1, freePos.$2);
        session.strokeTo(fixedPos.$1, fixedPos.$2);
        session.endStroke();

        expectBoard(session, laid);
      });

      test('clearCell on the free cell lifts its half and the piece keeps '
          'its own', () {
        final session = startSession(p);
        final before = snapshotOf(session);
        stroke(session, [freePos, fixedPos]);

        session.clearCell(end.free);

        expect(session.maskAt(end.free), 0);
        expect(session.maskAt(end.fixed), p.clues.fixed[end.fixed]);
        expectBoard(session, before);
        expect(session.takeEvent(), TracksEvent.lifted);
        // An entry of its own, so it can be taken back.
        session.undo();
        expect(session.maskAt(end.free), towards);
      });

      test('a retrace lifts only the free half', () {
        final session = startSession(p);
        final before = snapshotOf(session);

        session.beginStroke(freePos.$1, freePos.$2);
        session.strokeTo(fixedPos.$1, fixedPos.$2);
        expect(session.maskAt(end.free), towards);
        session.strokeTo(freePos.$1, freePos.$2);
        session.endStroke();

        expect(session.maskAt(end.fixed), p.clues.fixed[end.fixed]);
        expectBoard(session, before);
        expect(session.canUndo, isFalse);
      });

      test('a retrace out of a join laid in an earlier stroke is no lift', () {
        final session = startSession(p);
        stroke(session, [freePos, fixedPos]);
        final laid = snapshotOf(session);

        session.beginStroke(freePos.$1, freePos.$2);
        session.strokeTo(fixedPos.$1, fixedPos.$2);
        session.strokeTo(freePos.$1, freePos.$2);
        session.endStroke();

        expectBoard(session, laid);
      });
    });

    test('clearCell does nothing on a fixed piece', () {
      final probe = findPuzzle<int>((p) => openEnd(p) == null ? null : 1);
      final end = openEnd(probe.puzzle)!;
      final fresh = startSession(probe.puzzle)..clearCell(end.fixed);

      expect(fresh.maskAt(end.fixed), probe.puzzle.clues.fixed[end.fixed]);
      expect(fresh.canUndo, isFalse);
      expect(fresh.takeEvent(), isNull);
    });

    test('a fixed port bit cannot be cleared either', () {
      final probe = findPuzzle<int>(
        (p) => p.clues.fixed[p.clues.startCell] & _w != 0 ? 1 : null,
        combos: offeredCombos,
      );
      final session = startSession(probe.puzzle);
      final cell = probe.puzzle.clues.startCell;
      final before = session.maskAt(cell);

      session.clearCell(cell);

      expect(session.maskAt(cell), before);
      expect(session.canUndo, isFalse);
    });

    test('a step off the grid is refused and lays nothing', () {
      // The last column's east edge: not the goal port, not anything.
      final row = [
        for (var r = 0; r < spec.side; r++)
          if (initialBoard(clues)[spec.indexAt(r, spec.side - 1)] == 0) r,
      ].first;
      final session = start()..beginStroke(row, spec.side - 1);

      session.strokeTo(row, spec.side);
      session.endStroke();

      expect(session.cells, initialBoard(clues));
      expect(session.takeEvent(), TracksEvent.refused);
      expect(session.canUndo, isFalse);
    });

    test('a finger already off the board bumps nothing', () {
      final session = start()..beginStroke(startRow, -2);

      session.strokeTo(startRow, -3);

      expect(session.takeEvent(), isNull);
    });

    test('a finger that slides in from the margin lays at the port', () {
      final session = start()..beginStroke(startRow, -2);

      session.strokeTo(startRow, -1);
      session.strokeTo(startRow, 0);
      session.endStroke();

      expect(session.maskAt(clues.startCell), _w);
    });
  });

  group('a jump', () {
    final block = findPuzzle<Position>(emptyBlock);
    final bp = block.puzzle;
    final bs = bp.id.spec;
    final (r0, c0) = block.found;

    TracksSession over() => startSession(bp);
    int at3(int dr, int dc) => bs.indexAt(r0 + dr, c0 + dc);

    test('lays an L along the dominant axis first', () {
      final session = over()..beginStroke(r0, c0);

      // Two rows, one column: rows are dominant.
      session.strokeTo(r0 + 2, c0 + 1);

      expect(session.maskAt(at3(0, 0)), _s);
      expect(session.maskAt(at3(1, 0)), _n | _s);
      expect(session.maskAt(at3(2, 0)), _n | _e);
      expect(session.maskAt(at3(2, 1)), _w);
      expect(session.maskAt(at3(0, 1)), 0);
    });

    test('columns first when the columns are the dominant axis', () {
      final session = over()..beginStroke(r0, c0);

      session.strokeTo(r0 + 1, c0 + 2);

      expect(session.maskAt(at3(0, 0)), _e);
      expect(session.maskAt(at3(0, 1)), _w | _e);
      expect(session.maskAt(at3(0, 2)), _w | _s);
      expect(session.maskAt(at3(1, 2)), _n);
      expect(session.maskAt(at3(1, 0)), 0);
    });

    test(
      'a diagonal tie goes along columns when the stroke has not stepped',
      () {
        final session = over()..beginStroke(r0, c0);

        session.strokeTo(r0 + 2, c0 + 2);

        expect(session.maskAt(at3(0, 0)), _e);
        expect(session.maskAt(at3(0, 1)), _w | _e);
        expect(session.maskAt(at3(0, 2)), _w | _s);
        expect(session.maskAt(at3(1, 2)), _n | _s);
        expect(session.maskAt(at3(2, 2)), _n);
        expect(session.maskAt(at3(1, 1)), 0);
      },
    );

    test('a diagonal tie continues along the axis of the previous step', () {
      // After a step down, a one-cell diagonal goes down first, so the cell
      // below the finger is laid and not the one beside it.
      final down = over()..beginStroke(r0, c0);
      down.strokeTo(r0 + 1, c0);
      down.strokeTo(r0 + 2, c0 + 1);
      expect(down.maskAt(at3(2, 0)), _n | _e);
      expect(down.maskAt(at3(1, 1)), 0);

      // After a step across, it goes across first.
      final across = over()..beginStroke(r0, c0);
      across.strokeTo(r0, c0 + 1);
      across.strokeTo(r0 + 1, c0 + 2);
      expect(across.maskAt(at3(0, 2)), _w | _s);
      expect(across.maskAt(at3(1, 1)), 0);
    });

    test('a long straight jump lays every cell between', () {
      final session = over()..beginStroke(r0, c0);

      session.strokeTo(r0, c0 + 2);
      session.endStroke();

      expect(session.maskAt(at3(0, 0)), _e);
      expect(session.maskAt(at3(0, 1)), _w | _e);
      expect(session.maskAt(at3(0, 2)), _w);
      // One stroke, one entry, however many cells it laid.
      session.undo();
      expect(session.canUndo, isFalse);
    });

    test('is walked from the start port the same way', () {
      final session = start()..beginStroke(startRow, -1);

      session.strokeTo(startRow, 1);

      expect(session.maskAt(clues.startCell), _w | _e);
    });
  });

  group('undo and redo', () {
    test('a stroke is one entry however many cells it laid', () {
      final session = start();
      final before = snapshotOf(session);

      stroke(session, [at(path[0]), at(path[1]), at(path[2]), at(path[3])]);
      session.undo();

      expectBoard(session, before);
      expect(session.canUndo, isFalse);
      expect(session.canRedo, isTrue);
      expect(session.takeEvent(), TracksEvent.restored);
    });

    test('an empty stroke and a fully retraced one are none', () {
      final session = start();

      session.beginStroke(startRow, -1);
      session.endStroke();
      expect(session.canUndo, isFalse);

      session.beginStroke(at(path[0]).$1, at(path[0]).$2);
      session.strokeTo(at(path[1]).$1, at(path[1]).$2);
      session.strokeTo(at(path[0]).$1, at(path[0]).$2);
      session.endStroke();
      expect(session.canUndo, isFalse);
    });

    test('a stroke that changed nothing leaves redo alone', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      session.undo();
      expect(session.canRedo, isTrue);

      session.beginStroke(startRow, -1);
      session.endStroke();
      stroke(session, [at(path[0]), at(path[1]), at(path[0])]);

      expect(session.canRedo, isTrue);
    });

    test('restore the exact board and marks, both ways', () {
      final session = start();
      session.toggleMark(plain.found.wrongCell);
      final one = snapshotOf(session);
      stroke(session, [at(path[0]), at(path[1])]);
      final two = snapshotOf(session);
      session.clearCell(path[0]);
      final three = snapshotOf(session);

      session.undo();
      expectBoard(session, two);
      session.undo();
      expectBoard(session, one);
      session.redo();
      expectBoard(session, two);
      session.redo();
      expectBoard(session, three);
      expect(session.canRedo, isFalse);
    });

    test('a new move clears redo', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      session.undo();
      expect(session.canRedo, isTrue);

      session.toggleMark(plain.found.wrongCell);

      expect(session.canRedo, isFalse);
    });

    test('with nothing to undo or redo do nothing and say nothing', () {
      final session = start();
      var notifications = 0;
      session.addListener(() => notifications++);

      session.undo();
      session.redo();

      expect(notifications, 0);
      expect(session.takeEvent(), isNull);
    });

    test('undo and redo end an open stroke first', () {
      final session = start();
      session.beginStroke(at(path[0]).$1, at(path[0]).$2);
      session.strokeTo(at(path[1]).$1, at(path[1]).$2);

      session.undo();

      expect(session.isStroking, isFalse);
      expect(session.cells, initialBoard(clues));
    });

    test('keep 300 moves: the 301st undo does nothing', () {
      // Move k toggles the mark of cell number (index of the lowest set bit of
      // k), a Gray code, so no two boards among the first 512 are the same
      // and a restore to the wrong depth cannot pass by coincidence.
      final big = puzzleFor('tracks:9x9:easy:0');
      final board = initialBoard(big.clues);
      final empties = [
        for (var i = 0; i < board.length; i++)
          if (board[i] == 0) i,
      ].take(9).toList();
      expect(empties.length, 9);
      final session = startSession(big);
      final snapshots = [snapshotOf(session)];

      for (var move = 1; move <= 310; move++) {
        session.toggleMark(empties[(move & -move).bitLength - 1]);
        snapshots.add(snapshotOf(session));
      }

      for (var undone = 1; undone <= 300; undone++) {
        session.undo();
        expectBoard(session, snapshots[310 - undone]);
      }
      expect(session.canUndo, isFalse);
      session.undo();
      expectBoard(session, snapshots[10]);

      for (var redone = 1; redone <= 300; redone++) {
        session.redo();
        expectBoard(session, snapshots[10 + redone]);
      }
      expect(session.canRedo, isFalse);
      expectBoard(session, snapshots[310]);
    });
  });

  group('marks', () {
    test('toggle on an empty cell, and off again', () {
      final cell = plain.found.wrongCell;
      final session = start();

      session.toggleMark(cell);
      expect(session.isMarked(cell), isTrue);
      expect(session.takeEvent(), TracksEvent.marked);

      session.toggleMark(cell);
      expect(session.isMarked(cell), isFalse);
    });

    test('are refused on a cell that holds track', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      session.takeEvent();
      final before = snapshotOf(session);

      session.toggleMark(path[0]);

      expectBoard(session, before);
      expect(session.takeEvent(), isNull);
    });

    test('are refused on a fixed cell', () {
      final fixed = findPuzzle<int>((p) {
        final index = p.clues.fixed.indexWhere((mask) => mask != 0);
        return index < 0 ? null : index;
      });
      final session = startSession(fixed.puzzle);

      session.toggleMark(fixed.found);

      expect(session.isMarked(fixed.found), isFalse);
      expect(session.canUndo, isFalse);
    });

    test('are cleared by laying into the cell', () {
      final session = start()..toggleMark(path[1]);

      stroke(session, [at(path[0]), at(path[1])]);

      expect(session.isMarked(path[1]), isFalse);
      expect(session.maskAt(path[1]), isNot(0));
    });

    test('come back with undo of the stroke that cleared them', () {
      final session = start()..toggleMark(path[1]);
      final marked = snapshotOf(session);
      stroke(session, [at(path[0]), at(path[1])]);

      session.undo();

      expectBoard(session, marked);
      expect(session.isMarked(path[1]), isTrue);
    });

    test('clearing a cell leaves the neighbour\'s mark state alone', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);

      session.clearCell(path[0]);

      expect(session.maskAt(path[0]), 0);
      expect(session.maskAt(path[1]), 0);
      expect(session.isMarked(path[0]), isFalse);
    });
  });

  group('mistakes', () {
    final wrong = plain.found.wrongCell;

    TracksSession withWrong({
      MistakeFeedback feedback = MistakeFeedback.immediate,
    }) =>
        start(feedback: feedback)..beginStroke(at(path[0]).$1, at(path[0]).$2);

    test('a wrong connection laid and kept counts once, at endStroke', () {
      final session = withWrong();

      session.strokeTo(at(wrong).$1, at(wrong).$2);
      expect(session.mistakes, 0);
      session.endStroke();

      expect(session.mistakes, 1);
      expect(session.wrongSides(path[0]), facing(path[0], wrong));
      expect(session.wrongSides(wrong), facing(wrong, path[0]));
    });

    test('one laid and retraced in the same stroke costs nothing', () {
      final session = withWrong();

      session.strokeTo(at(wrong).$1, at(wrong).$2);
      session.strokeTo(at(path[0]).$1, at(path[0]).$2);
      session.endStroke();

      expect(session.mistakes, 0);
    });

    test('a correct connection costs nothing', () {
      final session = start();

      stroke(session, [at(path[0]), at(path[1])]);

      expect(session.mistakes, 0);
      expect(session.wrongSides(path[0]), 0);
    });

    test('undo does not take a mistake back', () {
      final session = withWrong();
      session.strokeTo(at(wrong).$1, at(wrong).$2);
      session.endStroke();

      session.undo();

      expect(session.mistakes, 1);
      expect(session.wrongSides(path[0]), 0);
    });

    test('laidWrong is the event under immediate feedback only', () {
      final immediate = withWrong();
      immediate.strokeTo(at(wrong).$1, at(wrong).$2);
      expect(immediate.takeEvent(), TracksEvent.laidWrong);

      final held = withWrong(feedback: MistakeFeedback.atCompletion);
      held.strokeTo(at(wrong).$1, at(wrong).$2);
      expect(held.takeEvent(), TracksEvent.laid);
      held.endStroke();
      // Still a mistake: only the telling is held back.
      expect(held.mistakes, 1);
    });

    test('flaggedSides flags wrong sides at once under immediate', () {
      final session = withWrong();
      session.strokeTo(at(wrong).$1, at(wrong).$2);
      session.endStroke();

      expect(session.flaggedSides(path[0]), facing(path[0], wrong));
      expect(session.flaggedSides(wrong), facing(wrong, path[0]));
      expect(session.flaggedSides(path[1]), 0);
    });

    test('flaggedSides hides them under atCompletion', () {
      final session = withWrong(feedback: MistakeFeedback.atCompletion);
      session.strokeTo(at(wrong).$1, at(wrong).$2);
      session.endStroke();

      expect(session.wrongSides(path[0]), isNot(0));
      expect(session.flaggedSides(path[0]), 0);
      expect(session.flaggedSides(wrong), 0);
    });

    test('flaggedSides shows the cell a hint pointed at, even under '
        'atCompletion', () {
      final session = withWrong(feedback: MistakeFeedback.atCompletion);
      session.strokeTo(at(wrong).$1, at(wrong).$2);
      session.endStroke();

      session.hint();

      final pointed = session.pointedAt!;
      expect(pointed, min(path[0], wrong));
      expect(session.flaggedSides(pointed), session.wrongSides(pointed));
      expect(session.flaggedSides(pointed), isNot(0));
      final other = pointed == path[0] ? wrong : path[0];
      expect(session.flaggedSides(other), 0);
    });

    test('flaggedSides shows them under atCompletion once the track is joined '
        'but the board is not solved', () {
      // The whole solution plus a stray wrong piece between two cells the
      // solution leaves empty: joined, and not solved.
      final probe = findPuzzle<(int, int)>((p) {
        final s = p.id.spec;
        final board = initialBoard(p.clues);
        for (var cell = 0; cell < s.cells; cell++) {
          if (p.solution[cell] != 0 || board[cell] != 0) continue;
          for (final n in neighboursOf(s, cell)) {
            if (n.cell > cell &&
                p.solution[n.cell] == 0 &&
                board[n.cell] == 0) {
              return (cell, n.cell);
            }
          }
        }
        return null;
      });
      final p = probe.puzzle;
      final s = p.id.spec;
      final (a, b) = probe.found;
      final session = startSession(p, feedback: MistakeFeedback.atCompletion);

      stroke(session, [positionOf(s, a), positionOf(s, b)]);
      expect(session.isJoined, isFalse);
      expect(session.flaggedSides(a), 0, reason: 'not joined yet');

      stroke(session, solutionStroke(p));
      expect(session.isJoined, isTrue);
      expect(session.isSolved, isFalse);
      expect(session.flaggedSides(a), isNot(0));
      expect(session.flaggedSides(b), isNot(0));

      session.clearCell(a);
      expect(session.isSolved, isTrue);
      expect(session.flaggedSides(b), 0);
    });
  });

  group('hints', () {
    test('with a wrong connection on the board point at it, free', () {
      final wrong = plain.found.wrongCell;
      final session = start();
      stroke(session, [at(path[0]), at(wrong)]);
      session.takeEvent();
      final before = snapshotOf(session);
      final undoable = session.canUndo;

      session.hint();

      expect(session.pointedAt, min(path[0], wrong));
      expect(session.hints, 0);
      expectBoard(session, before);
      expect(session.canUndo, undoable);
      expect(session.takeEvent(), TracksEvent.hinted);
    });

    test('otherwise lay a solution piece, count it, and can be undone', () {
      final session = start();
      final before = snapshotOf(session);

      session.hint();

      expect(session.hints, 1);
      expect(session.pointedAt, isNull);
      expect(session.takeEvent(), TracksEvent.hinted);
      final changed = [
        for (var i = 0; i < spec.cells; i++)
          if (session.maskAt(i) != before.cells[i]) i,
      ];
      expect(changed, isNotEmpty);
      // The piece laid is the solution's, whichever cell the solver chose.
      expect(
        changed.any((i) => session.maskAt(i) == puzzle.solution[i]),
        isTrue,
      );
      for (var i = 0; i < spec.cells; i++) {
        expect(session.wrongSides(i), 0);
      }

      session.undo();
      expectBoard(session, before);
      expect(session.hints, 1, reason: 'a hint used stays used');
    });

    test('clear the marks on every cell the piece gives a connection to', () {
      final session = start();
      final board = initialBoard(clues);
      // Every empty cell the solution uses, marked wrongly.
      for (var i = 0; i < spec.cells; i++) {
        if (board[i] == 0 && puzzle.solution[i] != 0) session.toggleMark(i);
      }

      for (var i = 0; i < 4 * spec.cells && !session.isSolved; i++) {
        session.hint();
        for (var cell = 0; cell < spec.cells; cell++) {
          expect(session.isMarked(cell) && session.maskAt(cell) != 0, isFalse);
        }
      }
      expect(session.isSolved, isTrue);
    });

    test('repeated hints solve every offered size and difficulty', () {
      for (final (size, difficulty) in offeredCombos) {
        final p = puzzleFor('tracks:${size.label}:${difficulty.name}:1');
        final session = startSession(p);

        var presses = 0;
        while (!session.isSolved && presses < 2 * size.cells) {
          session.hint();
          presses++;
        }

        expect(session.isSolved, isTrue, reason: '${p.id}');
        expect(session.cells, p.solution, reason: '${p.id}');
        expect(session.hints, presses, reason: '${p.id}');
        expect(session.mistakes, 0);
        expect(session.takeEvent(), TracksEvent.solved);
      }
    });

    test('do nothing once the puzzle is solved', () {
      final session = start();
      stroke(session, solutionStroke(puzzle));
      expect(session.isSolved, isTrue);
      session.takeEvent();

      session.hint();

      expect(session.hints, 0);
      expect(session.takeEvent(), isNull);
    });
  });

  group('events', () {
    test('takeEvent hands an event over once', () {
      final session = start()..beginStroke(startRow, -1);
      session.strokeTo(startRow, 0);

      expect(session.takeEvent(), TracksEvent.laid);
      expect(session.takeEvent(), isNull);
    });

    test('a call keeps the highest priority of what happened in it', () {
      // One call that retraces a cell (lifted) and then lays another (laid):
      // from the second cell of a stroke, a diagonal jump with a tie goes along
      // columns first, back over the connection just laid, then down.
      final block = findPuzzle<Position>(emptyBlock);
      final (r0, c0) = block.found;
      // Held-back feedback, so the laid pieces are `laid` whether or not the
      // solution holds them.
      final session = startSession(
        block.puzzle,
        feedback: MistakeFeedback.atCompletion,
      )..beginStroke(r0, c0);
      session.strokeTo(r0, c0 + 1);
      session.takeEvent();

      session.strokeTo(r0 + 1, c0);

      expect(session.takeEvent(), TracksEvent.laid);
      final s = block.puzzle.id.spec;
      expect(session.maskAt(s.indexAt(r0, c0 + 1)), 0, reason: 'lifted');
      expect(session.maskAt(s.indexAt(r0 + 1, c0)), TrackSide.north);
    });

    test('solved arrives on the step that finishes the track', () {
      final session = start()..beginStroke(startRow, -1);
      final events = <TracksEvent?>[];
      final solvedAt = <int>[];

      final positions = solutionStroke(puzzle);
      for (var i = 1; i < positions.length; i++) {
        session.strokeTo(positions[i].$1, positions[i].$2);
        events.add(session.takeEvent());
        if (session.isSolved) solvedAt.add(i);
      }

      expect(solvedAt, isNotEmpty);
      expect(events[solvedAt.first - 1], TracksEvent.solved);
      expect(events.where((e) => e == TracksEvent.solved).length, 1);
    });

    test('undo and redo say solved when they leave the board solved', () {
      final session = start();
      stroke(session, solutionStroke(puzzle));
      session.takeEvent();

      session.undo();
      expect(session.isSolved, isFalse);
      expect(session.takeEvent(), TracksEvent.restored);

      session.redo();
      expect(session.isSolved, isTrue);
      expect(session.takeEvent(), TracksEvent.solved);
    });

    test('a hint that finishes the puzzle says solved', () {
      final session = start();
      stroke(session, solutionStroke(puzzle));
      session.clearCell(path[1]);
      session.takeEvent();

      var presses = 0;
      while (!session.isSolved && presses++ < spec.cells) {
        session.hint();
      }

      expect(session.takeEvent(), TracksEvent.solved);
    });
  });

  group('rules', () {
    test('placedInRow and placedInColumn count non-empty cells', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1]), at(path[2])]);

      for (var line = 0; line < spec.side; line++) {
        var row = 0;
        var column = 0;
        for (var other = 0; other < spec.side; other++) {
          if (session.maskAt(spec.indexAt(line, other)) != 0) row++;
          if (session.maskAt(spec.indexAt(other, line)) != 0) column++;
        }
        expect(session.placedInRow(line), row);
        expect(session.placedInColumn(line), column);
      }
    });

    test('a joined track with the wrong counts is not solved', () {
      // The solution is the only board that joins and counts right, so a
      // detour joined start to goal cannot be solved. Closing the track
      // through an extra empty pair (see the flaggedSides case) is one; here
      // it is checked from the other side: the rules agree with the solution.
      final session = start();
      stroke(session, solutionStroke(puzzle));

      expect(session.isJoined, isTrue);
      expect(session.isSolved, isTrue);
      expect(listEquals(session.cells, puzzle.solution), isTrue);
    });

    test('a half track is neither joined nor solved', () {
      final session = start();
      stroke(session, solutionStroke(puzzle).take(5).toList());

      expect(session.isJoined, isFalse);
      expect(session.isSolved, isFalse);
    });
  });

  group('saving and resuming', () {
    test(
      'round-trips cells, marks, undo stack, hints, elapsed and mistakes',
      () {
        final session = start();
        session.toggleMark(plain.found.sideCell!);
        session.hint();
        stroke(session, [at(path[0]), at(plain.found.wrongCell)]);
        session.elapsed = const Duration(seconds: 42, milliseconds: 7);
        final saved = session.toSaved();

        final resumed = resumeSession(puzzle, saved);

        expectBoard(resumed, snapshotOf(session));
        expect(resumed.toSaved(), saved);
        expect(resumed.hints, 1);
        expect(resumed.elapsed, const Duration(seconds: 42, milliseconds: 7));
        expect(resumed.mistakes, 1);
        expect(resumed.canUndo, isTrue);
        expect(resumed.canRedo, isFalse, reason: 'redo is not stored');
        session.undo();
        resumed.undo();
        expectBoard(resumed, snapshotOf(session));
      },
    );

    test('counts each wrong connection once, not once per bit', () {
      final session = start();
      stroke(session, [at(path[0]), at(plain.found.wrongCell)]);

      final resumed = resumeSession(puzzle, session.toSaved());

      expect(resumed.mistakes, 1);
    });

    test('a fresh board round-trips with no undo history', () {
      final saved = start().toSaved();

      expect(saved.marks, '');
      expect(saved.undoStack, isEmpty);
      expectBoard(resumeSession(puzzle, saved), snapshotOf(start()));
    });

    test('a resumed solved board is solved', () {
      final session = start();
      stroke(session, solutionStroke(puzzle));

      expect(resumeSession(puzzle, session.toSaved()).isSolved, isTrue);
    });

    test('caps a stored undo stack at 300, dropping the oldest', () {
      final board = initialBoard(clues);
      final cell = board.indexOf(0);
      // Every entry restores the same empty cell, marked or not, so any
      // replay of them is a valid board and only the cap can change the
      // outcome.
      final stack = [
        for (var i = 0; i < 310; i++)
          TracksMove([
            TracksCellState(index: cell, mask: 0, marked: i.isOdd),
          ]).encode(),
      ];

      final resumed = resumeSession(
        puzzle,
        TracksInProgress(
          cells: encodeTracksCells(spec, board),
          undoStack: stack,
        ),
      );

      expect(resumed.toSaved().undoStack, stack.sublist(10));
    });

    void expectRefused(String reason, List<int> cells, {List<bool>? marks}) {
      expect(
        () => resumeSession(
          puzzle,
          TracksInProgress(
            cells: encodeTracksCells(spec, cells),
            marks: marks == null ? '' : encodeTracksMarks(spec, marks),
          ),
        ),
        throwsFormatException,
        reason: reason,
      );
    }

    List<int> board() => initialBoard(clues);

    test('refuses a board that does not decode', () {
      expect(
        () => resumeSession(puzzle, const TracksInProgress(cells: '00')),
        throwsFormatException,
      );
      expect(
        () => resumeSession(puzzle, TracksInProgress(cells: 'g' * spec.cells)),
        throwsFormatException,
      );
    });

    test('refuses a board missing a fixed piece', () {
      final fixed = findPuzzle<int>(
        (p) => p.clues.fixed.any((m) => m != 0) ? 1 : null,
      ).puzzle;
      final s = fixed.id.spec;
      final cells = initialBoard(fixed.clues);
      cells[fixed.clues.fixed.indexWhere((m) => m != 0)] = 0;

      expect(
        () => resumeSession(
          fixed,
          TracksInProgress(cells: encodeTracksCells(s, cells)),
        ),
        throwsFormatException,
      );
    });

    test('accepts a fixed piece\'s open end with nothing answering it', () {
      final probe = findPuzzle<int>((p) => openEnd(p) == null ? null : 1);
      final p = probe.puzzle;
      final end = openEnd(p)!;
      final cells = initialBoard(p.clues);
      expect(cells[end.free], 0);

      final resumed = resumeSession(
        p,
        TracksInProgress(cells: encodeTracksCells(p.id.spec, cells)),
      );

      expect(resumed.cells, cells);
    });

    test('accepts a free cell that answers an open end', () {
      final probe = findPuzzle<int>((p) => openEnd(p) == null ? null : 1);
      final p = probe.puzzle;
      final end = openEnd(p)!;
      final cells = initialBoard(p.clues)
        ..[end.free] = TrackSide.opposite(end.side);

      expect(
        () => resumeSession(
          p,
          TracksInProgress(cells: encodeTracksCells(p.id.spec, cells)),
        ),
        returnsNormally,
      );
    });

    test('refuses a free cell pointing into a fixed piece\'s closed side', () {
      final probe = findPuzzle<int>((p) => closedSide(p) == null ? null : 1);
      final p = probe.puzzle;
      final end = closedSide(p)!;
      // The free cell's bit toward the piece, which holds no bit back.
      final cells = initialBoard(p.clues)
        ..[end.free] = TrackSide.opposite(end.side);

      expect(
        () => resumeSession(
          p,
          TracksInProgress(cells: encodeTracksCells(p.id.spec, cells)),
        ),
        throwsFormatException,
      );
    });

    test('refuses a port bit on the wrong row, or the wrong column', () {
      final otherRow = [
        for (var r = 0; r < spec.side; r++)
          if (r != startRow && board()[spec.indexAt(r, 0)] == 0) r,
      ].first;
      final west = board()..[spec.indexAt(otherRow, 0)] = _w;
      expectRefused('west bit off the start row', west);

      final otherColumn = [
        for (var c = 0; c < spec.side; c++)
          if (c != clues.goalColumn &&
              board()[spec.indexAt(spec.side - 1, c)] == 0)
            c,
      ].first;
      final south = board()..[spec.indexAt(spec.side - 1, otherColumn)] = _s;
      expectRefused('south bit away from the goal column', south);

      final north = board()..[plain.found.sideCell!] = 0;
      north[spec.indexAt(0, 0)] = _n;
      expectRefused('north bit off the top edge', north);
    });

    test(
      'accepts the start cell\'s west bit and the goal cell\'s south bit',
      () {
        final cells = board()
          ..[clues.startCell] |= _w
          ..[clues.goalCell] |= _s;
        // A half-built board with both ports joined is still a board.
        expect(
          () => resumeSession(
            puzzle,
            TracksInProgress(cells: encodeTracksCells(spec, cells)),
          ),
          returnsNormally,
        );
      },
    );

    test('refuses a mark on a track cell', () {
      final cells = board()
        ..[path[0]] = _w | facing(path[0], path[1])
        ..[path[1]] = facing(path[1], path[0]);
      final marks = List<bool>.filled(spec.cells, false)..[path[0]] = true;

      expectRefused('mark on track', cells, marks: marks);
    });

    test('refuses a free cell\'s bit with no partner, and a third bit', () {
      final cell = path[1];
      final lonely = board()..[cell] = facing(cell, path[2]);
      expectRefused('unreciprocated', lonely);

      final crowded = board()..[cell] = _n | _e | _s;
      expectRefused('three bits', crowded);
    });

    test('keeps the board and drops an undo stack that does not decode', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      final saved = session.toSaved();

      final resumed = resumeSession(
        puzzle,
        TracksInProgress(
          cells: saved.cells,
          marks: saved.marks,
          elapsedMs: 5000,
          undoStack: const ['not a move'],
          hints: 2,
        ),
      );

      expectBoard(resumed, snapshotOf(session));
      expect(resumed.canUndo, isFalse);
      expect(resumed.hints, 2);
      expect(resumed.elapsed, const Duration(seconds: 5));
    });

    test('drops an undo stack whose replay reaches an impossible board', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      stroke(session, [at(path[1]), at(path[2])]);
      final saved = session.toSaved();
      expect(saved.undoStack.length, 2);

      // An entry that decodes but would put a north bit on the top row, in a
      // stack whose newest entry is fine: only replaying all of it finds it.
      final bad = TracksMove([
        const TracksCellState(index: 0, mask: _n | _w, marked: false),
      ]).encode();
      final resumed = resumeSession(
        puzzle,
        TracksInProgress(
          cells: saved.cells,
          undoStack: [bad, saved.undoStack[1]],
        ),
      );

      expectBoard(resumed, snapshotOf(session));
      expect(resumed.canUndo, isFalse);
    });

    test('keeps a valid undo stack whole', () {
      final session = start();
      stroke(session, [at(path[0]), at(path[1])]);
      session.toggleMark(plain.found.wrongCell);
      session.clearCell(path[0]);

      final resumed = resumeSession(puzzle, session.toSaved());

      for (var i = 0; i < 3; i++) {
        session.undo();
        resumed.undo();
        expectBoard(resumed, snapshotOf(session));
      }
      expect(resumed.canUndo, isFalse);
    });
  });

  group('the board invariants', () {
    test('hold after every call of a long random play', () {
      // Random strokes, taps, hints and undo/redo, seeded so a failure
      // replays. After every call: at most two bits a cell, a fixed cell
      // exactly as it came, every interior connection held on both ends bar a
      // fixed piece's open end, nothing off the grid but the two port bits, a
      // mark only on an empty cell, and a save of the board resumes.
      final random = Random(20240607);
      final p = puzzleFor('tracks:5x5:medium:2');
      final s = p.id.spec;
      final session = startSession(p);

      void check(String after) {
        final cells = session.cells;
        for (var cell = 0; cell < s.cells; cell++) {
          final mask = cells[cell];
          expect(_bits(mask), lessThanOrEqualTo(2), reason: after);
          if (session.isMarked(cell)) expect(mask, 0, reason: after);
          if (p.clues.fixed[cell] != 0) {
            expect(mask, p.clues.fixed[cell], reason: '$after: fixed moved');
          }
          for (final side in TrackSide.all) {
            if (mask & side == 0) continue;
            final neighbour = neighbourOf(s, cell, side);
            if (neighbour == null) {
              final port =
                  (cell == p.clues.startCell && side == _w) ||
                  (cell == p.clues.goalCell && side == _s);
              expect(port, isTrue, reason: '$after: bit off the grid');
            } else if (p.clues.fixed[cell] == 0 ||
                p.clues.fixed[neighbour] != 0) {
              // Only a fixed piece's bit onto a free cell may go unanswered.
              expect(
                cells[neighbour] & TrackSide.opposite(side),
                isNot(0),
                reason: '$after: unreciprocated',
              );
            }
          }
        }
        expect(() => resumeSession(p, session.toSaved()), returnsNormally);
      }

      for (var i = 0; i < 400; i++) {
        switch (random.nextInt(8)) {
          case 0:
            session.toggleMark(random.nextInt(s.cells));
          case 1:
            session.clearCell(random.nextInt(s.cells));
          case 2:
            session.undo();
          case 3:
            session.redo();
          case 4:
            if (random.nextInt(5) == 0) session.hint();
          default:
            session.beginStroke(
              random.nextInt(s.side + 2) - 1,
              random.nextInt(s.side + 2) - 1,
            );
            for (var j = 0; j < 1 + random.nextInt(6); j++) {
              session.strokeTo(
                random.nextInt(s.side + 2) - 1,
                random.nextInt(s.side + 2) - 1,
              );
            }
            session.endStroke();
        }
        check('call $i');
      }
    });
  });
}

int _bits(int mask) {
  var count = 0;
  for (var bits = mask; bits != 0; bits >>= 1) {
    count += bits & 1;
  }
  return count;
}
