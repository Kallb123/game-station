// The app as a whole: what it boots into, where its routes go, and that it
// writes what it holds when the platform takes it away.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart';
import 'package:zibo_games/features/sudoku/data/providers.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_menu_screen.dart';
import 'package:zibo_games/routes.dart';

import 'app_harness.dart';
import 'features/sudoku/puzzle_fixtures.dart';

void main() {
  testWidgets('the app boots to the home screen', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(find.text('Zibo Games'), findsOneWidget);
    expect(find.text('Sudoku'), findsOneWidget);
    expect(find.text('Arcade'), findsOneWidget);
  });

  // Every card leads somewhere, and every somewhere leads back. A card that
  // opened a screen with no way out would strand a child on it.
  //
  // Stops short of the Invaders card the arcade menu offers: that screen
  // holds a running `GameWidget`, whose Flame ticker never settles, so
  // `invaders_screen_test.dart` drives it with bounded `tester.pump` calls
  // instead of `pumpAndSettle`.
  testWidgets('Arcade opens its screen and comes back', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    await tester.tap(find.text('Arcade'));
    await tester.pumpAndSettle();
    expect(find.text(invadersTitle), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Sudoku'), findsOneWidget);
    expect(find.text('Arcade'), findsOneWidget);
    expect(find.text(invadersTitle), findsNothing);
  });

  testWidgets('Sudoku opens its menu and comes back', (tester) async {
    // The source is a fake because the menu pre-warms today's puzzle the moment
    // it opens (`sudoku_menu_screen.dart`), and the real one would generate a
    // 9x9 on an isolate in a widget test.
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [puzzleSourceProvider.overrideWithValue(FakePuzzleSource())],
    );

    await tester.tap(find.text('Sudoku'));
    await tester.pumpAndSettle();
    expect(find.text(dailyPuzzleTitle), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Arcade'), findsOneWidget);
    expect(find.text(dailyPuzzleTitle), findsNothing);
  });

  testWidgets('the play route without a puzzle to play fails loudly', (
    tester,
  ) async {
    // The one route in the app that takes arguments, so it is the one that can
    // be pushed without them. Same reasoning as the unknown-name case below:
    // only a typo in this repository can do it, so it has to fail in a test run
    // rather than reach a child.
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    expect(
      () => navigator.pushNamed(AppRoutes.sudokuPlay),
      throwsAssertionError,
    );
  });

  testWidgets('the settings button opens the settings route', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('the profile chip opens the profile route', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    await tester.tap(find.text('Playing as Player 1'));
    await tester.pumpAndSettle();

    expect(find.text('Players'), findsOneWidget);
  });

  testWidgets('the home screen has no back control', (tester) async {
    // There is nothing under it to go back to, and a back arrow that does
    // nothing is worse than no arrow (`screen_scaffold.dart`).
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(find.byTooltip('Back'), findsNothing);
  });

  testWidgets('the active profile is the one shown', (tester) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpApp(tester, store: store);
    final repository = container.read(progressRepositoryProvider);

    repository.createProfile(name: 'Bo', avatar: AvatarId.owl);
    // Awaited rather than pumped past: a test that pumped the 500 ms debounce
    // would be testing the timer, and a test that left it pending fails on the
    // binding's own invariant check.
    await repository.flush();
    await tester.pump();

    expect(find.text('Playing as Bo'), findsOneWidget);
    expect((await store.load()).data.activeProfile.name, 'Bo');
  });

  testWidgets('a route name with no screen fails loudly', (tester) async {
    // Only a typo in this repository can produce one — nothing outside the app
    // can name a route — so it has to fail where the typo is, in a test run,
    // rather than reach a child as a grey error page. The release fallback to
    // home sits behind this assert and cannot be reached in a debug test.
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));

    expect(() => navigator.pushNamed('/nope'), throwsAssertionError);
  });

  testWidgets('a pause writes what is still in the debounce window', (
    tester,
  ) async {
    // Without this the last 500 ms of a session — the debounce window — die
    // with the process, which is exactly the settings toggle a child made just
    // before handing the tablet back.
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpApp(tester, store: store);

    container
        .read(progressRepositoryProvider)
        .updateSettings(const AppSettings(sound: false));
    expect(store.writes, 0, reason: 'still inside the debounce window');

    // The full transition the platform makes, because `AppLifecycleListener`
    // asserts on a state change that skips a step.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    expect(store.writes, 1);
    expect((await store.load()).data.settings.sound, isFalse);
  });

  // One test per brightness rather than a loop inside one: `MediaQuery.fromView`
  // does not pick up a change to the dispatcher's test value on a tree that is
  // already built, so a second iteration would keep the first brightness and
  // the assertion would be testing the harness rather than the app.
  for (final brightness in Brightness.values) {
    testWidgets('the app follows $brightness', (tester) async {
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = brightness;

      await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

      // Not just "it did not throw": assert the theme actually followed, so a
      // missing darkTheme would fail here rather than pass silently.
      final context = tester.element(find.text('Zibo Games'));
      expect(Theme.of(context).brightness, brightness);
    });
  }
}
