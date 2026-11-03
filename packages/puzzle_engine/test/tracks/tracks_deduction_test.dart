// The deduction solver is the generator's proof of uniqueness: PR 3 digs clues
// out of a path and keeps a removal when `solveTracks` still finishes, without
// asking the counter (`PLAN-phase-9-tracks.md` §4.5). So the property test
// below carries the weight. It builds random clues from random paths, and
// whenever the solver says "solved" the counter, which shares no code with it,
// must find exactly that one board. A rule that deduced too much would show up
// here as a disagreement, not as a bad puzzle in a child's hands.

import 'package:puzzle_engine/src/difficulty.dart';
import 'package:puzzle_engine/src/rng.dart';
import 'package:puzzle_engine/src/tracks/track_side.dart';
import 'package:puzzle_engine/src/tracks/tracks_clues.dart';
import 'package:puzzle_engine/src/tracks/tracks_counter.dart';
import 'package:puzzle_engine/src/tracks/tracks_deduction.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';
import 'package:test/test.dart';

import 'tracks_counter_test.dart'
    show
        loopFive,
        noneFive,
        twoFive,
        twoFiveFirst,
        twoFiveSecond,
        uniqueFive,
        uniqueFiveSolution,
        uniqueNine,
        uniqueNineB,
        uniqueNineBSolution,
        uniqueNineSolution,
        uniqueSeven,
        uniqueSevenSolution;
import 'tracks_fixtures.dart';

/// A random self-avoiding walk from the start cell to the goal cell, as cell
/// indices, or null when [budget] cells were entered without reaching it.
///
/// Plain randomised depth-first search with no length band: the property test
/// wants variety, not the generator's taste.
List<int>? randomPath(
  TracksSpec spec,
  int startRow,
  int goalColumn,
  Rng rng, {
  int budget = 20000,
}) {
  final side = spec.side;
  final start = spec.indexAt(startRow, 0);
  final goal = spec.indexAt(side - 1, goalColumn);
  final visited = List<bool>.filled(spec.cells, false);
  final path = <int>[];
  var spent = 0;

  bool walk(int cell) {
    if (++spent > budget) return false;
    visited[cell] = true;
    path.add(cell);
    if (cell == goal) return true;
    final sides = List<int>.of(TrackSide.all);
    rng.shuffle(sides);
    final row = spec.rowOf(cell);
    final column = spec.columnOf(cell);
    for (final s in sides) {
      final r =
          row + (s == TrackSide.north ? -1 : (s == TrackSide.south ? 1 : 0));
      final c =
          column + (s == TrackSide.west ? -1 : (s == TrackSide.east ? 1 : 0));
      if (r < 0 || r >= side || c < 0 || c >= side) continue;
      final next = spec.indexAt(r, c);
      if (visited[next]) continue;
      if (walk(next)) return true;
      if (spent > budget) return false;
    }
    visited[cell] = false;
    path.removeLast();
    return false;
  }

  return walk(start) ? path : null;
}

/// The connection masks of [path], ports included.
List<int> maskedPath(TracksSpec spec, List<int> path) {
  final cells = List<int>.filled(spec.cells, 0);
  int toward(int from, int to) {
    final d = to - from;
    if (d == 1) return TrackSide.east;
    if (d == -1) return TrackSide.west;
    return d > 0 ? TrackSide.south : TrackSide.north;
  }

  for (var p = 0; p < path.length; p++) {
    if (p == 0) cells[path[p]] |= TrackSide.west;
    if (p == path.length - 1) cells[path[p]] |= TrackSide.south;
    if (p > 0) cells[path[p]] |= toward(path[p], path[p - 1]);
    if (p < path.length - 1) cells[path[p]] |= toward(path[p], path[p + 1]);
  }
  return cells;
}

/// Clues for [solution] with each track cell fixed with probability
/// [percent] in a hundred. The draw order is cell index order.
TracksClues cluesOf(
  TracksSpec spec,
  int startRow,
  int goalColumn,
  List<int> solution,
  Rng rng,
  int percent,
) {
  final side = spec.side;
  final rows = List<int>.filled(side, 0);
  final columns = List<int>.filled(side, 0);
  final fixed = List<int>.filled(spec.cells, 0);
  for (var i = 0; i < spec.cells; i++) {
    if (solution[i] == 0) continue;
    rows[spec.rowOf(i)]++;
    columns[spec.columnOf(i)]++;
    if (rng.nextInt(100) < percent) fixed[i] = solution[i];
  }
  return TracksClues(
    spec: spec,
    startRow: startRow,
    goalColumn: goalColumn,
    rowCounts: rows,
    columnCounts: columns,
    fixed: fixed,
  );
}

