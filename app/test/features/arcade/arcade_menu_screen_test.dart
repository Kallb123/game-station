// `/arcade`'s own screen (`PLAN-phase-4.md` §6, PR 7; `PLAN-phase-7-snake.md`
// §6, PR 5): the Invaders card, the Snake card, the two arcade-wide toggles,
// and each card's own top-five table for whichever mode its own toggles
// currently choose.
//
// Pumped on its own rather than through the whole app for most tests: nothing
// here pushes a route except a card's own Play button, which
// `invaders_screen_test.dart` and `snake_screen_test.dart` already drive end
// to end through the app harness. The one exception is the test at the
// bottom of this file, which plays a real Snake run and returns to the menu
// to read what it wrote — the done-criterion `PLAN-phase-7-snake.md` §6, PR 5
// names, so it needs the whole app to reach `/arcade/snake` and pop back.

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart';
import 'package:zibo_games/features/arcade/invaders/invaders_screen.dart';
import 'package:zibo_games/features/arcade/shared/arcade_result.dart';
import 'package:zibo_games/features/arcade/shared/game_shell.dart'
    show noScoresYetMessage;
import 'package:zibo_games/features/arcade/snake/model/snake_sim.dart';
import 'package:zibo_games/features/arcade/snake/snake_game.dart';
import 'package:zibo_games/features/arcade/snake/snake_screen.dart';

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

