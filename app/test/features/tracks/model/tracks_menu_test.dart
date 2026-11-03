import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/model/tracks_difficulties.dart';
import 'package:zibo_games/features/tracks/model/tracks_menu.dart';

void main() {
  TracksPuzzleId id(TracksSpec spec, Difficulty difficulty, int index) =>
      TracksPuzzleId(spec, difficulty, index);

  TracksPuzzleId easy5(int index) =>
      id(TracksSpec.s5x5, Difficulty.easy, index);

  TracksInProgress board({int elapsedMs = 0}) =>
      TracksInProgress(cells: '0' * 25, elapsedMs: elapsedMs);

  SolvedPuzzle solvedAt(int day, {int timeMs = 1000}) =>
      SolvedPuzzle(timeMs: timeMs, solvedAt: DateTime.utc(2026, 8, day));

  TracksMenu menuOf({
    Map<String, SolvedPuzzle> solved = const {},
    Map<String, TracksInProgress> inProgress = const {},
    Map<String, int> bestTimeMs = const {},
  }) => TracksMenu.of(
    TracksProgress(
      solved: solved,
      inProgress: inProgress,
      bestTimeMs: bestTimeMs,
    ),
  );

  group('Keep going', () {
    test('is absent when nothing is half-finished', () {
      expect(menuOf().continuePuzzle, isNull);
      expect(
        menuOf(solved: {easy5(0).value: solvedAt(1)}).continuePuzzle,
        isNull,
      );
    });

    test('is the board with the most time on its clock', () {
      final menu = menuOf(
        inProgress: {
          easy5(0).value: board(elapsedMs: 5000),
          id(TracksSpec.s7x7, Difficulty.medium, 2).value: board(
            elapsedMs: 9000,
          ),
          easy5(1).value: board(elapsedMs: 100),
        },
      );

      expect(menu.continuePuzzle, id(TracksSpec.s7x7, Difficulty.medium, 2));
    });

    test('breaks a tie by the id, ascending', () {
      final menu = menuOf(
        inProgress: {
          easy5(3).value: board(elapsedMs: 5000),
          easy5(1).value: board(elapsedMs: 5000),
          easy5(2).value: board(elapsedMs: 5000),
        },
      );

      expect(menu.continuePuzzle, easy5(1));
    });

    test('ignores a key this build cannot spell', () {
      final menu = menuOf(
        inProgress: {
          'tracks:5x5:hard:0': board(elapsedMs: 99999),
          'nonsense': board(elapsedMs: 99999),
          easy5(4).value: board(elapsedMs: 10),
        },
      );

      expect(menu.continuePuzzle, easy5(4));
    });
  });

  group('the lowest unsolved index', () {
    test('is 0 for a tier with no history', () {
      expect(menuOf().nextPuzzle(TracksSpec.s5x5, Difficulty.easy), easy5(0));
    });

    test('skips solved indexes and stops at the first gap', () {
      final menu = menuOf(
        solved: {
          easy5(0).value: solvedAt(1),
          easy5(1).value: solvedAt(1),
          easy5(3).value: solvedAt(1),
        },
      );

      expect(menu.nextPuzzle(TracksSpec.s5x5, Difficulty.easy), easy5(2));
    });

    test('starts at 0 when only later indexes are solved', () {
      final menu = menuOf(solved: {easy5(2).value: solvedAt(1)});

      expect(menu.nextPuzzle(TracksSpec.s5x5, Difficulty.easy), easy5(0));
    });

    test('offers a half-finished puzzle again rather than skipping it', () {
      final menu = menuOf(
        solved: {easy5(0).value: solvedAt(1)},
        inProgress: {easy5(1).value: board(elapsedMs: 10)},
      );

      expect(menu.nextPuzzle(TracksSpec.s5x5, Difficulty.easy), easy5(1));
    });

    test('is not moved by other tiers or other sizes', () {
      final menu = menuOf(
        solved: {
          id(TracksSpec.s5x5, Difficulty.medium, 0).value: solvedAt(1),
          id(TracksSpec.s7x7, Difficulty.easy, 0).value: solvedAt(1),
        },
      );

      expect(menu.nextPuzzle(TracksSpec.s5x5, Difficulty.easy), easy5(0));
    });
  });

  group('records', () {
    test('count solved puzzles per size and tier', () {
      final menu = menuOf(
        solved: {
          easy5(0).value: solvedAt(1),
          easy5(1).value: solvedAt(2),
          id(TracksSpec.s7x7, Difficulty.easy, 0).value: solvedAt(3),
          'nonsense': solvedAt(4),
        },
      );

      expect(menu.solvedCount(TracksSpec.s5x5, Difficulty.easy), 2);
      expect(menu.solvedCount(TracksSpec.s7x7, Difficulty.easy), 1);
      expect(menu.solvedCount(TracksSpec.s9x9, Difficulty.easy), 0);
    });

    test('best time is read from the stored key, and absent otherwise', () {
      final menu = menuOf(
        bestTimeMs: {
          TracksProgress.bestTimeKey(TracksSpec.s7x7, Difficulty.medium): 4200,
        },
      );

      expect(menu.bestTimeMs(TracksSpec.s7x7, Difficulty.medium), 4200);
      expect(menu.bestTimeMs(TracksSpec.s7x7, Difficulty.easy), isNull);
    });
  });

  group('what the menu opens on', () {
    test('a profile with no history gets the defaults', () {
      final menu = menuOf();

      expect(menu.lastPlayed, isNull);
      expect(menu.lastSpec, defaultTracksSpec);
      expect(menu.lastDifficultyFor(TracksSpec.s9x9), defaultTracksDifficulty);
    });

    test('Keep going outranks the latest solve', () {
      final menu = menuOf(
        solved: {easy5(0).value: solvedAt(9)},
        inProgress: {
          id(TracksSpec.s9x9, Difficulty.medium, 0).value: board(elapsedMs: 1),
        },
      );

      expect(menu.lastSpec, TracksSpec.s9x9);
      expect(menu.lastDifficultyFor(TracksSpec.s9x9), Difficulty.medium);
    });

    test('otherwise the latest solve decides, ties by id', () {
      final menu = menuOf(
        solved: {
          easy5(0).value: solvedAt(1),
          id(TracksSpec.s7x7, Difficulty.hard, 0).value: solvedAt(5),
          id(TracksSpec.s9x9, Difficulty.easy, 0).value: solvedAt(5),
        },
      );

      expect(menu.lastPlayed, id(TracksSpec.s7x7, Difficulty.hard, 0));
      expect(menu.lastSpec, TracksSpec.s7x7);
    });

    test('Hard is clamped to the hardest tier 5x5 offers', () {
      final menu = menuOf(
        solved: {id(TracksSpec.s7x7, Difficulty.hard, 0).value: solvedAt(1)},
      );

      expect(menu.lastDifficultyFor(TracksSpec.s7x7), Difficulty.hard);
      expect(menu.lastDifficultyFor(TracksSpec.s5x5), Difficulty.medium);
    });
  });
}
