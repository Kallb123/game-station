// `/arcade/invaders` end to end (`PLAN-phase-4.md` §6, PR 4 and PR 5):
// reachable from the temporary button on `/arcade`, driven by the keyboard
// mirror and `OnScreenPad`.
//
// Every test here uses bounded `tester.pump` calls rather than
// `tester.pumpAndSettle`: `InvadersGame` runs a live Flame ticker once
// mounted, which never reaches a settled frame, so `pumpAndSettle` would hang
// forever.

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/arcade/invaders/invaders_game.dart';
import 'package:zibo_games/features/arcade/shared/on_screen_pad.dart';

import '../../../app_harness.dart';

/// Pumps [count] frames at roughly 60 Hz — never `pumpAndSettle`, which
/// would wait forever on `InvadersGame`'s live Flame ticker.
Future<void> _pumpFrames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Leaves the game through `GameShell`'s quit confirmation
/// (`game_shell_test.dart` covers the confirmation itself; this is just what
/// a test that only wants to tidy up before ending needs).
Future<void> _quit(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Back').last);
  await tester.pump(); // opens "Stop playing?"
  await tester.tap(find.text('Stop'));
  await _pumpFrames(tester, 5);
}

void main() {
  testWidgets('opening Invaders renders a playable field', (tester) async {
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [nowProvider.overrideWithValue(testClock)],
    );

    await tester.tap(find.text('Arcade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play Invaders (dev build)'));
    await _pumpFrames(tester, 20); // past the page transition, several frames

    expect(find.byType(GameWidget<InvadersGame>), findsOneWidget);
    final game = tester
        .widget<GameWidget<InvadersGame>>(find.byType(GameWidget<InvadersGame>))
        .game!;
    // The sim has advanced: proof the accumulator is actually being fed real
    // frames through the widget, not just that nothing threw.
    expect(game.debugStepsDone, greaterThan(0));

    // Leaves the screen instead of letting the test end mid-run, so the
    // game's ticker is disposed along with the route rather than outliving
    // the test.
    await _quit(tester);
  });

  testWidgets('holding the right arrow moves the player right', (tester) async {
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [nowProvider.overrideWithValue(testClock)],
    );

    await tester.tap(find.text('Arcade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play Invaders (dev build)'));
    await _pumpFrames(tester, 5);

    final game = tester
        .widget<GameWidget<InvadersGame>>(find.byType(GameWidget<InvadersGame>))
        .game!;
    final startX = game.sim.player.x;
    final stepsBefore = game.debugStepsDone;

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await _pumpFrames(tester, 30);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await _pumpFrames(tester, 2);

    expect(game.debugStepsDone, greaterThan(stepsBefore));
    expect(game.sim.player.x, greaterThan(startX));

    await _quit(tester);
  });

  testWidgets(
    'a key event hides the pad, a touch on the field brings it back',
    (tester) async {
      await pumpApp(
        tester,
        store: MemorySaveStore(initial: freshSave()),
        overrides: [nowProvider.overrideWithValue(testClock)],
      );

      await tester.tap(find.text('Arcade'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play Invaders (dev build)'));
      await _pumpFrames(tester, 5);

      expect(find.byType(OnScreenPad), findsOneWidget);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await _pumpFrames(tester, 1);
      expect(
        find.byType(OnScreenPad),
        findsNothing,
        reason: 'a keyboard player has no use for the pad',
      );

      await tester.tapAt(
        tester.getCenter(find.byType(GameWidget<InvadersGame>)),
      );
      await _pumpFrames(tester, 1);
      expect(
        find.byType(OnScreenPad),
        findsOneWidget,
        reason: 'a touch means the pad is back in use',
      );

      await _quit(tester);
    },
  );

  testWidgets('the screen fits at 200% text scale with no overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [nowProvider.overrideWithValue(testClock)],
    );

    await tester.tap(find.text('Arcade'));
    await tester.pumpAndSettle();
    // The button can sit below the fold at this scale on this surface — the
    // placeholder screen's own reason for being a `SingleChildScrollView`
    // (`app.dart`).
    await tester.ensureVisible(find.text('Play Invaders (dev build)'));
    await tester.tap(find.text('Play Invaders (dev build)'));
    await _pumpFrames(tester, 5);

    expect(find.byType(GameWidget<InvadersGame>), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _quit(tester);
  });
}
