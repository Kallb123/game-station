// `/arcade`'s own screen (`PLAN-phase-4.md` §6, PR 7): the Invaders card, the
// three toggles, and the top-five table for whichever mode those toggles
// currently choose.
//
// Pumped on its own rather than through the whole app: nothing here pushes a
// route except the Invaders card's own button, which `invaders_screen_test.dart`
// already drives end to end through the app harness.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart';
import 'package:zibo_games/features/arcade/invaders/invaders_screen.dart';
import 'package:zibo_games/features/arcade/shared/arcade_result.dart';
import 'package:zibo_games/features/arcade/shared/game_shell.dart'
    show noScoresYetMessage;

import '../../app_harness.dart';

/// Pumps the menu on its own, over [store] when given or a fresh save
/// otherwise.
///
/// A blank widget first, as `app_harness.dart`'s `pumpApp` does: pumping the
/// same widget shape twice in one test — the relaunch tests below do exactly
/// that — would otherwise update the old element in place rather than
/// building a fresh tree over the new container.
Future<ProviderContainer> pumpMenu(
  WidgetTester tester, {
  SaveData? save,
  SaveStore? store,
}) async {
  final resolvedStore = store ?? MemorySaveStore(initial: save ?? freshSave());
  final container = ProviderContainer(
    overrides: [
      saveStoreProvider.overrideWithValue(resolvedStore),
      initialSaveProvider.overrideWithValue(await resolvedStore.load()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ArcadeMenuScreen(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

/// Whether the toggle labelled [label] is drawn as chosen.
bool selected(WidgetTester tester, String label) =>
    tester.widget<BigButton>(find.widgetWithText(BigButton, label)).selected;

void main() {
  testWidgets('a fresh profile sees both empty states', (tester) async {
    await pumpMenu(tester, save: freshSave());

    expect(find.text(notPlayedYetMessage), findsOneWidget);
    expect(find.text(noScoresYetMessage), findsOneWidget);
    expect(selected(tester, easyModeLabel), isFalse);
    expect(selected(tester, autoFireLabel), isFalse);
    expect(selected(tester, padSideLabel), isFalse);
  });

  testWidgets('the easy table and the normal table hold different entries', (
    tester,
  ) async {
    const normal = HighScore(score: 900, wave: 4);
    const easy = HighScore(score: 400, wave: 2, easy: true);
    final save = freshSave();
    final profile = save.profiles.single.copyWith(
      arcade: const ArcadeProgress(
        games: {
          invadersGameId: ArcadeGameProgress(highScores: [normal, easy]),
        },
      ),
    );
    final container = await pumpMenu(
      tester,
      save: save.copyWith(profiles: [profile]),
    );

    expect(find.text(bestScoreLabel(normal)), findsOneWidget);
    expect(find.text(scoreRowLabel(1, normal)), findsOneWidget);
    expect(find.text(scoreRowLabel(1, easy)), findsNothing);

    await tester.tap(find.widgetWithText(BigButton, easyModeLabel));
    await tester.pump();

    expect(find.text(bestScoreLabel(easy)), findsOneWidget);
    expect(find.text(scoreRowLabel(1, easy)), findsOneWidget);
    expect(find.text(scoreRowLabel(1, normal)), findsNothing);

    // Flushed rather than left pending: the toggle above scheduled a debounced
    // write, and a test that ends with one still pending fails the binding's
    // own invariant check (`app_test.dart`).
    await container.read(progressRepositoryProvider).flush();
  });

  testWidgets('switching profile changes the scores and the toggles shown', (
    tester,
  ) async {
    const score = HighScore(score: 500, wave: 2, easy: true);
    final save = freshSave();
    final p1 = save.profiles.single.copyWith(
      arcadeEasyMode: true,
      arcade: const ArcadeProgress(
        games: {
          invadersGameId: ArcadeGameProgress(highScores: [score]),
        },
      ),
    );
    final p2 = Profile(
      id: 'p2',
      name: 'Bo',
      avatar: AvatarId.owl,
      createdAt: testClock(),
    );
    final container = await pumpMenu(
      tester,
      save: save.copyWith(profiles: [p1, p2]),
    );

    expect(selected(tester, easyModeLabel), isTrue);
    expect(find.text(bestScoreLabel(score)), findsOneWidget);

    final repository = container.read(progressRepositoryProvider);
    repository.selectProfile('p2');
    // Awaited rather than pumped past: a test that pumped the 500 ms debounce
    // would be testing the timer, not the screen (`app_test.dart`).
    await repository.flush();
    await tester.pump();

    expect(selected(tester, easyModeLabel), isFalse);
    expect(find.text(notPlayedYetMessage), findsOneWidget);
    expect(find.text(noScoresYetMessage), findsOneWidget);
  });

  testWidgets('a toggle survives a relaunch over the same store', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpMenu(tester, store: store);
    expect(selected(tester, autoFireLabel), isFalse);

    await tester.tap(find.widgetWithText(BigButton, autoFireLabel));
    await container.read(progressRepositoryProvider).flush();

    await pumpMenu(tester, store: store);

    expect(selected(tester, autoFireLabel), isTrue);
  });

  testWidgets(
    'the card shows the score recordArcadeResult wrote, after a relaunch',
    (tester) async {
      final store = MemorySaveStore(initial: freshSave());
      final container = await pumpMenu(tester, store: store);

      container
          .read(progressRepositoryProvider)
          .recordArcadeResult(
            invadersGameId,
            const ArcadeResult(score: 1540, wave: 7, kills: 12),
          );
      await container.read(progressRepositoryProvider).flush();

      await pumpMenu(tester, store: store);

      expect(
        find.text(bestScoreLabel(const HighScore(score: 1540, wave: 7))),
        findsOneWidget,
      );
    },
  );
}
