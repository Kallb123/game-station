// `/arcade/snake` end to end (`PLAN-phase-7-snake.md` §6, PR 4): reachable
// from the arcade menu's own Snake card, drawing a D-pad rather than
// Invaders' lateral pad, and writing a finished run to the save through
// `GameShell`.
//
// Every test here uses bounded `tester.pump` calls rather than
// `tester.pumpAndSettle`: `SnakeGame` runs a live Flame ticker once mounted,
// which never reaches a settled frame, so `pumpAndSettle` would hang forever
// (`invaders_screen_test.dart`'s own header gives the same reason).

import 'package:flame/game.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart'
    show playSnakeLabel;
import 'package:zibo_games/features/arcade/shared/on_screen_pad.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_sim.dart';
import 'package:zibo_games/features/arcade/snake/snake_game.dart';
import 'package:zibo_games/features/arcade/snake/snake_screen.dart';

import '../../../app_harness.dart';

/// Pumps [count] frames at roughly 60 Hz — never `pumpAndSettle`, which
/// would wait forever on `SnakeGame`'s live Flame ticker.
Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Leaves a still-running game through `GameShell`'s quit confirmation
/// (`game_shell_test.dart` covers the confirmation itself).
Future<void> _quit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back').last);
  await tester.pump(); // opens "Stop playing?"
  await tester.tap(find.text('Stop'));
  await _pumpFrames(tester, 5);
}

/// Starts a fresh app, opens `/arcade/snake` through the arcade menu's own
/// Snake card, and returns the container so a test can read what `GameShell`
/// wrote to the repository.
Future<ProviderContainer> _openSnake(WidgetTester tester) async {
  final container = await pumpApp(
    tester,
    store: MemorySaveStore(initial: freshSave()),
    overrides: [nowProvider.overrideWithValue(testClock)],
  );

  await tester.tap(find.text('Arcade'));
  await tester.pumpAndSettle();
  // Scrolled into view first: the Snake card sits below the Invaders card
  // now that the menu draws one per game (`PLAN-phase-7-snake.md` §4.9), and
  // an 800x600 test surface does not fit both without scrolling.
  final playSnake = find.widgetWithText(BigButton, playSnakeLabel);
  await tester.ensureVisible(playSnake);
  await tester.pump();
  await tester.tap(playSnake);
  return container;
}

SnakeGame _currentGame(WidgetTester tester) => tester
    .widget<GameWidget<SnakeGame>>(find.byType(GameWidget<SnakeGame>))
    .game!;

void main() {
  testWidgets('opening Snake renders a playable field with a D-pad', (
    tester,
  ) async {
    await _openSnake(tester);
    await _pumpFrames(tester, 20); // past the page transition, several frames

    expect(find.byType(GameWidget<SnakeGame>), findsOneWidget);
    expect(find.byKey(OnScreenPad.upKey), findsOneWidget);
    expect(find.byKey(OnScreenPad.downKey), findsOneWidget);
    expect(find.byKey(OnScreenPad.leftKey), findsOneWidget);
    expect(find.byKey(OnScreenPad.rightKey), findsOneWidget);
    expect(
      find.byKey(OnScreenPad.fireKey),
      findsNothing,
      reason: 'Snake has nothing to fire',
    );

    // The sim has advanced: proof the accumulator is actually being fed real
    // frames through the widget, not just that nothing threw.
    expect(_currentGame(tester).debugStepsDone, greaterThan(0));

    await _quit(tester);
  });

  testWidgets("the HUD shows Next 1 and the run's level, labelled Level", (
    tester,
  ) async {
    await _openSnake(tester);
    await _pumpFrames(tester, 3);

    // The default fresh profile counts in ones, starting at 1
    // (`Profile.snakeCounting`'s default), and `snake_screen.dart` passes
    // `waveLabel: 'Level'`.
    expect(find.textContaining('Level 1'), findsOneWidget);
    expect(find.textContaining('Next 1'), findsOneWidget);

    await _quit(tester);
  });

  testWidgets('pause stops the sim and resuming does not replay the pause', (
    tester,
  ) async {
    await _openSnake(tester);
    // Past the page transition, the same margin `_openSnake`'s other callers
    // give it: a tap this soon can land on the incoming screen mid-slide,
    // which `tester.tap`'s own hit-test warning would catch but not fail on.
    await _pumpFrames(tester, 20);

    final game = _currentGame(tester);

    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    final stepsAtPause = game.debugStepsDone;

    await _pumpFrames(tester, 10);
    expect(game.debugStepsDone, stepsAtPause, reason: 'no steps while paused');

    await tester.tap(find.byTooltip('Resume'));
    await _pumpFrames(tester, 3);
    expect(
      game.debugStepsDone,
      greaterThan(stepsAtPause),
      reason: 'resuming does not replay the paused interval, it continues',
    );

    await _quit(tester);
  });

  testWidgets(
    'a run played to game over stores a HighScore with counting set and '
    'raises bestLength',
    (tester) async {
      final container = await _openSnake(tester);
      await _pumpFrames(tester, 3);

      final game = _currentGame(tester);

      // One real eat, through the same `debugSetTargets` seam
      // `snake_sim_test.dart`'s `_eatAhead` uses: `recordArcadeResult`
      // stores nothing for a run that never scored, and `bestLength` only
      // rises from a length `SnakeSim` itself measured — not from a body a
      // test sets directly, which is why the crash sequence below leaves
      // this eat's growth in place rather than overwriting it first.
      final head = game.sim.body.first;
      game.sim.debugSetTargets([
        SnakeTarget(
          cell: Cell(head.col + 1, head.row),
          value: game.sim.nextValue,
        ),
      ]);
      game.sim.debugForceMoveNext();
      await tester.pump(const Duration(milliseconds: 16));
      expect(game.sim.score, greaterThan(0), reason: 'the eat above landed');

      // Ends the run by crashing all three of `SnakeRules.normal`'s lives
      // against the wall — real D-pad taps would make this test about
      // navigating there rather than about what a finished run stores.
      for (var life = 0; life < 3; life++) {
        game.sim.debugSetBody([
          Cell(columns - 1, 5),
        ], heading: SnakeDirection.right);
        game.sim.debugForceMoveNext();
        await tester.pump(const Duration(milliseconds: 16));
        if (life < 2) {
          for (var i = 0; i < game.sim.rules.respawnTicks + 8; i++) {
            await tester.pump(const Duration(milliseconds: 16));
          }
        }
      }
      await tester.pump();

      expect(game.isOver.value, isTrue);

      final repository = container.read(progressRepositoryProvider);
      final progress = repository.activeProfile.arcade.games[snakeGameId];
      expect(progress, isNotNull);
      expect(progress!.highScores, isNotEmpty);
      expect(progress.highScores.first.counting, isTrue);
      expect(progress.bestLength, greaterThan(0));

      // The game-over card's own Back button pops without a confirmation —
      // the run already ended and was already recorded — so this leaves the
      // screen without `_quit`'s "Stop playing?" dialog, which only a
      // still-running game shows.
      await repository.flush();
      await tester.tap(find.byTooltip('Back').last);
      await _pumpFrames(tester, 3);
    },
  );
}
