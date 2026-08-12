// The "we started fresh" notice: that it appears exactly when progress was
// lost, that it can be got rid of, and that getting rid of it sticks.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/features/home/home_screen.dart';

import '../../app_harness.dart';

void main() {
  MemorySaveStore recovered(SaveRecovery recovery) =>
      MemorySaveStore(recovery: recovery, now: testClock);

  for (final recovery in [
    SaveRecovery.corrupt,
    SaveRecovery.unsupportedVersion,
  ]) {
    testWidgets('a $recovery load says so, once', (tester) async {
      await pumpApp(tester, store: recovered(recovery));

      expect(find.text(saveNoticeText), findsOneWidget);

      await tester.tap(find.byTooltip('Got it'));
      await tester.pumpAndSettle();
      expect(find.text(saveNoticeText), findsNothing);

      // Leaving the screen and coming back must not bring it back: the state
      // lives in a provider rather than in the screen for exactly this
      // (`providers.dart`).
      await tester.tap(find.text('Sudoku'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text(saveNoticeText), findsNothing);
    });
  }

  testWidgets('a first launch is not told anything was lost', (tester) async {
    // There was nothing to lose. Telling a child their games are gone the
    // first time they open the app would be both frightening and false.
    await pumpApp(tester, store: recovered(SaveRecovery.missing));

    expect(find.text(saveNoticeText), findsNothing);
  });

  testWidgets('a save that read cleanly says nothing', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(find.text(saveNoticeText), findsNothing);
  });

  testWidgets('the notice fits a small phone at 200% text scale', (
    tester,
  ) async {
    // The notice is the longest sentence on the home screen and the only one
    // that pushes the two cards down, so it is where an overflow would show.
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await pumpApp(tester, store: recovered(SaveRecovery.corrupt));

    expect(find.text(saveNoticeText), findsOneWidget);
    expect(find.text('Sudoku'), findsOneWidget);
    expect(find.text('Arcade'), findsOneWidget);
  });
}