/// Random clues for [seed], or null when the walk ran out of budget. The
/// fixed share cycles through a few values, so seeds cover sparse and dense
/// clue sets alike.
({TracksClues clues, List<int> solution})? randomClues(
  TracksSpec spec,
  int seed,
) {
  final rng = Rng(seed * 7919 + spec.side);
  final startRow = rng.nextInt(spec.side);
  final goalColumn = startRow == spec.side - 1
      ? 1 + rng.nextInt(spec.side - 1)
      : rng.nextInt(spec.side);
  final path = randomPath(spec, startRow, goalColumn, rng);
  if (path == null) return null;
  final solution = maskedPath(spec, path);
  const percents = [0, 4, 8, 15, 25, 40];
  final clues = cluesOf(
    spec,
    startRow,
    goalColumn,
    solution,
    rng,
    percents[seed % percents.length],
  );
  return (clues: clues, solution: solution);
}

// Hand fixtures for the tiers. Each was read off the solver's report and then
// checked against the counter in the tests below, so the tier named here is
// what the rules need and not what the author hoped.

/// T1 alone: see `uniqueFive` in the counter test, which the counts nearly
/// finish by themselves.
final TracksClues easyFive = uniqueFive;

/// Needs T2: a 9x9 with eight fixed cells whose last choices fall to reach and
/// no-early-loop, with no guess.
final TracksClues mediumNine = uniqueNine;

/// Needs T3: the 7x7 of the counter test, whose two fixed corners leave
/// ambiguity that only a cell's hypothesised state resolves.
final TracksClues hardSeven = uniqueSeven;

