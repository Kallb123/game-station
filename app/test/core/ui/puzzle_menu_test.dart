// The line under a difficulty, row by row of `PLAN-best-time-assists.md` §4.6.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/completion_card.dart';
import 'package:zibo_games/core/ui/puzzle_menu.dart';

void main() {
  test('says nothing is solved when nothing is', () {
    expect(tierProgressLabel(solved: 0, bestTimeMs: null), 'Not solved yet');
  });

  test('shows the best time alone where the detail is unknown', () {
    expect(
      tierProgressLabel(solved: 3, bestTimeMs: 245000),
      'Solved 3 · Best 4:05',
    );
  });

  test('reuses the completion card phrase for a clean solve', () {
    final label = tierProgressLabel(
      solved: 3,
      bestTimeMs: 245000,
      bestAssists: (hints: 0, mistakes: 0),
    );

    expect(label, 'Solved 3 · Best 4:05 · No hints, no mistakes');
    expect(label, endsWith(completionCleanLabel));
  });

  test('counts both kinds, with the plural following the count', () {
    expect(
      tierProgressLabel(
        solved: 3,
        bestTimeMs: 245000,
        bestAssists: (hints: 2, mistakes: 1),
      ),
      'Solved 3 · Best 4:05 · 2 hints, 1 mistake',
    );
    expect(
      tierProgressLabel(
        solved: 3,
        bestTimeMs: 245000,
        bestAssists: (hints: 1, mistakes: 2),
      ),
      'Solved 3 · Best 4:05 · 1 hint, 2 mistakes',
    );
  });

  test('leaves a zero count out', () {
    expect(
      tierProgressLabel(
        solved: 3,
        bestTimeMs: 245000,
        bestAssists: (hints: 1, mistakes: 0),
      ),
      'Solved 3 · Best 4:05 · 1 hint',
    );
    expect(
      tierProgressLabel(
        solved: 3,
        bestTimeMs: 245000,
        bestAssists: (hints: 0, mistakes: 3),
      ),
      'Solved 3 · Best 4:05 · 3 mistakes',
    );
  });

  test('ignores the assists when there is no best time', () {
    expect(
      tierProgressLabel(
        solved: 3,
        bestTimeMs: null,
        bestAssists: (hints: 2, mistakes: 1),
      ),
      'Solved 3',
    );
  });

  test('says nothing is solved even if assists are passed', () {
    expect(
      tierProgressLabel(
        solved: 0,
        bestTimeMs: null,
        bestAssists: (hints: 2, mistakes: 1),
      ),
      'Not solved yet',
    );
  });
}
