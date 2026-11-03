import 'package:puzzle_engine/src/difficulty.dart';
import 'package:puzzle_engine/src/hash.dart';
import 'package:puzzle_engine/src/rng.dart';
import 'package:puzzle_engine/src/tracks/track_side.dart';
import 'package:puzzle_engine/src/tracks/tracks_clues.dart';
import 'package:puzzle_engine/src/tracks/tracks_puzzle.dart';
import 'package:puzzle_engine/src/tracks/tracks_puzzle_id.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';
import 'package:puzzle_engine/src/tracks/tracks_walk.dart';
import 'package:test/test.dart';

import 'tracks_counter_test.dart' show brokenRules;

/// The provisional bands of the PR 3 brief; the generator owns the final ones.
const Map<int, TracksWalkBand> bands = {
  5: TracksWalkBand(minLength: 9, maxLength: 15, minTurns: 3),
  7: TracksWalkBand(minLength: 17, maxLength: 29, minTurns: 6),
  9: TracksWalkBand(minLength: 27, maxLength: 45, minTurns: 9),
};

const int seeds = 300;

/// Clues that count [solution] and fix nothing: enough for [brokenRules].
TracksClues cluesOf(
  TracksSpec spec,
  int startRow,
  int goalColumn,
  List<int> solution,
) {
  final side = spec.side;
  final rows = List<int>.filled(side, 0);
  final columns = List<int>.filled(side, 0);
  for (var i = 0; i < solution.length; i++) {
    if (solution[i] == 0) continue;
    rows[spec.rowOf(i)]++;
    columns[spec.columnOf(i)]++;
  }
  return TracksClues(
    spec: spec,
    startRow: startRow,
    goalColumn: goalColumn,
    rowCounts: rows,
    columnCounts: columns,
    fixed: List<int>.filled(spec.cells, 0),
  );
}

List<int>? walkFor(TracksSpec spec, int seed, {int? stepBudget}) {
  final rng = Rng(fnv1a32('walk:${spec.label}#$seed'));
  final (startRow, goalColumn) = drawTracksPorts(spec, rng);
  final band = bands[spec.side]!;
  return stepBudget == null
      ? walkTracksPath(spec, startRow, goalColumn, rng, band)
      : walkTracksPath(
          spec,
          startRow,
          goalColumn,
          rng,
          band,
          stepBudget: stepBudget,
        );
}

