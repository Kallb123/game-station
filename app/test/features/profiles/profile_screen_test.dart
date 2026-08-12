// The profile picker, driven the way a child drives it: through the home
// screen's chip, the buttons on the picker, and the dialogs behind them.
//
// Every test runs over a [MemorySaveStore], so the real codec and the real
// repository are in the loop and "it survives a relaunch" means the state was
// actually encoded, written and decoded again.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/progress_repository.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/core/ui/avatars.dart';
import 'package:game_station/core/ui/tokens.dart';
import 'package:game_station/features/profiles/profile_screen.dart';

import '../../app_harness.dart';

void main() {
  /// Two players, so that everything the last profile is not allowed to do is
  /// reachable.
  SaveData twoPlayers({String active = 'p1'}) => SaveData(
    activeProfileId: active,
    profiles: [
      Profile(
        id: 'p1',
        name: 'Bo',
        avatar: AvatarId.fox,
        createdAt: testClock(),
      ),
      Profile(
        id: 'p2',
        name: 'Ada',
        avatar: AvatarId.owl,
        createdAt: testClock(),
      ),
    ],
  );

  /// Home to the picker, through the control a child would use.
  Future<void> openPlayers(WidgetTester tester) async {
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    expect(find.text('Players'), findsOneWidget);
  }

  /// Writes everything outstanding, so a second launch over the same store
  /// reads what this one held.
  ///
  /// Awaited rather than pumped past: a test that pumped the 500 ms debounce
  /// would be testing the timer, and a test that left it pending fails on the
  /// binding's own invariant check.
  Future<void> flush(ProviderContainer container) =>
      container.read(progressRepositoryProvider).flush();

  testWidgets('a new player is the one playing, and still is next launch', (
    tester,
  ) async {
    // The PR's done-criterion: create, then relaunch over the same store and
    // find the new player still active.
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpApp(tester, store: store);

    await openPlayers(tester);
    await tester.tap(find.text(addProfileLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Creating a player makes them the one playing, and hands the child back
    // the home screen rather than leaving them on the picker.
    expect(find.text('Playing as Ada'), findsOneWidget);

    await flush(container);
    await pumpApp(tester, store: store);

    expect(find.text('Playing as Ada'), findsOneWidget);
  });

  testWidgets('a player created without a name still gets one', (tester) async {
    // A child who taps *Create* with an empty field gets a profile, not a
    // validation error (`progress_repository.dart`).
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
    );

    await openPlayers(tester);
    await tester.tap(find.text(addProfileLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Playing as Player 2'), findsOneWidget);
    await flush(container);
  });

  testWidgets('a name too long for the button is cut, not refused', (
    tester,
  ) async {
    // Both halves of the cap: the field stops accepting text at
    // [maxProfileNameLength], and the repository trims whatever arrives. A
    // child typing happily past the limit gets a shorter name, never an error.
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
    );

    await openPlayers(tester);
    await tester.tap(find.text(addProfileLabel));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bartholomew the Third');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final name = container.read(progressRepositoryProvider).activeProfile.name;
    expect(name.runes.length, lessThanOrEqualTo(maxProfileNameLength));
    expect('Bartholomew the Third', startsWith(name));
    await flush(container);
  });

  testWidgets('a new player does not look like the one before', (tester) async {
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
    );

    await openPlayers(tester);
    await tester.tap(find.text(addProfileLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final profiles = container.read(progressRepositoryProvider).profiles;
    expect(profiles.last.avatar, isNot(profiles.first.avatar));
    await flush(container);
  });

  testWidgets('picking a player switches to them, and it sticks', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: twoPlayers());
    final container = await pumpApp(tester, store: store);
    expect(find.text('Playing as Bo'), findsOneWidget);

    await openPlayers(tester);
    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();

    expect(find.text('Playing as Ada'), findsOneWidget);

    await flush(container);
    await pumpApp(tester, store: store);

    expect(find.text('Playing as Ada'), findsOneWidget);
  });

  testWidgets('a player can be renamed and given another picture', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: twoPlayers());
    final container = await pumpApp(tester, store: store);

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Bo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Bobbie');
    await tester.tap(find.byTooltip(avatarLabel(AvatarId.panda)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Bobbie'), findsOneWidget);
    expect(find.byIcon(avatarIcon(AvatarId.panda)), findsWidgets);

    await flush(container);
    final reloaded = (await store.load()).data.profiles.first;
    expect(reloaded.name, 'Bobbie');
    expect(reloaded.avatar, AvatarId.panda);
  });

  testWidgets('a change that is cancelled changes nothing', (tester) async {
    final store = MemorySaveStore(initial: twoPlayers());
    final container = await pumpApp(tester, store: store);

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Bo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nope');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Bo'), findsOneWidget);
    expect(find.text('Nope'), findsNothing);
    expect(
      container.read(progressRepositoryProvider).isSaving,
      isFalse,
      reason: 'nothing changed, so nothing is waiting to be written',
    );
  });

  testWidgets('deleting the player who is playing hands over to another', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: twoPlayers(active: 'p2'));
    final container = await pumpApp(tester, store: store);
    expect(find.text('Playing as Ada'), findsOneWidget);

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Ada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    // Asked again, by name, before any games go.
    expect(find.text('Delete Ada?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsNothing);
    expect(container.read(progressRepositoryProvider).activeProfile.name, 'Bo');

    await flush(container);
    expect((await store.load()).data.profiles, hasLength(1));
  });

  testWidgets('a delete that is not confirmed keeps the player', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: twoPlayers());
    final container = await pumpApp(tester, store: store);

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Ada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    expect(container.read(progressRepositoryProvider).profiles, hasLength(2));
    expect(store.writes, 0);
  });

  testWidgets('keeping the player is the emphasised way out of a delete', (
    tester,
  ) async {
    // The child who taps the obvious button loses nothing. Deleting is the one
    // action in the app that cannot be undone, so it is the quiet one.
    await pumpApp(tester, store: MemorySaveStore(initial: twoPlayers()));

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Ada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Keep'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.text('Delete'),
      ),
      findsNothing,
    );
  });

  testWidgets('the chosen picture reaches a screen reader', (tester) async {
    // On the button's own node rather than a second one beside it, the way
    // `BigButton` does it — otherwise a screen reader reads the selection out
    // separately from the control it belongs to.
    await pumpApp(tester, store: MemorySaveStore(initial: twoPlayers()));

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Bo'));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.byTooltip(avatarLabel(AvatarId.fox))),
      isSemantics(isButton: true, isSelected: true),
    );
    expect(
      tester.getSemantics(find.byTooltip(avatarLabel(AvatarId.panda))),
      isSemantics(isButton: true, isSelected: false),
    );
  });

  testWidgets('the last player has no delete control', (tester) async {
    // The repository refuses it as well (`progress_repository.dart`); the
    // control is hidden so that a child never taps something that says no.
    await pumpApp(tester, store: MemorySaveStore(initial: freshSave()));

    await openPlayers(tester);
    await tester.tap(find.byTooltip('Change Player 1'));
    await tester.pumpAndSettle();

    expect(find.text('Save'), findsOneWidget, reason: 'the editor is open');
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('every control on the picker clears the tap-target floor', (
    tester,
  ) async {
    await pumpApp(tester, store: MemorySaveStore(initial: twoPlayers()));
    await openPlayers(tester);

    for (final label in const ['Bo', 'Ada', addProfileLabel]) {
      expect(
        tester
            .getSize(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(FilledButton),
              ),
            )
            .height,
        greaterThanOrEqualTo(AppTapTargets.primary),
        reason: '$label is a primary action',
      );
    }
    for (final tooltip in const ['Change Bo', 'Change Ada', 'Back']) {
      expect(
        tester.getSize(find.byTooltip(tooltip)).height,
        greaterThanOrEqualTo(AppTapTargets.min),
      );
    }
  });

  testWidgets('the picker and its editor fit a small phone at 200% text scale', (
    tester,
  ) async {
    // The editor is the tightest layout in the app: a field, eight pictures and
    // three actions inside a dialog that cannot grow past the screen. An
    // overflow anywhere here fails the test on its own.
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await pumpApp(tester, store: MemorySaveStore(initial: twoPlayers()));
    await openPlayers(tester);
    expect(find.text('Bo'), findsOneWidget);

    await tester.tap(find.byTooltip('Change Bo'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });
}
