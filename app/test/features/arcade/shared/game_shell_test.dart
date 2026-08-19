// `GameShell`'s own rules (`PLAN-phase-4.md` §4.8, §6 PR 6): the write on
// game over and on quit, a zero-point run storing nothing, pausing on
// backgrounding without silently resuming, and the modal barrier that stops
// a tap reaching the pad behind the paused and game-over cards.
//
// Driven through a fake `ArcadeGameController` rather than `InvadersGame`:
// what is under test here is the shell around a game, not a game, and a fake
// lets a test flip `isOver` and set `result` directly instead of scripting a
// run to its end through the simulation — `invaders_screen_test.dart` is
// where the real `InvadersGame` gets pumped end to end.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/progress_repository.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/arcade/shared/arcade_controller.dart';
import 'package:zibo_games/features/arcade/shared/arcade_result.dart';
import 'package:zibo_games/features/arcade/shared/game_shell.dart';
import 'package:zibo_games/features/arcade/shared/on_screen_pad.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';

const String _gameId = 'invaders';

DateTime _clock() => DateTime.utc(2026, 8, 12, 9);

class _FakeController implements ArcadeGameController {
  @override
  final ValueNotifier<PadInput> input = ValueNotifier(PadInput.none);

  @override
  final ValueNotifier<ArcadeHud> hud = ValueNotifier(const ArcadeHud(score: 0));

  @override
  final ValueNotifier<bool> isOver = ValueNotifier(false);

  @override
  ArcadeResult result = const ArcadeResult(score: 0);

  int pauseCalls = 0;
  int resumeCalls = 0;
  int restartCalls = 0;

  @override
  void pause() => pauseCalls++;

  @override
  void resume() => resumeCalls++;

  @override
  void restart() {
    restartCalls++;
    isOver.value = false;
  }

  @override
  Widget buildView(BuildContext context) =>
      const ColoredBox(key: Key('fakeField'), color: Color(0xFF000000));
}

