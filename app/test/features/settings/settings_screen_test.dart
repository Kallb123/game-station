// The settings screen, driven through the home screen's settings button.
//
// Every test runs over a [MemorySaveStore], so "it survives a relaunch" means
// the value was encoded, written and decoded again by the real codec and the
// real repository rather than kept in a field.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/core/ui/screen_scaffold.dart';
import 'package:game_station/core/ui/tokens.dart';
import 'package:game_station/features/settings/settings_screen.dart';

import '../../app_harness.dart';

void main() {
  /// Home to the settings, through the control a child would use.
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text(soundLabel), findsOneWidget);
  }

  /// Writes everything outstanding, so a second launch over the same store
  /// reads what this one held.
  ///
  /// Awaited rather than pumped past: a test that pumped the 500 ms debounce
  /// would be testing the timer, and a test that left it pending fails on the
  /// binding's own invariant check.
  Future<void> flush(ProviderContainer container) =>
      container.read(progressRepositoryProvider).flush();

  /// The brightness of the screen the child is looking at, rather than of the
  /// theme the app was handed — those are the same thing only if `themeMode` is
  /// wired up, which is what the done-criterion is about.
  Brightness visibleBrightness(WidgetTester tester) =>
      Theme.of(tester.element(find.byType(ScreenScaffold).last)).brightness;

  bool motionReduced(WidgetTester tester) => MediaQuery.disableAnimationsOf(
    tester.element(find.byType(ScreenScaffold).last),
  );

  /// Runs [body] as if the app were on [platform].
  ///
  /// Reset in a `finally` rather than in a tear-down: the framework checks its
  /// "a debug variable was changed by the test" invariant before tear-downs run,
  /// so a tear-down both fails the test and leaks the override into the next one
  /// (`theme_test.dart` does the same).
  Future<void> runningOn(
    TargetPlatform platform,
    Future<void> Function() body,
  ) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Picks a theme, scrolling to it first.
  ///
  /// The five controls are taller than a short window, so the theme buttons can
  /// be below the fold — as they are for a child on a phone, who scrolls to them
  /// the same way.
  Future<void> chooseTheme(WidgetTester tester, ThemeChoice choice) async {
    final label = find.text(themeChoices[choice]!.label);
    await tester.ensureVisible(label);
    await tester.pumpAndSettle();
    await tester.tap(label);
    await tester.pumpAndSettle();
  }

  /// Opens a screen from the home cards and reports whether it was already in
  /// place partway through the transition, rather than still sliding in.
  ///
  /// The arcade card rather than the Sudoku one: what this needs is a screen
  /// with a landmark that is in place the moment the route builds, and phase
  /// 3's Sudoku screens start on a puzzle that is loaded rather than drawn.
  ///
  /// Leaves that screen open: a caller that needs the home screen again pops it.
  Future<bool> arrivesWithoutMoving(WidgetTester tester) async {
    await tester.tap(find.text('Arcade'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final partway = tester.getTopLeft(find.text('Coming soon!'));
    await tester.pumpAndSettle();

    return partway == tester.getTopLeft(find.text('Coming soon!'));
  }

  /// The switch drawn for [label].
  SwitchListTile switchFor(WidgetTester tester, String label) =>
      tester.widget<SwitchListTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(SwitchListTile),
        ),
      );

  testWidgets('night stays night after a relaunch', (tester) async {
    // The PR's done-criterion. It fails on a `MaterialApp` given a `darkTheme`
    // but no `themeMode`, which is what the app had before this change: the
    // stored choice would be written and then ignored.
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpApp(tester, store: store);
    expect(visibleBrightness(tester), Brightness.light);

    await openSettings(tester);
    await chooseTheme(tester, ThemeChoice.night);

    expect(visibleBrightness(tester), Brightness.dark);

    await flush(container);
    await pumpApp(tester, store: store);

    expect(visibleBrightness(tester), Brightness.dark);
  });

  testWidgets('automatic follows the device, both ways', (tester) async {
    // The default, and the reason `system` exists: a tablet already in night
    // mode should not have to be told twice (`save_data.dart`).
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;

    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
    expect(visibleBrightness(tester), Brightness.dark);

    // And an explicit choice wins over the device.
    await openSettings(tester);
    await chooseTheme(tester, ThemeChoice.day);

    expect(visibleBrightness(tester), Brightness.light);
  });

  testWidgets('the chosen theme is the one shown as chosen', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
    await openSettings(tester);

    // Selection is a check icon as well as a colour (`big_button.dart`), so
    // exactly one choice carries one.
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.descendant(
        of: find.ancestor(
          of: find.text(themeChoices[ThemeChoice.system]!.label),
          matching: find.byType(FilledButton),
        ),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
      reason: 'a fresh save follows the device, so Automatic is the chosen one',
    );
  });

  testWidgets('every switch survives a relaunch', (tester) async {
    const flipped = AppSettings(
      sound: false,
      haptics: false,
      showTimer: true,
      reduceMotion: true,
    );

    await runningOn(TargetPlatform.android, () async {
      final store = MemorySaveStore(initial: freshSave());
      final container = await pumpApp(tester, store: store);
      await openSettings(tester);

      for (final label in const [
        soundLabel,
        hapticsLabel,
        showTimerLabel,
        reduceMotionLabel,
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      expect(container.read(settingsProvider), flipped);

      await flush(container);
      final relaunched = await pumpApp(tester, store: store);

      expect(relaunched.read(settingsProvider), flipped);
      // Read back off the screen as well, so a switch drawn from the wrong
      // field fails here rather than in phase 5, when something finally
      // consumes it.
      await openSettings(tester);
      expect(switchFor(tester, soundLabel).value, isFalse);
      expect(switchFor(tester, hapticsLabel).value, isFalse);
      expect(switchFor(tester, showTimerLabel).value, isTrue);
      expect(switchFor(tester, reduceMotionLabel).value, isTrue);
    });
  });

  for (final platform in const [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform can turn buzzing off', (tester) async {
      await runningOn(platform, () async {
        await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
        await openSettings(tester);

        expect(find.text(hapticsLabel), findsOneWidget);
      });
    });
  }

  for (final platform in const [
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
  ]) {
    testWidgets('$platform is not offered a buzzing switch', (tester) async {
      // A control that does nothing on the device in front of you is worse than
      // an absent one (PLAN-phase-1.md §4.5).
      await runningOn(platform, () async {
        await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
        await openSettings(tester);

        expect(find.text(hapticsLabel), findsNothing);
        expect(
          find.text(showTimerLabel),
          findsOneWidget,
          reason: 'the rest of the screen is still there',
        );
      });
    });
  }

  // The or in PLAN-phase-1.md §4.1, one test per half plus neither.
  //
  // Each asserts what the app *does*, not what `MediaQuery` says: the device's
  // own flag is already in the ambient `MediaQuery`, so a test that only read the
  // flag back would pass whether or not the app had looked at it. Opening a
  // screen is the observable, because the slide between screens is the only
  // animation phase 1 has — and the reason the setting does something on the day
  // it ships rather than in phase 4.

  testWidgets('the setting alone reduces motion', (tester) async {
    await pumpApp(
      tester,
      store: MemorySaveStore(
        initial: freshSave(settings: const AppSettings(reduceMotion: true)),
      ),
    );

    expect(await arrivesWithoutMoving(tester), isTrue);
    // Published as well as acted on, so that a phase-4 animation asks
    // `MediaQuery` once and gets both halves (`app.dart`).
    expect(motionReduced(tester), isTrue);
  });

  testWidgets('the device alone reduces motion', (tester) async {
    // A child whose tablet already asks for less motion does not have to find
    // this app's switch as well. Flutter is what honours this half — an
    // `AnimationController` shortens itself when the platform asks — so this
    // test guards the behaviour rather than any code in `app.dart`, and it is
    // here because the child cannot tell the two halves apart.
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);

    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(await arrivesWithoutMoving(tester), isTrue);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await openSettings(tester);
    expect(
      switchFor(tester, reduceMotionLabel).value,
      isFalse,
      reason:
          'the switch shows the half of the decision this screen can change',
    );
  });

  testWidgets('neither leaves motion alone', (tester) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    expect(await arrivesWithoutMoving(tester), isFalse);
    expect(motionReduced(tester), isFalse);
  });

  testWidgets('every control clears the tap-target floor', (tester) async {
    await runningOn(TargetPlatform.android, () async {
      await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
      await openSettings(tester);

      for (final label in const [
        soundLabel,
        hapticsLabel,
        showTimerLabel,
        reduceMotionLabel,
      ]) {
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text(label),
                  matching: find.byType(SwitchListTile),
                ),
              )
              .height,
          greaterThanOrEqualTo(AppTapTargets.primary),
          reason: '$label is a row a child aims at',
        );
      }
      for (final choice in themeChoices.values) {
        expect(
          tester
              .getSize(
                find.ancestor(
                  of: find.text(choice.label),
                  matching: find.byType(FilledButton),
                ),
              )
              .height,
          greaterThanOrEqualTo(AppTapTargets.primary),
        );
      }
      expect(
        tester.getSize(find.byTooltip('Back')).height,
        greaterThanOrEqualTo(AppTapTargets.min),
      );
    });
  });

  testWidgets('every control is reachable on a small phone at 200% text scale', (
    tester,
  ) async {
    // Nothing on this screen fits a 360x640 phone at 200%, and it does not have
    // to: it has to scroll without clipping a label or overflowing, which an
    // overflow error here would fail on its own.
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await runningOn(TargetPlatform.android, () async {
      await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
      await openSettings(tester);

      for (final label in <String>[
        soundLabel,
        hapticsLabel,
        showTimerLabel,
        reduceMotionLabel,
        themeSectionLabel,
        for (final choice in themeChoices.values) choice.label,
      ]) {
        final target = find.text(label);
        // Two steps, because they answer different questions: the first scrolls
        // until the row has been built at all, the second until it is inside the
        // viewport and could be tapped.
        await tester.scrollUntilVisible(target, AppTapTargets.primary);
        await tester.ensureVisible(target);
        await tester.pumpAndSettle();

        expect(target, findsOneWidget, reason: '$label is reachable');
      }
    });
  });
}
