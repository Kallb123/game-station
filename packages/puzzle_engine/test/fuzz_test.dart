// Volume. The goldens freeze 700 puzzles as bytes; this runs the generator over
// far more indices than anyone would read and asserts only the properties that
// have to hold for every puzzle a child could ever be handed: it returns, it
// returns one answer rather than several, the label on it is the label the
// solver agrees with, and it does not take long enough to look broken.
//
// `FUZZ_SEEDS` sets how many puzzles in total, dealt round-robin across the
// seven size-and-label combinations. `verify.sh` and CI both set 2000, so the
// check people run locally and the check that blocks a merge are the same one.
// The default of 200 is what keeps a bare `dart test` affordable while
// iterating.
//
// It counts puzzles rather than indices per combination because the seven
// combinations differ in cost by two orders of magnitude — a 6x6 Easy is well
// under a millisecond and a 9x9 Hard is tens — so 2000 *each* is about five
// minutes, and `PLAN-phase-2.md` §7 promised `verify.sh` would stay near three.
// 2000 puzzles across the matrix is about 40 s and still walks every
// combination past index 250.
@Timeout(Duration(minutes: 30))
library;

import 'dart:io';

import 'package:puzzle_engine/src/generator.dart';
import 'package:puzzle_engine/src/puzzle_id.dart';
import 'package:puzzle_engine/src/solver.dart';
import 'package:puzzle_engine/src/sudoku_board.dart';
import 'package:puzzle_engine/src/technique_solver.dart';
import 'package:test/test.dart';

import 'combinations.dart';

/// How many puzzles to generate in total, across every size and difficulty.
final int fuzzSeeds =
    int.tryParse(Platform.environment['FUZZ_SEEDS'] ?? '') ?? 200;

/// The longest one call to `generateSudoku` may take (`PLAN-phase-2.md` §4.8).
///
/// A ceiling on a single puzzle rather than on the run: `dart test`'s own
/// timeout already catches a generator that never returns, and the failure this
/// adds is the one a timeout lets through — a puzzle that terminates, in eight
/// seconds, on one seed in a thousand, which reaches a child as a frozen menu.
///
/// Loose against the `PLAN.md` §3.5 targets (400 ms for a 9x9 Hard) because a
/// shared runner under load varies by more than a factor of two and a flaky
/// build is a deleted check. PR 7's benchmark is what measures the targets.
const Duration generateCeiling = Duration(seconds: 2);

void main() {
  for (var slot = 0; slot < combinations.length; slot++) {
    final (spec, difficulty) = combinations[slot];
    // The remainder goes to the earliest combinations, so the deal depends on
    // nothing but FUZZ_SEEDS and the order of the list.
    final count =
        fuzzSeeds ~/ combinations.length +
        (slot < fuzzSeeds % combinations.length ? 1 : 0);

    test('${spec.label} ${difficulty.name} generates cleanly', () {
      var slowest = Duration.zero;
      var slowestId = '';

      for (var index = 0; index < count; index++) {
        final id = PuzzleId(spec, difficulty, index);

        final watch = Stopwatch()..start();
        final puzzle = generateSudoku(id);
        watch.stop();
        if (watch.elapsed > slowest) {
          slowest = watch.elapsed;
          slowestId = '$id';
        }

        final board = SudokuBoard.fromClues(spec, puzzle.clues);
        expect(
          board.filledCount,
          puzzle.clueCount,
          reason: '$id: the clue string and the reported count disagree',
        );

        // One answer, and one the search could actually establish: a capped
        // search returns unknownSolutionCount, which is not 1, so a puzzle the
        // solver cannot settle fails here rather than reaching a child as a
        // grid with two endings.
        expect(
          countSolutions(board),
          1,
          reason:
              '$id: expected exactly one solution; '
              '$unknownSolutionCount means the node cap was hit',
        );

        // The tier re-derived from the emitted clues rather than taken from the
        // attempt that made them, so the generator and the solver cannot drift
        // apart about what the label means.
        expect(
          solveWithTechniques(board).tier,
          puzzle.tier,
          reason: '$id: rejudging the clue string disagrees with $puzzle',
        );
      }

      expect(
        slowest,
        lessThan(generateCeiling),
        reason:
            'the slowest of $count was $slowestId at '
            '${slowest.inMilliseconds} ms',
      );
    });
  }
}
