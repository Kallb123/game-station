// The generator is the one part of the engine whose output is a stored format:
// a save file keeps the ID and throws the grid away, so `generateSudoku` has to
// answer the same thing on every platform and in every release, and it has to
// answer *something* — a child cannot act on "could not generate a puzzle".
//
// These tests check the properties that make that true for a handful of indices
// per size and difficulty. The volume run is `fuzz_test.dart` and the frozen
// output is `determinism_test.dart`'s goldens; what is here is the contract
// those two hold the generator to at scale.
//
// `GENERATOR_INDICES` raises the count per size and difficulty from the default
// 3, which is what keeps this file to about a second — the goldens are where
// the suite spends its time, and this one stays cheap enough to re-run on every
// edit to the generator. The sweep at 200, which `PLAN-phase-2.md` §6's PR 5
// criteria ask for, is run by hand and reported in the pull request.

import 'dart:io';

import 'package:puzzle_engine/src/generator.dart';
import 'package:puzzle_engine/src/puzzle_id.dart';
import 'package:puzzle_engine/src/solver.dart';
import 'package:puzzle_engine/src/sudoku_board.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:puzzle_engine/src/technique_solver.dart';
import 'package:test/test.dart';

import 'combinations.dart';

/// How many indices of each combination to generate.
final int indices =
    int.tryParse(Platform.environment['GENERATOR_INDICES'] ?? '') ?? 3;

void main() {
  group('every puzzle it makes', () {
    for (final (spec, difficulty) in combinations) {
      test('${spec.label} ${difficulty.name} is a real puzzle', () {
        for (var index = 0; index < indices; index++) {
          final id = PuzzleId(spec, difficulty, index);
          final puzzle = generateSudoku(id);
          final where = '$id';

          expect(puzzle.id, id, reason: where);
          expect(puzzle.requested, difficulty, reason: where);
          expect(puzzle.attempts, greaterThanOrEqualTo(1), reason: where);

          final board = SudokuBoard.fromClues(spec, puzzle.clues);
          expect(board.filledCount, puzzle.clueCount, reason: where);
          expect(
            countSolutions(board),
            1,
            reason: '$where has more than one answer, or none',
          );

          // The solution is a completion of the clues rather than a grid that
          // merely fits the same shape: every clue has to survive in it.
          final solved = SudokuBoard.fromClues(spec, puzzle.solution);
          expect(solved.isFull, isTrue, reason: where);
          for (var cell = 0; cell < spec.cells; cell++) {
            final clue = board.digitAt(cell);
            if (clue == 0) continue;
            expect(solved.digitAt(cell), clue, reason: '$where at cell $cell');
          }
        }
      });
    }
  });

  group('the label it promises', () {
    for (final (spec, difficulty) in combinations) {
      test('${spec.label} ${difficulty.name} is what the recipe asks', () {
        final recipe = recipeFor(spec, difficulty);
        for (var index = 0; index < indices; index++) {
          final puzzle = generateSudoku(PuzzleId(spec, difficulty, index));
          final where = '${puzzle.id} -> $puzzle';

          // Judged again from the clue string rather than trusted from the
          // attempt that made it: the generator and the solver cannot drift
          // apart without this failing.
          final rejudged = solveWithTechniques(
            SudokuBoard.fromClues(spec, puzzle.clues),
          );
          expect(rejudged.tier, puzzle.tier, reason: where);

          if (puzzle.widened) {
            expect(
              recipe.accepts(puzzle.tier, puzzle.clueCount),
              isFalse,
              reason: 'widened means the recipe was missed: $where',
            );
            continue;
          }
          expect(
            recipe.accepts(puzzle.tier, puzzle.clueCount),
            isTrue,
            reason: where,
          );
          expect(puzzle.clueCount, greaterThanOrEqualTo(recipe.floor));
          expect(puzzle.clueCount, lessThanOrEqualTo(recipe.ceiling));
        }
      });
    }
  });

  group('the same ID', () {
    test('produces the same puzzle, down to the attempt count', () {
      // This is the property a save file is built on. If it ever fails, every
      // stored puzzle ID names a different grid than it did.
      for (final (spec, difficulty) in combinations) {
        for (var index = 0; index < indices; index++) {
          final id = PuzzleId(spec, difficulty, index);
          final first = generateSudoku(id);
          final second = generateSudoku(id);

          expect(first.clues, second.clues, reason: '$id');
          expect(first.solution, second.solution, reason: '$id');
          expect(first.tier, second.tier, reason: '$id');
          expect(first.attempts, second.attempts, reason: '$id');
          expect(first.widened, second.widened, reason: '$id');
        }
      }
    });

    test('is reproduced from its parsed string', () {
      // The app will hold an ID it read out of a file, not one it built.
      const text = 'sudoku:9x9:medium:7';
      expect(
        generateSudoku(PuzzleId.parse(text)).clues,
        generateSudoku(
          const PuzzleId(SudokuSpec.s9x9, Difficulty.medium, 7),
        ).clues,
      );
    });
  });

  group('different IDs', () {
    test('are different puzzles, not one puzzle dug twice', () {
      // The seed is a hash of the whole ID string, so neighbouring indices and
      // neighbouring labels share nothing.
      final clues = <String>{};
      for (final (spec, difficulty) in combinations) {
        for (var index = 0; index < indices; index++) {
          clues.add(generateSudoku(PuzzleId(spec, difficulty, index)).clues);
        }
      }
      expect(clues, hasLength(combinations.length * indices));
    });

    test('at the same index and size differ by label', () {
      final easy = generateSudoku(
        const PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 1),
      );
      final hard = generateSudoku(
        const PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 1),
      );
      expect(easy.clues, isNot(hard.clues));
      expect(easy.solution, isNot(hard.solution));
    });
  });

  group('a size and label with no puzzles', () {
    test('is refused in release, not only by an assertion', () {
      // `PuzzleId.parse` will not spell 6x6 Expert, but the constructor is
      // `const` and cannot check it, so the guard that matters is here.
      expect(
        () => recipeFor(SudokuSpec.s6x6, Difficulty.expert),
        throwsArgumentError,
      );
      expect(
        () => generateSudoku(
          const PuzzleId(SudokuSpec.s6x6, Difficulty.expert, 1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('the recipes', () {
    test('describe bands a puzzle can actually be dug into', () {
      for (final (spec, difficulty) in combinations) {
        final recipe = recipeFor(spec, difficulty);
        expect(recipe.floor, lessThanOrEqualTo(recipe.ceiling));
        expect(
          recipe.lowestTier.index,
          lessThanOrEqualTo(recipe.highestTier.index),
        );
        expect(
          recipe.ceiling,
          lessThan(spec.cells),
          reason: 'a puzzle with every cell filled is not a puzzle',
        );
      }
    });

    test('get harder as the label does', () {
      // Whatever the tiers say, a child moving down the menu should be given
      // fewer clues, at both sizes. This is the whole of what 6x6 Medium
      // means, and it has to hold for 9x9 too or the labels are decoration.
      for (final spec in [SudokuSpec.s9x9, SudokuSpec.s6x6]) {
        var previous = spec.cells;
        for (final difficulty in Difficulty.values) {
          if (spec == SudokuSpec.s6x6 && difficulty == Difficulty.expert) {
            continue;
          }
          final recipe = recipeFor(spec, difficulty);
          expect(
            recipe.floor,
            lessThan(previous),
            reason: '${spec.label} ${difficulty.name}',
          );
          previous = recipe.floor;
        }
      }
    });
  });
}
