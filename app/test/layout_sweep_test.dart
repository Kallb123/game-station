// The guard `PLAN-phase-5.md` §4.8 exists to add: every route, pumped at
// three window sizes and two text scales, with the assertion that nothing
// throws. Nothing before this pull request had ever driven these screens
// through a size or an orientation they were not built and eyeballed at —
// a `RenderFlex` overflow, an unbounded constraint or a failed assertion
// throws during a widget test, which is what `tester.takeException()`
// catches here.
//
// This is the expensive kind of test, which is why this file is the one
// shared harness rather than one test per combination (`PLAN.md` §6). The
// brightness axis §4.8 also names is dropped, as its own risk row says to
// when the sweep does not fit `flutter test`'s 60 s budget: day and night
// share every spacing and size token, so a `RenderFlex` overflow does not
// know the difference, and `contrast_test.dart` already walks both palettes
// for the one thing that does.

import 'dart:async';
import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/layout.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart'
    show playInvadersLabel;
import 'package:zibo_games/features/arcade/invaders/invaders_game.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/data/providers.dart';
import 'package:zibo_games/features/draw/ui/draw_sheet_screen.dart';
import 'package:zibo_games/features/sudoku/data/providers.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_play_screen.dart';
import 'package:zibo_games/routes.dart';

import 'app_harness.dart';
import 'features/sudoku/puzzle_fixtures.dart';

/// The three window sizes `PLAN-phase-5.md` §4.8 names: a phone, the same
/// phone turned on its side, and a tablet — an `830x1112` window is
/// [AppFormFactor.expanded] by its short side alone, whichever way round it
/// is held.
const Map<String, Size> _sweepSizes = {
  'a phone': Size(360, 640),
  'a phone in landscape': Size(640, 360),
  'a tablet': Size(834, 1112),
};

/// Every route, and the arguments it needs to be pushed with — every one but
/// [AppRoutes.sudokuPlay] takes none (`routes.dart`).
Map<String, Object?> _sweepRoutes(PuzzleId puzzleId) => {
  AppRoutes.home: null,
  AppRoutes.profiles: null,
  AppRoutes.settings: null,
  AppRoutes.sudoku: null,
  AppRoutes.sudokuPlay: SudokuPlayArgs(puzzleId),
  AppRoutes.arcade: null,
  AppRoutes.arcadeInvaders: null,
  AppRoutes.draw: null,
  AppRoutes.drawSheet: const DrawSheetArgs(),
};

/// Leaves the game the way a child would, so the repository's debounced
/// write from `startArcadeGame` lands before the tree comes down instead of
/// firing after it and failing the test on its own.
Future<void> _quit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back').last);
  await tester.pump();
  await tester.tap(find.text('Stop'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

void main() {
  final puzzleId = PuzzleId.parse('sudoku:9x9:easy:0');

  for (final routeEntry in _sweepRoutes(puzzleId).entries) {
    for (final sizeEntry in _sweepSizes.entries) {
      for (final textScale in [1.0, 2.0]) {
        testWidgets('${routeEntry.key} fits ${sizeEntry.key} at '
            '${(textScale * 100).round()}% text', (tester) async {
          tester.view.physicalSize = sizeEntry.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.platformDispatcher.textScaleFactorTestValue = textScale;
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          final drawingDir = Directory.systemTemp.createTempSync(
            'zibo_games_layout_sweep',
          );
          addTearDown(() {
            if (drawingDir.existsSync()) drawingDir.deleteSync(recursive: true);
          });

          final container = await pumpApp(
            tester,
            store: MemorySaveStore(initial: freshSave()),
            overrides: [
              puzzleSourceProvider.overrideWithValue(FakePuzzleSource()),
              drawingRepositoryProvider.overrideWithValue(
                DrawingRepository(drawingDir),
              ),
            ],
          );

          final navigator = tester.state<NavigatorState>(
            find.byType(Navigator),
          );
          unawaited(
            navigator.pushNamed(routeEntry.key, arguments: routeEntry.value),
          );
          // Bounded pumps rather than `pumpAndSettle`: `InvadersScreen`'s
          // `GameWidget` reschedules a frame on every tick for as long as
          // it is mounted, so settling on it never finishes.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));

          expect(tester.takeException(), isNull);

          // Lands whatever `AppRoutes.arcadeInvaders`'s `startArcadeGame`
          // scheduled in the repository's 500 ms debounce — otherwise it
          // fires after the tree comes down and fails the test on its own.
          await container.read(progressRepositoryProvider).flush();

          // The one route-specific claim a generic sweep cannot make on
          // its own: the board is square and never past `maxBoardSide`,
          // whatever room the window leaves it (`PLAN-phase-5.md` §4.8).
          // The frame drawn square is the `DecoratedBox` inside
          // `SudokuGridView`, not that widget's own box — `LayoutBuilder`
          // reports back whatever non-square rectangle it was given
          // (`sudoku_grid_view_test.dart` measures the same way).
          final grid = find.byType(SudokuGridView);
          if (grid.evaluate().isNotEmpty) {
            final frame = find
                .descendant(of: grid, matching: find.byType(DecoratedBox))
                .first;
            final size = tester.getSize(frame);
            expect(
              size.width,
              closeTo(size.height, 0.5),
              reason: 'the board must stay square',
            );
            expect(size.width, lessThanOrEqualTo(maxBoardSide));
          }
        });
      }
    }
  }

  testWidgets(
    'an Invaders run survives a size change with the same instance and '
    'its score',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpApp(
        tester,
        store: MemorySaveStore(initial: freshSave()),
        overrides: [nowProvider.overrideWithValue(testClock)],
      );
      await tester.tap(find.text('Arcade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(playInvadersLabel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final game = tester
          .widget<GameWidget<InvadersGame>>(
            find.byType(GameWidget<InvadersGame>),
          )
          .game!;
      game.sim.debugAwardScore(500);

      // The rotation itself: the same `MediaQuery` size change a device
      // delivers, turning the phone on its side.
      tester.view.physicalSize = const Size(640, 360);
      await tester.pump();

      final rotated = tester
          .widget<GameWidget<InvadersGame>>(
            find.byType(GameWidget<InvadersGame>),
          )
          .game!;
      expect(
        identical(rotated, game),
        isTrue,
        reason: 'a rotation must not restart the run',
      );
      // `sim.score` rather than `hud.value.score`: the HUD notifier is only
      // refreshed by a fixed step actually running in `InvadersGame.update`,
      // where the score itself is the fact the rotation must not lose.
      expect(rotated.sim.score, 500);

      await _quit(tester);
    },
  );
}
