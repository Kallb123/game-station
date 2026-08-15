// The arithmetic behind every number the menu draws.
//
// Plain `test()` calls: [SudokuMenu] is pure over a [SudokuProgress]
// (`PLAN-phase-3.md` §5), so the rules that decide which puzzle each card
// offers are checked here rather than by reading them back out of a widget
// tree.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/sudoku/model/difficulties.dart';
import 'package:zibo_games/features/sudoku/model/sudoku_menu.dart';

void main() {
  const inProgress = PuzzleInProgress(grid: '...', elapsedMs: 1000);

  SudokuMenu menuOf({
    Map<String, SolvedPuzzle> solved = const {},
    Map<String, PuzzleInProgress> inProgress = const {},
    DailyStreak streak = const DailyStreak(),
    Map<String, int> bestTimeMs = const {},
  }) => SudokuMenu.of(
    SudokuProgress(
      solved: solved,
      inProgress: inProgress,
      dailyStreak: streak,
      bestTimeMs: bestTimeMs,
    ),
  );

  group('the continue card', () {
    test('offers nothing for a profile with nothing half-finished', () {
      expect(menuOf().continuePuzzle, isNull);
    });

    test('offers the board with the most time on its clock', () {
      // Which puzzle was played *last* is not recoverable — v1 stores no
      // timestamp on an in-progress board (`sudoku_menu.dart`) — so the rule is
      // the one a save can support, and this is the test that says which rule
      // it is.
      final menu = menuOf(
        inProgress: const {
          'sudoku:9x9:easy:1': PuzzleInProgress(grid: '.', elapsedMs: 30000),
          'sudoku:6x6:hard:2': PuzzleInProgress(grid: '.', elapsedMs: 900000),
          'sudoku:9x9:hard:3': PuzzleInProgress(grid: '.', elapsedMs: 60000),
        },
      );

      expect(
        menu.continuePuzzle,
        const PuzzleId(SudokuSpec.s6x6, Difficulty.hard, 2),
      );
    });

    test('breaks a tie by id rather than by map order', () {
      // Two boards with the same time on them is not a hypothetical: a board
      // opened and left alone twice has 0 ms on both. Iterating a map would
      // decide it, and a map's order is not something to decide a screen with.
      final ids = ['sudoku:9x9:easy:5', 'sudoku:9x9:easy:2'];
      final forwards = menuOf(
        inProgress: {for (final id in ids) id: inProgress},
      );
      final backwards = menuOf(
        inProgress: {for (final id in ids.reversed) id: inProgress},
      );

      expect(forwards.continuePuzzle, backwards.continuePuzzle);
      expect(
        forwards.continuePuzzle,
        const PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 2),
      );
    });

    test('ignores an entry this build cannot spell', () {
      // A hand-edited save. One card short is the handling; an exception on the
      // way into the menu is not (`AGENTS.md`).
      final menu = menuOf(
        inProgress: const {
          'sudoku:12x12:easy:1': PuzzleInProgress(grid: '.', elapsedMs: 99000),
          'sudoku:6x6:easy:0': inProgress,
        },
      );

      expect(
        menu.continuePuzzle,
        const PuzzleId(SudokuSpec.s6x6, Difficulty.easy, 0),
      );
    });
  });

  group('the daily card', () {
    test('takes the day index it is given', () {
      expect(menuOf().dailyPuzzle(SudokuSpec.s9x9, 223).index, 223);
    });

    test('is 9x9 Easy for a profile that has played nothing', () {
      final menu = menuOf();

      expect(menu.lastSpec, SudokuSpec.s9x9);
      expect(menu.lastDifficulty, Difficulty.easy);
      expect(
        menu.dailyPuzzle(menu.lastSpec, 4),
        const PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 4),
      );
    });

    test('follows the half-finished board before the solved ones', () {
      final menu = menuOf(
        solved: {
          'sudoku:9x9:medium:0': SolvedPuzzle(
            timeMs: 1000,
            solvedAt: DateTime.utc(2026, 8, 14),
          ),
        },
        inProgress: const {'sudoku:6x6:hard:1': inProgress},
      );

      expect(menu.lastSpec, SudokuSpec.s6x6);
      expect(menu.lastDifficulty, Difficulty.hard);
    });

    test('falls back to the most recently solved puzzle', () {
      final menu = menuOf(
        solved: {
          'sudoku:9x9:easy:0': SolvedPuzzle(
            timeMs: 1000,
            solvedAt: DateTime.utc(2026, 8, 10),
          ),
          'sudoku:6x6:medium:1': SolvedPuzzle(
            timeMs: 1000,
            solvedAt: DateTime.utc(2026, 8, 14),
          ),
        },
      );

      expect(menu.lastSpec, SudokuSpec.s6x6);
      expect(menu.lastDifficulty, Difficulty.medium);
    });

    test('never offers 6x6 Expert', () {
      // The one combination the engine refuses outright, reachable here only
      // because the size the card is drawn at is the menu's and the difficulty
      // is the child's history.
      final menu = menuOf(
        inProgress: const {'sudoku:9x9:expert:0': inProgress},
      );

      expect(menu.lastDifficulty, Difficulty.expert);
      expect(menu.dailyDifficultyFor(SudokuSpec.s6x6), Difficulty.hard);
      expect(
        difficultiesFor(SudokuSpec.s6x6),
        contains(menu.dailyDifficultyFor(SudokuSpec.s6x6)),
      );
      expect(menu.dailyPuzzle(SudokuSpec.s6x6, 1).value, 'sudoku:6x6:hard:1');
    });

    test('shows the streak the profile carries', () {
      expect(menuOf(streak: const DailyStreak(current: 4, best: 9)).streak, 4);
    });
  });

  group('a difficulty row', () {
    test('offers the lowest index this profile has not solved', () {
      final menu = menuOf(
        solved: const {
          'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 1000),
          'sudoku:9x9:easy:1': SolvedPuzzle(timeMs: 1000),
          'sudoku:9x9:easy:3': SolvedPuzzle(timeMs: 1000),
          // Another tier's history does not move this one along.
          'sudoku:9x9:hard:2': SolvedPuzzle(timeMs: 1000),
        },
      );

      expect(
        menu.nextPuzzle(SudokuSpec.s9x9, Difficulty.easy),
        const PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 2),
      );
      expect(
        menu.nextPuzzle(SudokuSpec.s9x9, Difficulty.hard),
        const PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 0),
      );
    });

    test('offers a half-finished puzzle again rather than skipping it', () {
      // The play screen resumes it from the save, which is what a child tapping
      // the tier they were last on expects.
      final menu = menuOf(inProgress: const {'sudoku:6x6:easy:0': inProgress});

      expect(menu.nextPuzzle(SudokuSpec.s6x6, Difficulty.easy).index, 0);
    });

    test('counts the solved puzzles of its own tier', () {
      final menu = menuOf(
        solved: const {
          'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 1000),
          'sudoku:9x9:easy:7': SolvedPuzzle(timeMs: 1000),
          'sudoku:6x6:easy:0': SolvedPuzzle(timeMs: 1000),
          'nonsense': SolvedPuzzle(timeMs: 1000),
        },
      );

      expect(menu.solvedCount(SudokuSpec.s9x9, Difficulty.easy), 2);
      expect(menu.solvedCount(SudokuSpec.s6x6, Difficulty.easy), 1);
      expect(menu.solvedCount(SudokuSpec.s9x9, Difficulty.hard), 0);
    });

    test('reads the best time under the key the repository writes', () {
      // One spelling of `"9x9:easy"`, shared with the code that writes it
      // (`save_data.dart`): two would agree until one of them was edited.
      final menu = menuOf(bestTimeMs: const {'9x9:easy': 245000});

      expect(menu.bestTimeMs(SudokuSpec.s9x9, Difficulty.easy), 245000);
      expect(menu.bestTimeMs(SudokuSpec.s9x9, Difficulty.hard), isNull);
    });
  });
}