void main() {
  group('solveTracks tiers', () {
    test('a unique 5x5 falls to T1 alone', () {
      final report = solveTracks(easyFive, ceiling: Difficulty.easy);
      expect(report.solved, isTrue);
      expect(report.tier, Difficulty.easy);
      expect(report.cells, uniqueFiveSolution);
    });

    test('a 9x9 that needs T2 reports medium', () {
      final report = solveTracks(mediumNine);
      expect(report.solved, isTrue);
      expect(report.tier, Difficulty.medium);
      expect(report.cells, uniqueNineSolution);
      expect(solveTracks(uniqueNineB).tier, Difficulty.medium);
    });

    test('a 7x7 that needs T3 reports hard', () {
      final report = solveTracks(hardSeven);
      expect(report.solved, isTrue);
      expect(report.tier, Difficulty.hard);
      expect(report.cells, uniqueSevenSolution);
    });

    test('two solutions are never reported solved', () {
      for (final ceiling in Difficulty.values) {
        final report = solveTracks(twoFive, ceiling: ceiling);
        expect(report.solved, isFalse, reason: '$ceiling');
        expect(report.tier, Difficulty.expert);
      }
    });

    test('no solution and a closed loop are not reported solved', () {
      expect(solveTracks(noneFive).solved, isFalse);
      expect(solveTracks(loopFive).solved, isFalse);
    });

    test('the ceiling stops the solver using a higher tier', () {
      final easy = solveTracks(mediumNine, ceiling: Difficulty.easy);
      expect(easy.solved, isFalse);
      expect(easy.tier, Difficulty.expert);
      expect(
        solveTracks(mediumNine, ceiling: Difficulty.medium).tier,
        Difficulty.medium,
      );

      expect(solveTracks(hardSeven, ceiling: Difficulty.easy).solved, isFalse);
      expect(
        solveTracks(hardSeven, ceiling: Difficulty.medium).solved,
        isFalse,
      );
      expect(
        solveTracks(hardSeven, ceiling: Difficulty.expert).tier,
        Difficulty.hard,
      );
    });

    test('an unsolved report holds only edges the solution has', () {
      final report = solveTracks(hardSeven, ceiling: Difficulty.medium);
      expect(report.solved, isFalse);
      var proven = 0;
      for (var i = 0; i < report.cells.length; i++) {
        expect(report.cells[i] & ~uniqueSevenSolution[i], 0, reason: 'cell $i');
        if (report.cells[i] != 0) proven++;
      }
      expect(proven, greaterThan(0));
    });

    test('clues that contradict themselves do not throw', () {
      // The start cell is fixed without its west bit, so the port and the
      // fixed piece disagree.
      final clues = cluesFor(5, 0, 1, [1, 1, 1, 1, 1], [1, 1, 1, 1, 1], {
        0: TrackSide.east | TrackSide.south,
      });
      expect(solveTracks(clues).solved, isFalse);
    });
  });

  group('frozen fixtures from the property run', () {
    // Clue lines pulled out of the random sweep below, one per tier, so a rule
    // change that moves a tier shows up here with a name.
    const fixtures = <String, (String, Difficulty)>{
      '5x5 medium': ('5x5|2|4|2,5,5,1,2|3,3,2,4,3|', Difficulty.medium),
      '5x5 hard': ('5x5|3|4|0,3,3,4,4|3,3,4,3,1|', Difficulty.hard),
      '7x7 medium': ('7x7|3|3|0,0,0,1,3,4,3|3,2,3,3,0,0,0|', Difficulty.medium),
      '7x7 hard': ('7x7|0|2|3,2,2,4,2,1,3|3,4,4,3,3,0,0|', Difficulty.hard),
      '9x9 medium': (
        '9x9|4|2|3,2,2,3,3,5,5,2,2|8,7,8,2,2,0,0,0,0|28:6',
        Difficulty.medium,
      ),
      '9x9 hard': (
        '9x9|3|6|0,3,3,4,4,1,2,3,4|4,4,5,6,3,1,1,0,0|',
        Difficulty.hard,
      ),
    };

    for (final entry in fixtures.entries) {
      test('${entry.key} solves at exactly ${entry.value.$2.name}', () {
        final clues = TracksClues.decode(entry.value.$1);
        final report = solveTracks(clues);
        expect(report.solved, isTrue);
        expect(report.tier, entry.value.$2);
        final found = solutionsOf(clues);
        expect(found, hasLength(1));
        expect(report.cells, found.single);
        expect(brokenRules(clues, report.cells), isEmpty);
        // One tier lower is not enough.
        if (entry.value.$2 != Difficulty.easy) {
          final lower = Difficulty.values[entry.value.$2.index - 1];
          expect(solveTracks(clues, ceiling: lower).solved, isFalse);
        }
      });
    }
  });

  group('nextTracksStep', () {
    test('on an empty board it finds the cheapest provable cell', () {
      final step = nextTracksStep(uniqueFive, List<int>.filled(25, 0));
      expect(step, isNotNull);
      expect(step!.tier, Difficulty.easy);
      expect(step.mask, uniqueFiveSolution[step.cell]);
      expect(uniqueFive.fixed[step.cell], 0);
      expect(TrackSide.isPiece(step.mask), isTrue);
    });

    test('it is deterministic', () {
      final empty = List<int>.filled(81, 0);
      final a = nextTracksStep(uniqueNine, empty);
      final b = nextTracksStep(uniqueNine, empty);
      expect(a.toString(), b.toString());
    });

    test('on a partial correct board it never repeats a shown cell', () {
      final shown = List<int>.filled(25, 0);
      // Show the whole first row correctly, then ask.
      for (var i = 0; i < 5; i++) {
        shown[i] = uniqueFiveSolution[i];
      }
      final step = nextTracksStep(uniqueFive, shown);
      expect(step, isNotNull);
      expect(step!.cell, greaterThanOrEqualTo(5));
      expect(step.mask, uniqueFiveSolution[step.cell]);
      expect(shown[step.cell], isNot(step.mask));
    });

    test('a half-drawn cell is not shown as its piece', () {
      // Only one connection drawn at a cell the solver can complete.
      final shown = List<int>.filled(25, 0);
      final first = nextTracksStep(uniqueFive, shown)!;
      final bits = first.mask & -first.mask;
      shown[first.cell] = bits;
      final again = nextTracksStep(uniqueFive, shown)!;
      expect(again.mask, uniqueFiveSolution[again.cell]);
      expect(shown[again.cell], isNot(again.mask));
    });

    test('following the steps solves a puzzle from an empty board', () {
      for (final entry in <(TracksClues, List<int>)>[
        (uniqueFive, uniqueFiveSolution),
        (uniqueSeven, uniqueSevenSolution),
        (uniqueNine, uniqueNineSolution),
        (uniqueNineB, uniqueNineBSolution),
      ]) {
        final clues = entry.$1;
        final solution = entry.$2;
        final shown = List<int>.filled(solution.length, 0);
        var guard = 0;
        while (true) {
          final step = nextTracksStep(clues, shown);
          if (step == null) break;
          expect(step.mask, solution[step.cell]);
          expect(shown[step.cell], isNot(step.mask));
          shown[step.cell] = step.mask;
          expect(++guard, lessThanOrEqualTo(solution.length));
        }
        for (var i = 0; i < shown.length; i++) {
          // Everything the player did not have to place is a fixed cell or an
          // empty one.
          expect(
            shown[i] == solution[i] || clues.fixed[i] != 0 || solution[i] == 0,
            isTrue,
            reason: 'cell $i',
          );
        }
      }
    });

    test('a complete board has no next step', () {
      expect(nextTracksStep(uniqueFive, uniqueFiveSolution), isNull);
      expect(nextTracksStep(uniqueNine, uniqueNineSolution), isNull);
    });

    test('a board that contradicts the clues has no next step', () {
      final wrong = List<int>.filled(25, 0)..[24] = 5;
      expect(nextTracksStep(uniqueFive, wrong), isNull);
    });

    test('a stalled puzzle has no next step', () {
      // Everything the two solutions share is shown; the cells where they
      // differ are not, and no deduction can choose between them.
      final shown = [
        for (var i = 0; i < 25; i++)
          twoFiveFirst[i] == twoFiveSecond[i] ? twoFiveFirst[i] : 0,
      ];
      expect(twoFiveFirst, isNot(twoFiveSecond));
      expect(nextTracksStep(twoFive, shown), isNull);
    });

    test('a board of the wrong length is refused', () {
      expect(
        () => nextTracksStep(uniqueFive, List<int>.filled(24, 0)),
        throwsArgumentError,
      );
    });
  });

  group('soundness against the counter', () {
    const perSize = 300;
    for (final spec in TracksSpec.supported) {
      test('${spec.label}: $perSize random clue sets', () {
        var solvedCount = 0;
        var checked = 0;
        for (var seed = 0; seed < perSize; seed++) {
          final made = randomClues(spec, seed);
          if (made == null) continue;
          final clues = made.clues;

          var previous = false;
          for (final ceiling in [
            Difficulty.easy,
            Difficulty.medium,
            Difficulty.hard,
          ]) {
            final report = solveTracks(clues, ceiling: ceiling);
            final reason =
                '${spec.label} seed $seed $ceiling ${clues.encode()}';
            // Whatever it proved is true of the path the clues came from, which
            // is one solution; if it is the only one the proofs are all true.
            for (var i = 0; i < report.cells.length; i++) {
              expect(
                report.cells[i] & ~made.solution[i],
                0,
                reason: '$reason cell $i',
              );
            }
            if (report.solved) {
              expect(report.cells, made.solution, reason: reason);
              expect(brokenRules(clues, report.cells), isEmpty, reason: reason);
              expect(report.tier.index, lessThanOrEqualTo(ceiling.index));
              expect(
                countTracksSolutions(clues, maxNodes: 4000000),
                1,
                reason: reason,
              );
            } else {
              expect(report.tier, Difficulty.expert);
              // More allowed tiers can only help.
              expect(previous, isFalse, reason: reason);
            }
            previous = report.solved;
          }
          if (previous) solvedCount++;
          checked++;
        }
        expect(checked, greaterThan(perSize ~/ 2));
        expect(solvedCount, greaterThan(0));
      });
    }

    test('a hint from a partly shown correct board is the solution piece', () {
      final rng = Rng(99);
      for (final spec in TracksSpec.supported) {
        for (var seed = 0; seed < 100; seed++) {
          final made = randomClues(spec, seed);
          if (made == null) continue;
          final shown = [
            for (final mask in made.solution) rng.nextInt(2) == 0 ? mask : 0,
          ];
          final step = nextTracksStep(made.clues, shown);
          if (step == null) continue;
          expect(
            step.mask,
            made.solution[step.cell],
            reason: '${made.clues.encode()} cell ${step.cell}',
          );
          expect(shown[step.cell], isNot(step.mask));
        }
      }
    });

    test('every solution the counter finds agrees with the proven edges', () {
      // The converse direction on a clue set the solver cannot finish: each
      // edge it did prove is in every solution, not just the generating path.
      var unsolvedWithCounts = 0;
      for (var seed = 0; seed < 200; seed++) {
        final made = randomClues(TracksSpec.s5x5, seed);
        if (made == null) continue;
        final report = solveTracks(made.clues);
        if (report.solved) continue;
        final all = solutionsOf(made.clues, limit: 1000);
        expect(all, isNotEmpty); // the generating path at least
        for (final solution in all) {
          for (var i = 0; i < solution.length; i++) {
            expect(
              report.cells[i] & ~solution[i],
              0,
              reason: 'seed $seed cell $i ${made.clues.encode()}',
            );
          }
        }
        unsolvedWithCounts++;
      }
      expect(unsolvedWithCounts, greaterThan(0));
    });
  });
}