/// Pushes a [GameShell] over [controller] on top of a launcher screen, so
/// popping it has somewhere real to land — `Navigator.pop` on a lone root
/// route is a no-op, which would hide a `GameShell` that failed to leave.
Future<ProgressRepository> _pumpShell(
  WidgetTester tester,
  _FakeController controller, {
  EdgeInsets padding = EdgeInsets.zero,
}) async {
  final save = SaveData.initial(createdAt: _clock());
  final repository = ProgressRepository(
    MemorySaveStore(initial: save),
    initial: save,
    debounce: Duration.zero,
    now: _clock,
  );
  addTearDown(repository.dispose);

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(padding: padding),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => GameShell(
                    controller: controller,
                    title: 'Invaders',
                    gameId: _gameId,
                    repository: repository,
                    padSide: PadSide.right,
                    haptics: const SilentHaptics(),
                  ),
                ),
              ),
              child: const Text('Play'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Play'));
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('a run driven to game over stores its HighScore and kills', (
    tester,
  ) async {
    final controller = _FakeController();
    final repository = await _pumpShell(tester, controller);

    controller.result = const ArcadeResult(
      score: 540,
      wave: 3,
      kills: 12,
      easy: true,
    );
    controller.isOver.value = true;
    await tester.pump();

    final progress = repository.activeProfile.arcade.games[_gameId]!;
    expect(progress.highScores, [
      isA<HighScore>()
          .having((score) => score.score, 'score', 540)
          .having((score) => score.wave, 'wave', 3)
          .having((score) => score.easy, 'easy', isTrue),
    ]);
    expect(progress.totalKills, 12);
    expect(find.text(gameOverTitle), findsOneWidget);
  });

  testWidgets('quitting mid-run stores the score too', (tester) async {
    final controller = _FakeController();
    final repository = await _pumpShell(tester, controller);

    controller.result = const ArcadeResult(score: 220, wave: 1, kills: 4);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump(); // opens "Stop playing?"
    expect(find.text(quitConfirmTitle), findsOneWidget);

    await tester.tap(find.text(quitStopLabel));
    await tester.pumpAndSettle();

    expect(
      repository.activeProfile.arcade.games[_gameId]!.highScores.single.score,
      220,
    );
    expect(
      find.text('Play'),
      findsOneWidget,
      reason: 'the confirmed quit popped back to the launcher',
    );
  });

  testWidgets(
    'the hardware back gesture asks for confirmation too, through PopScope',
    (tester) async {
      final controller = _FakeController();
      final repository = await _pumpShell(tester, controller);
      controller.result = const ArcadeResult(score: 75);

      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pump();
      expect(
        find.text(quitConfirmTitle),
        findsOneWidget,
        reason: 'GameShell\'s PopScope caught the system back gesture too',
      );

      await tester.tap(find.text(quitStopLabel));
      await tester.pumpAndSettle();
      expect(
        repository.activeProfile.arcade.games[_gameId]!.highScores.single.score,
        75,
      );
    },
  );

  testWidgets('choosing "Keep playing" leaves the run going', (tester) async {
    final controller = _FakeController();
    final repository = await _pumpShell(tester, controller);
    controller.result = const ArcadeResult(score: 100);

    await tester.tap(find.byTooltip('Back'));
    await tester.pump();
    await tester.tap(find.text(quitKeepPlayingLabel));
    await tester.pumpAndSettle();

    expect(find.text('Play'), findsNothing, reason: 'still on the game');
    expect(
      repository.activeProfile.arcade.games[_gameId]!.highScores,
      isEmpty,
      reason: 'nothing was recorded — the run was not quit',
    );
  });

  testWidgets('a zero-point run stores no high score', (tester) async {
    final controller = _FakeController();
    final repository = await _pumpShell(tester, controller);

    controller.result = const ArcadeResult(score: 0, wave: 2);
    controller.isOver.value = true;
    await tester.pump();

    final progress = repository.activeProfile.arcade.games[_gameId]!;
    expect(progress.highScores, isEmpty);
    expect(progress.gamesPlayed, 1, reason: 'the run still started');
  });

  testWidgets(
    'backgrounding pauses the game; foregrounding does not resume it',
    (tester) async {
      final controller = _FakeController();
      await _pumpShell(tester, controller);

      // The steps the platform makes a backgrounding transition in
      // (`sudoku_play_screen_test.dart`'s `_goAway`/`_comeBack`).
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(controller.pauseCalls, 1);
      expect(find.text(pausedTitle), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(
        controller.resumeCalls,
        0,
        reason:
            'coming back to the foreground is not the same as tapping '
            'Resume',
      );
      expect(
        find.text(pausedTitle),
        findsOneWidget,
        reason: 'still paused, exactly where it was left',
      );
    },
  );

  testWidgets('the modal barrier stops a tap reaching the pad', (tester) async {
    final controller = _FakeController();
    await _pumpShell(tester, controller);

    controller.result = const ArcadeResult(score: 10);
    controller.isOver.value = true;
    await tester.pump();

    await tester.tapAt(tester.getCenter(find.byKey(OnScreenPad.fireKey)));
    await tester.pump();

    expect(
      controller.input.value.fire,
      isFalse,
      reason: 'the barrier over the game-over card caught the tap first',
    );
  });

  testWidgets('the field clears a floor at 360x640 with a notch and a '
      'gesture bar', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = _FakeController();
    await _pumpShell(
      tester,
      controller,
      padding: const EdgeInsets.only(top: 44, bottom: 34),
    );

    final field = tester.getSize(find.byKey(const Key('fakeField')));
    // Well below what this geometry actually leaves at 100% scale — a
    // header row, a 72 dp pad and the screen's own padding come out of a
    // 562 dp safe area — but a regression that crushed it to less than this
    // is a field no child could see enough of to play.
    expect(field.height, greaterThanOrEqualTo(200));
  });
}
