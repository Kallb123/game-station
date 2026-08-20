// The settings screen, driven through the home screen's settings button.
//
// Every test runs over a [MemorySaveStore], so "it survives a relaunch" means
// the value was encoded, written and decoded again by the real codec and the
// real repository rather than kept in a field.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/build_info.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/screen_scaffold.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart';
import 'package:zibo_games/features/settings/settings_screen.dart';

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

  /// Scrolls [label] into view, building it if the list has not yet.
  ///
  /// `ensureVisible` is not enough for anything below the last section: a
  /// `ListView` builds lazily, so a control off the bottom is not in the tree
  /// to be made visible until the list has been dragged towards it.
  Future<void> scrollTo(WidgetTester tester, String label) async {
    await tester.scrollUntilVisible(
      find.text(label),
      AppTapTargets.primary,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Picks when this profile is told about a wrong digit.
  Future<void> chooseMistakeFeedback(
    WidgetTester tester,
    MistakeFeedback choice,
  ) async {
    final label = mistakeFeedbackChoices[choice]!.label;
    await scrollTo(tester, label);
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  /// The active profile, which is what the mistake setting belongs to.
  Profile activeProfile(ProviderContainer container) =>
      container.read(progressRepositoryProvider).activeProfile;

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
    final partway = tester.getTopLeft(find.text(invadersTitle));
    await tester.pumpAndSettle();

    return partway == tester.getTopLeft(find.text(invadersTitle));
  }

  /// Drags the haptics slider to [level], approximating its stop's fraction
  /// along the track — close enough that `Slider.divisions` snaps to the
  /// nearest of the four stops even when the tap lands a few pixels off it.
  Future<void> setHapticsLevel(WidgetTester tester, HapticsLevel level) async {
    final slider = find.byType(Slider);
    await tester.ensureVisible(slider);
    await tester.pumpAndSettle();
    final rect = tester.getRect(slider);
    final fraction =
        HapticsLevel.values.indexOf(level) / (HapticsLevel.values.length - 1);
    final dx = (rect.left + rect.width * fraction).clamp(
      rect.left + 8,
      rect.right - 8,
    );
    await tester.tapAt(Offset(dx, rect.center.dy));
    await tester.pumpAndSettle();
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
    // exactly one of the three carries one — a fresh save follows the device,
    // which makes it Automatic.
    for (final MapEntry(key: choice, value: (:label, icon: _))
        in themeChoices.entries) {
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(label),
            matching: find.byType(FilledButton),
          ),
          matching: find.byIcon(Icons.check_circle),
        ),
        choice == ThemeChoice.system ? findsOneWidget : findsNothing,
        reason: label,
      );
    }
  });

  group('when a wrong number is pointed out', () {
    testWidgets('the choice survives a relaunch', (tester) async {
      final store = MemorySaveStore(initial: freshSave());
      final container = await pumpApp(tester, store: store);
      await openSettings(tester);
      expect(
        activeProfile(container).mistakeFeedback,
        MistakeFeedback.immediate,
        reason: 'the default (`PLAN.md` §3.7)',
      );

      await chooseMistakeFeedback(tester, MistakeFeedback.atCompletion);
      expect(
        activeProfile(container).mistakeFeedback,
        MistakeFeedback.atCompletion,
      );

      await flush(container);
      final relaunched = await pumpApp(tester, store: store);

      expect(
        activeProfile(relaunched).mistakeFeedback,
        MistakeFeedback.atCompletion,
        reason: 'encoded, written and decoded by the real codec',
      );
    });

    testWidgets('it belongs to the player, not to the tablet', (tester) async {
      // The one setting on this screen that is per profile
      // (`save_data.dart`), which is why the control says whose it is.
      final container = await pumpApp(
        tester,
        store: MemorySaveStore(initial: freshSave()),
      );
      final repository = container.read(progressRepositoryProvider);
      final first = repository.activeProfile;
      final second = repository.createProfile(avatar: AvatarId.owl);

      repository.selectProfile(first.id);
      await openSettings(tester);
      await chooseMistakeFeedback(tester, MistakeFeedback.atCompletion);

      repository.selectProfile(second.id);
      await tester.pumpAndSettle();
      await scrollTo(tester, mistakeSectionLabel);

      expect(
        repository.activeProfile.mistakeFeedback,
        MistakeFeedback.immediate,
        reason: 'the other child was not changed with them',
      );
      expect(find.text(mistakeSectionCaption(second.name)), findsOneWidget);
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text(
              mistakeFeedbackChoices[MistakeFeedback.immediate]!.label,
            ),
            matching: find.byType(FilledButton),
          ),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
        reason: 'and the screen shows this profile\'s answer, not the first\'s',
      );
    });
  });

  testWidgets('every switch survives a relaunch', (tester) async {
    const flipped = AppSettings(
      sound: false,
      showTimer: true,
      reduceMotion: true,
      allowPhotoImport: true,
    );

    await runningOn(TargetPlatform.android, () async {
      final store = MemorySaveStore(initial: freshSave());
      final container = await pumpApp(tester, store: store);
      await openSettings(tester);

      for (final label in const [
        soundLabel,
        showTimerLabel,
        reduceMotionLabel,
        allowPhotoImportLabel,
      ]) {
        await scrollTo(tester, label);
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
      expect(switchFor(tester, showTimerLabel).value, isTrue);
      expect(switchFor(tester, reduceMotionLabel).value, isTrue);
      await scrollTo(tester, allowPhotoImportLabel);
      expect(switchFor(tester, allowPhotoImportLabel).value, isTrue);
    });
  });

  testWidgets('the haptics level survives a relaunch', (tester) async {
    await runningOn(TargetPlatform.android, () async {
      final store = MemorySaveStore(initial: freshSave());
      final container = await pumpApp(tester, store: store);
      await openSettings(tester);

      await setHapticsLevel(tester, HapticsLevel.high);

      expect(container.read(settingsProvider).hapticsLevel, HapticsLevel.high);

      await flush(container);
      final relaunched = await pumpApp(tester, store: store);

      expect(relaunched.read(settingsProvider).hapticsLevel, HapticsLevel.high);
      await openSettings(tester);
      expect(find.text(hapticsLevelLabels[HapticsLevel.high]!), findsOneWidget);
    });
  });

  for (final platform in const [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform is offered a buzzing control', (tester) async {
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
    testWidgets('$platform is not offered a buzzing control', (tester) async {
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
      expect(
        tester.getSize(find.byType(Slider)).height,
        greaterThanOrEqualTo(AppTapTargets.min),
        reason: 'the haptics slider is a strip a child drags along',
      );
      // Below the haptics slider in list order, so this one is checked after
      // it rather than in the same pass: scrolling this far pushes the
      // slider out of the `ListView`'s lazily-built range, and a size check
      // against a widget no longer built finds nothing.
      await scrollTo(tester, allowPhotoImportLabel);
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(allowPhotoImportLabel),
                matching: find.byType(SwitchListTile),
              ),
            )
            .height,
        greaterThanOrEqualTo(AppTapTargets.primary),
        reason: '$allowPhotoImportLabel is a row a child aims at',
      );
      for (final choice in [
        ...themeChoices.values,
        ...mistakeFeedbackChoices.values,
      ]) {
        await scrollTo(tester, choice.label);
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

  testWidgets('the footer names the build, under everything else', (
    tester,
  ) async {
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));
    await openSettings(tester);

    // Whatever this build was stamped with — `flutter test` stamps nothing, so
    // here it is the development label. Asserting the string the app would show
    // rather than a literal is what keeps the test honest under a stamped run:
    // `build_info_test.dart` is where the label's own wording is pinned.
    final footer = find.text(BuildInfo.current.label);
    await scrollTo(tester, BuildInfo.current.label);

    expect(footer, findsOneWidget);
    expect(
      tester.getTopLeft(footer).dy,
      greaterThan(tester.getBottomLeft(find.text(mistakeSectionLabel)).dy),
      reason: 'the footer sits below the last setting',
    );
  });

  testWidgets('every control is reachable on a small phone at 200% text scale', (
    tester,
  ) async {
    // Nothing on this screen fits a 360x640 phone at 200%, and it does not have
    // to: it has to scroll without clipping a label or overflowing, which an
    // overflow error here would fail on its own.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        allowPhotoImportLabel,
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
