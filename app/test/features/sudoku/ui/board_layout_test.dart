// The board and the keypad in the arrangement the play screen will put them
// in: the grid taking the space that is left, the keypad taking what it needs.
//
// PR 6 owns that screen. What this file checks is the property the screen
// cannot fix for itself — that the two widgets fit together on the smallest
// target at the largest text scale, at both sizes and in both themes
// (`PLAN-phase-3.md` §1, §6). An overflow is reported as an exception in a
// widget test, so `takeException` is the assertion.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/ui/tokens.dart';
import 'package:game_station/features/sudoku/model/sudoku_session.dart';
import 'package:game_station/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:game_station/features/sudoku/ui/sudoku_keypad.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/ui/ui_harness.dart';
import '../puzzle_fixtures.dart';

void main() {
  final ids = [
    PuzzleId.parse('sudoku:6x6:easy:11'),
    PuzzleId.parse('sudoku:9x9:easy:11'),
  ];

  Widget board(SudokuSession session) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            Expanded(child: SudokuGridView(session: session)),
            const SizedBox(height: AppSpacing.lg),
            SudokuKeypad(session: session),
          ],
        ),
      ),
    ),
  );

  for (final id in ids) {
    for (final theme in appThemes.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('a ${id.spec.label} board fits a small phone at '
            '${(scale * 100).round()}% text scale in ${theme.key}', (
          tester,
        ) async {
          await usePhoneSurface(tester);

          await pumpApp(
            tester,
            board(fixtureSession(id)),
            theme: theme.value(),
            textScale: scale,
            // A notch and a gesture bar, so the safe area is doing something
            // rather than being zero on a test surface.
            padding: const EdgeInsets.only(top: 44, bottom: 34),
          );

          expect(tester.takeException(), isNull);
          // The board is still square and still on screen: an overflow is
          // not the only way a layout fails, and a grid squeezed to nothing
          // would pass the check above.
          final grid = tester.getSize(
            find
                .descendant(
                  of: find.byType(SudokuGridView),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(grid.width, grid.height);
          expect(grid.width, greaterThan(AppTapTargets.primary));
        });
      }
    }
  }
}