/// Taps the `BigButton` labelled [label], scrolling it into view first.
///
/// Two cards no longer fit an 800x600 test surface, unlike the one card this
/// screen drew before `PLAN-phase-7-snake.md` §4.9 — every toggle below the
/// fold needs `ensureVisible` before a hit test can land on it.
Future<void> tapButton(WidgetTester tester, String label) async {
  final finder = find.widgetWithText(BigButton, label);
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

void main() {
  testWidgets('a fresh profile sees the empty state on both cards', (
    tester,
  ) async {
    await pumpMenu(tester, save: freshSave());

    expect(find.text(notPlayedYetMessage), findsNWidgets(2));
    expect(find.text(noScoresYetMessage), findsNWidgets(2));
    expect(selected(tester, easyModeLabel), isFalse);
    expect(selected(tester, padSideLabel), isFalse);
    expect(selected(tester, autoFireLabel), isFalse);
    // `Profile.snakeCounting` defaults to `ones` (`save_data.dart`), so a
    // fresh profile already has Numbers on and Count in 2s drawn beneath it.
    expect(selected(tester, numbersLabel), isTrue);
    expect(selected(tester, countIn2sLabel), isFalse);
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

    await tapButton(tester, easyModeLabel);
    await tester.pump();

    expect(find.text(bestScoreLabel(easy)), findsOneWidget);
    expect(find.text(scoreRowLabel(1, easy)), findsOneWidget);
    expect(find.text(scoreRowLabel(1, normal)), findsNothing);

    // Flushed rather than left pending: the toggle above scheduled a debounced
    // write, and a test that ends with one still pending fails the binding's
    // own invariant check (`app_test.dart`).
    await container.read(progressRepositoryProvider).flush();
  });

  testWidgets(
    "the Snake card shows its own best score, independent of Invaders'",
    (tester) async {
      const invadersScore = HighScore(score: 900, wave: 4);
      const snakeScore = HighScore(score: 70, wave: 2, counting: true);
      final save = freshSave();
      final profile = save.profiles.single.copyWith(
        arcade: ArcadeProgress(
          games: {
            invadersGameId: const ArcadeGameProgress(
              highScores: [invadersScore],
            ),
            snakeGameId: const ArcadeGameProgress(highScores: [snakeScore]),
          },
        ),
      );
      await pumpMenu(tester, save: save.copyWith(profiles: [profile]));

      expect(find.text(bestScoreLabel(invadersScore)), findsOneWidget);
      expect(
        find.text(bestScoreLabel(snakeScore, roundLabel: 'Level')),
        findsOneWidget,
      );
      expect(find.text(notPlayedYetMessage), findsNothing);
    },
  );

  testWidgets(
    'the Snake card shows the lifetime longest snake and keeps showing it '
    'when the mode changes',
    (tester) async {
      final save = freshSave();
      final profile = save.profiles.single.copyWith(
        arcade: const ArcadeProgress(
          games: {snakeGameId: ArcadeGameProgress(bestLength: 24)},
        ),
      );
      final container = await pumpMenu(
        tester,
        save: save.copyWith(profiles: [profile]),
      );

      expect(find.text(longestSnakeLabel(24)), findsOneWidget);

      // Toggling Numbers off changes which mode the score table reads, but
      // `bestLength` is a lifetime figure — it must not move or disappear.
      await tapButton(tester, numbersLabel);
      await tester.pump();

      expect(find.text(longestSnakeLabel(24)), findsOneWidget);

      await container.read(progressRepositoryProvider).flush();
    },
  );

  testWidgets('toggling Numbers off hides Count in 2s and writes off', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpMenu(tester, store: store);
    expect(selected(tester, numbersLabel), isTrue);
    expect(find.widgetWithText(BigButton, countIn2sLabel), findsOneWidget);

    await tapButton(tester, numbersLabel);
    await tester.pump();

    expect(selected(tester, numbersLabel), isFalse);
    expect(find.widgetWithText(BigButton, countIn2sLabel), findsNothing);

    final repository = container.read(progressRepositoryProvider);
    await repository.flush();
    expect(repository.activeProfile.snakeCounting, SnakeCounting.off);
  });

  testWidgets('toggling Numbers back on writes ones', (tester) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpMenu(tester, store: store);
    final repository = container.read(progressRepositoryProvider);

    // Off, then twos, then back on: back on must land on `ones` regardless of
    // which value was stored before it was switched off
    // (`PLAN-phase-7-snake.md` §4.9).
    await tapButton(tester, numbersLabel);
    await tester.pump();
    await tapButton(tester, numbersLabel);
    await tester.pump();
    expect(selected(tester, numbersLabel), isTrue);
    await tapButton(tester, countIn2sLabel);
    await tester.pump();
    await tapButton(tester, numbersLabel);
    await tester.pump();
    await tapButton(tester, numbersLabel);
    await tester.pump();

    expect(selected(tester, numbersLabel), isTrue);
    expect(selected(tester, countIn2sLabel), isFalse);
    await repository.flush();
    expect(repository.activeProfile.snakeCounting, SnakeCounting.ones);
  });

  testWidgets('Count in 2s moves between ones and twos', (tester) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpMenu(tester, store: store);
    final repository = container.read(progressRepositoryProvider);
    expect(selected(tester, countIn2sLabel), isFalse);

    await tapButton(tester, countIn2sLabel);
    await tester.pump();
    expect(selected(tester, countIn2sLabel), isTrue);
    await repository.flush();
    expect(repository.activeProfile.snakeCounting, SnakeCounting.twos);

    await tapButton(tester, countIn2sLabel);
    await tester.pump();
    expect(selected(tester, countIn2sLabel), isFalse);
    await repository.flush();
    expect(repository.activeProfile.snakeCounting, SnakeCounting.ones);
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
    expect(find.text(notPlayedYetMessage), findsNWidgets(2));
    expect(find.text(noScoresYetMessage), findsNWidgets(2));
  });

  testWidgets('a toggle survives a relaunch over the same store', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await pumpMenu(tester, store: store);
    expect(selected(tester, autoFireLabel), isFalse);

    await tapButton(tester, autoFireLabel);
    await container.read(progressRepositoryProvider).flush();

    await pumpMenu(tester, store: store);

    expect(selected(tester, autoFireLabel), isTrue);
  });

  testWidgets(
    "a relaunch over the same store shows Snake's stored choice too",
    (tester) async {
      final store = MemorySaveStore(initial: freshSave());
      final container = await pumpMenu(tester, store: store);

      await tapButton(tester, countIn2sLabel);
      await container.read(progressRepositoryProvider).flush();

      await pumpMenu(tester, store: store);

      expect(selected(tester, numbersLabel), isTrue);
      expect(selected(tester, countIn2sLabel), isTrue);

      // Nothing left pending, the same reason the toggle test above flushes.
      await container.read(progressRepositoryProvider).flush();
    },
  );

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

  testWidgets(
    'a test plays a snake run, returns to the menu and finds the score on '
    'the Snake card and not on the Invaders one',
    (tester) async {
      final container = await pumpApp(
        tester,
        store: MemorySaveStore(initial: freshSave()),
        overrides: [nowProvider.overrideWithValue(testClock)],
      );

      await tester.tap(find.text('Arcade'));
      await tester.pumpAndSettle();
      await tapButton(tester, playSnakeLabel);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final game = tester
          .widget<GameWidget<SnakeGame>>(find.byType(GameWidget<SnakeGame>))
          .game!;

      // One real eat through the same `debugSetTargets` seam
      // `snake_sim_test.dart` uses, so the run actually scores.
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

      final finishedScore = game.sim.score;
      final finishedLevel = game.sim.level;

      // Ends the run by crashing all three of the normal rules' lives against
      // the wall, exactly as `snake_screen_test.dart`'s own game-over test
      // does — real D-pad taps would make this test about navigating there
      // rather than about what the menu shows afterwards.
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
      await repository.flush();

      // Back to the arcade menu through the game-over card's own Back
      // button, which pops without a confirmation once the run has ended.
      await tester.tap(find.byTooltip('Back').last);
      await tester.pumpAndSettle();

      final snakeBest = HighScore(score: finishedScore, wave: finishedLevel);
      expect(
        find.text(bestScoreLabel(snakeBest, roundLabel: 'Level')),
        findsOneWidget,
      );
      // The Invaders card is still unplayed — its own empty state, and only
      // its own: the Snake card no longer shows one.
      expect(find.text(notPlayedYetMessage), findsOneWidget);
    },
  );
}