void main() {
  group('drawTracksPorts', () {
    test('never puts the goal on the start cell and stays on the grid', () {
      for (final spec in TracksSpec.supported) {
        final startRows = <int>{};
        for (var seed = 0; seed < 500; seed++) {
          final (startRow, goalColumn) = drawTracksPorts(spec, Rng(seed));
          expect(startRow, inInclusiveRange(0, spec.side - 1));
          expect(goalColumn, inInclusiveRange(0, spec.side - 1));
          expect(
            spec.indexAt(startRow, 0) ==
                spec.indexAt(spec.side - 1, goalColumn),
            isFalse,
            reason: '${spec.label} seed $seed',
          );
          startRows.add(startRow);
        }
        expect(startRows.length, spec.side, reason: 'every row is reachable');
      }
    });

    test('the bottom-left start forces a goal column off column 0', () {
      final spec = TracksSpec.s5x5;
      var seen = 0;
      for (var seed = 0; seed < 2000; seed++) {
        final (startRow, goalColumn) = drawTracksPorts(spec, Rng(seed));
        if (startRow != spec.side - 1) continue;
        seen++;
        expect(goalColumn, greaterThan(0));
      }
      expect(seen, greaterThan(0));
    });

    test('the same seed gives the same ports', () {
      final a = drawTracksPorts(TracksSpec.s9x9, Rng(7));
      final b = drawTracksPorts(TracksSpec.s9x9, Rng(7));
      expect(a, b);
    });
  });

  for (final spec in TracksSpec.supported) {
    group('walkTracksPath ${spec.label}', () {
      final band = bands[spec.side]!;

      test('every path is a valid solution in band over $seeds seeds', () {
        var hits = 0;
        final lengths = <int>[];
        final turns = <int>[];
        for (var seed = 0; seed < seeds; seed++) {
          final rng = Rng(fnv1a32('walk:${spec.label}#$seed'));
          final (startRow, goalColumn) = drawTracksPorts(spec, rng);
          final path = walkTracksPath(spec, startRow, goalColumn, rng, band);
          if (path == null) continue;
          hits++;

          final reason = '${spec.label} seed $seed';
          expect(path.first, spec.indexAt(startRow, 0), reason: reason);
          expect(
            path.last,
            spec.indexAt(spec.side - 1, goalColumn),
            reason: reason,
          );
          expect(path.toSet().length, path.length, reason: '$reason repeats');
          for (var i = 1; i < path.length; i++) {
            final a = path[i - 1];
            final b = path[i];
            final distance =
                (spec.rowOf(a) - spec.rowOf(b)).abs() +
                (spec.columnOf(a) - spec.columnOf(b)).abs();
            expect(distance, 1, reason: '$reason step $i');
          }
          expect(path.length, inInclusiveRange(band.minLength, band.maxLength));

          final solution = tracksSolutionFor(spec, path);
          expect(tracksTurns(solution), greaterThanOrEqualTo(band.minTurns));
          final clues = cluesOf(spec, startRow, goalColumn, solution);
          expect(brokenRules(clues, solution), isEmpty, reason: reason);

          lengths.add(path.length);
          turns.add(tracksTurns(solution));
        }
        // The hit rate is reported by the PR, not asserted, but a walk that
        // never succeeds would make the checks above vacuous.
        expect(hits, greaterThan(seeds ~/ 2));
        lengths.sort();
        turns.sort();
        printOnFailure(
          '${spec.label}: $hits/$seeds, median length '
          '${lengths[lengths.length ~/ 2]}, median turns '
          '${turns[turns.length ~/ 2]}',
        );
      });

      test('the same seed gives the same path', () {
        for (var seed = 0; seed < 20; seed++) {
          expect(walkFor(spec, seed), walkFor(spec, seed));
        }
      });

      test('a budget of one cell gives up', () {
        expect(walkFor(spec, 1, stepBudget: 1), isNull);
      });

      test('a band no path can meet gives null rather than looping', () {
        final rng = Rng(3);
        final (startRow, goalColumn) = drawTracksPorts(spec, rng);
        const tooShort = TracksWalkBand(
          minLength: 1,
          maxLength: 2,
          minTurns: 0,
        );
        // Start and goal are at least two cells apart unless adjacent; a
        // maximum of two cells admits at most the adjacent pair.
        final path = walkTracksPath(spec, startRow, goalColumn, rng, tooShort);
        if (path != null) expect(path.length, lessThanOrEqualTo(2));
      });
    });
  }

  group('tracksSolutionFor', () {
    test('draws the ports and the corners of a 3-cell hook', () {
      const spec = TracksSpec(3);
      // Start (0,0) -> (0,1) -> (1,1) -> (2,1) goal.
      final solution = tracksSolutionFor(spec, [0, 1, 4, 7]);
      expect(solution, [
        TrackSide.west | TrackSide.east,
        TrackSide.west | TrackSide.south,
        0,
        0,
        TrackSide.north | TrackSide.south,
        0,
        0,
        TrackSide.north | TrackSide.south,
        0,
      ]);
      expect(tracksTurns(solution), 1);
    });

    test('rejects cells that are not neighbours', () {
      expect(
        () => tracksSolutionFor(const TracksSpec(3), [0, 4]),
        throwsArgumentError,
      );
      // Index 2 and 3 are adjacent in row-major order but not on the grid.
      expect(
        () => tracksSolutionFor(const TracksSpec(3), [2, 3]),
        throwsArgumentError,
      );
    });
  });

  group('tracksTurns', () {
    test('counts only the four corner pieces', () {
      expect(tracksTurns([0, 5, 10, 0]), 0);
      expect(tracksTurns([3, 6, 12, 9, 5]), 4);
    });
  });

  group('TracksPuzzle', () {
    final id = TracksPuzzleId(TracksSpec.s5x5, Difficulty.easy, 4);
    final clues = TracksClues(
      spec: TracksSpec.s5x5,
      startRow: 0,
      goalColumn: 1,
      rowCounts: const [1, 1, 1, 1, 1],
      columnCounts: const [1, 1, 1, 1, 1],
      fixed: List<int>.filled(25, 0),
    );

    test('requested is the ID tier and the solution cannot be edited', () {
      final source = List<int>.filled(25, 0);
      final puzzle = TracksPuzzle(
        id: id,
        clues: clues,
        solution: source,
        tier: Difficulty.medium,
        attempts: 3,
        widened: true,
      );
      expect(puzzle.requested, Difficulty.easy);
      source[0] = 5;
      expect(puzzle.solution[0], 0, reason: 'copied, not shared');
      expect(() => puzzle.solution[0] = 5, throwsUnsupportedError);
    });

    test('toString names the ID, tier, attempts and widening', () {
      TracksPuzzle make(int attempts, bool widened) => TracksPuzzle(
        id: id,
        clues: clues,
        solution: List<int>.filled(25, 0),
        tier: Difficulty.medium,
        attempts: attempts,
        widened: widened,
      );
      expect(
        make(1, false).toString(),
        'TracksPuzzle(tracks:5x5:easy:4, medium, 1 attempt)',
      );
      expect(
        make(250, true).toString(),
        'TracksPuzzle(tracks:5x5:easy:4, medium, 250 attempts, '
        'widened from easy)',
      );
    });
  });
}
