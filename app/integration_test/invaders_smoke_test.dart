// The arcade's device test, and the second file in this repository written to
// run on hardware rather than on the host (`PLAN-phase-4.md` §6, PR 8).
//
// **CI does not run it**, for the same reason `sudoku_smoke_test.dart` says:
// there is no emulator in the workflow, an emulator job is `PLAN.md` §9's open
// question, and `AGENTS.md` says how to run this by hand. What runs on every
// commit is `test/features/arcade/`, which carries the same criteria over a
// fake controller and an in-memory store — so what is left here is exactly
// what those have to fake:
//
// - Real pointers on real hardware. `OnScreenPad`'s buttons are raw
//   `Listener`s specifically so Flutter's gesture arena never gets to award a
//   second finger to whichever button claimed the first
//   (`PLAN-phase-4.md` §1, §4.6), and a widget test's synthetic pointers are
//   the least faithful simulation of the arena there is. Holding FIRE and
//   RIGHT at once here is the check that a cheap tablet's touchscreen agrees.
// - A real frame clock. `InvadersGame`'s accumulator turns wall-clock deltas
//   into fixed steps (`PLAN-phase-4.md` §4.2); every other test feeds it
//   deltas it chose. Here the device's own vsync does, which is the only place
//   the 60 Hz and 144 Hz question is answered by a display rather than by
//   `invaders_sim_equivalence_test.dart`'s arithmetic.
// - `path_provider` really answers, and the run's score really goes through a
//   file: the directory the platform hands back, a temp file, an `fsync` and a
//   rename.
//
// What is *not* more real here is the app going away. There is no portable way
// to make a platform background an app mid-test, so the lifecycle transitions
// are posted to the binding exactly as the widget tests post them. What they
// drive is the difference: the flush in `GameShell._record` runs against a
// filesystem, and the score it lands is read back out of `save.json`.
//
// It was run red before it was trusted (`AGENTS.md`), against two deliberately
// broken builds: one where `GameShell` quits without calling `_record`, which
// fails at the read-back from `save.json`; and one where `OnScreenPad`'s
// buttons share a single "something is down" flag instead of tracking a
// pointer id each — the bug the per-button id exists to prevent — which fails
// at the two-finger assertion, with the ship still at its starting x.
//
// Nothing here asserts an exact score. The run's seed is the clock
// (`PLAN-phase-4.md` §4.3) and its input is however far a held button got the
// ship in the time the frames allowed, so the number is different every run;
// what is fixed is that a run which scored is the run the save holds, and the
// scoring rules themselves are frozen by `invaders_sim_test.dart`.

import 'dart:io';

import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:zibo_games/app.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_codec.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart';
import 'package:zibo_games/features/arcade/invaders/invaders_game.dart';
import 'package:zibo_games/features/arcade/invaders/invaders_screen.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_sim.dart';
import 'package:zibo_games/features/arcade/shared/game_shell.dart';
import 'package:zibo_games/features/arcade/shared/on_screen_pad.dart';

/// The directory this test's save lives in, inside the one the app would use.
///
/// Its own rather than the app's, so a run cannot delete the high scores a
/// child has on the device it is being run on, and so the test starts from a
/// known save however many times it has been run before.
const String smokeSaveDirectory = 'integration_test_arcade_save';

/// How long each of the two waits on the run itself is given: steering the
/// ship back to the middle, and hitting something while FIRE is held.
///
/// The ship starts centred on the gap between the middle two bunkers and the
/// alien block marches over that column continuously, so the first hit is
/// normally within a second or two. This is the "nothing is being simulated at
/// all" timeout, not a measurement of how long either takes.
const Duration playTimeout = Duration(seconds: 30);

/// How long the save is given to reach the disk after the run is quit.
const Duration writeTimeout = Duration(seconds: 10);

/// The x the ship is steered back to before FIRE is held for score: its own
/// starting position, centred on the gap between bunkers two and three, where
/// a shot reaches the aliens instead of eroding a bunker.
const double centredX = (fieldWidth - playerWidth) / 2;

/// How close to [centredX] counts as back in the gap. The gap is 12 field
/// units wide and the shot is 2 wide, so a couple of units of overshoot from
/// the last frame's movement is still clear of both bunkers.
const double centringTolerance = 2;

/// How long two fingers are held down together.
///
/// Long enough for the ship to visibly move at 60 field units a second — about
/// twenty-four units, three ship widths — and short enough that it stays well
/// inside the field.
const Duration twoFingerHold = Duration(milliseconds: 400);

/// How long the app is left in the background mid-run.
const Duration awaySpan = Duration(seconds: 1);

/// How long the run is watched after *Resume*, to see that it started again
/// and that it did not start again by replaying [awaySpan].
const Duration resumeSpan = Duration(milliseconds: 200);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a run played with two fingers survives the app going away', (
    tester,
  ) async {
    final directory = await _saveDirectory();
    await _launch(tester, FileSaveStore(directory));

    final game = await _openInvaders(tester);
    expect(
      game.debugStepsDone,
      greaterThan(0),
      reason: 'the accumulator is being fed real frames',
    );

    // Two pointers at once, which is the thing only hardware answers
    // (`PLAN-phase-4.md` §7): FIRE goes down first, so RIGHT is the second
    // finger — the order that fails if anything upstream of the pad's raw
    // `Listener`s has claimed the gesture.
    final fire = await _hold(tester, OnScreenPad.fireKey);
    final startX = game.sim.player.x;
    final right = await _hold(tester, OnScreenPad.rightKey);
    await _pumpFor(tester, twoFingerHold);
    expect(
      game.sim.player.x,
      greaterThan(startX),
      reason: 'RIGHT moved the ship while FIRE was already held',
    );
    await right.up();

    // Back onto the gap between the middle bunkers, so the shots that follow
    // reach the aliens. Steered rather than teleported: there is no way to
    // place the ship that a child has either.
    final left = await _hold(tester, OnScreenPad.leftKey);
    await _pumpUntil(
      tester,
      () => game.sim.player.x <= centredX + centringTolerance,
      timeout: playTimeout,
      what: 'the ship steering back to the middle',
    );
    await left.up();

    await _pumpUntil(
      tester,
      () => game.sim.score > 0,
      timeout: playTimeout,
      what: 'a hit while FIRE was held',
    );
    await fire.up();
    await _pumpFor(tester, const Duration(milliseconds: 100));

    // The app going away mid-run. `GameShell` pauses on the way out and
    // deliberately does *not* resume on the way back in — a shooter that
    // started moving aliens again the instant a tablet unlocked would drop the
    // player back into the game before they had looked at the screen — so what
    // a child sees on return is the paused card and an explicit *Resume*.
    final stepsBefore = game.debugStepsDone;
    _goAway(tester);
    await _wait(awaySpan);
    expect(
      game.debugStepsDone,
      stepsBefore,
      reason: 'the simulation did not run while the app was away',
    );

    _comeBack(tester);
    await _pumpFor(tester, resumeSpan);
    expect(find.text(pausedTitle), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await _pumpFor(tester, resumeSpan);
    expect(
      game.debugStepsDone,
      greaterThan(stepsBefore),
      reason: 'the run carried on from where it paused',
    );
    // A second away must not become a second of game time owed. Two mechanisms
    // stop it — the accumulator is zeroed on resume (`PLAN-phase-4.md` §4.5),
    // and a frame that asks for more than [maxStepsPerFrame] drops the rest —
    // so this fails only if both are gone. The ceiling is what [awaySpan] is
    // worth in fixed steps rather than a number tuned to how fast [resumeSpan]
    // pumps here, which on a slow device is not the same thing.
    expect(
      game.debugStepsDone - stepsBefore,
      lessThan(awaySpan.inMicroseconds / 1e6 / InvadersSim.fixedStep),
      reason: 'the time spent away was dropped rather than replayed',
    );

    // Quitting mid-run still stores the run — a run stopped at 3,000 points is
    // still a run (`PLAN-phase-4.md` §4.8). The score is read after the
    // confirmation is up rather than before the tap, because `_confirmQuit`
    // pauses the game to ask: from here the numbers cannot move under the
    // assertions below.
    await tester.tap(find.byTooltip('Back').last);
    await _pumpFor(tester, const Duration(milliseconds: 200));
    expect(find.text(quitConfirmTitle), findsOneWidget);

    final score = game.sim.score;
    final wave = game.sim.wave;
    final kills = game.sim.kills;

    await tester.tap(find.text(quitStopLabel));
    await tester.pumpAndSettle();

    // The file half, and the assertion no widget test can make: the run comes
    // back out of `save.json` as characters.
    final progress = await _expectSaved(directory, score);
    expect(progress.highScores.single.wave, wave);
    expect(
      progress.highScores.single.easy,
      isFalse,
      reason: 'a fresh profile plays normal mode',
    );
    expect(progress.gamesPlayed, 1);
    expect(progress.totalKills, kills);

    // And the same number back on the card the child sees, which is the whole
    // point of storing it (`PLAN-phase-4.md` §4.10).
    expect(
      find.text(bestScoreLabel(HighScore(score: score, wave: wave))),
      findsOneWidget,
    );
  });
}

/// Where this run's save goes: a directory of its own inside the one
/// `path_provider` resolves, emptied first so the app starts from a fresh save.
///
/// Resolving it is itself part of the test — it is a plugin call, and a plugin
/// call is one of the things only a device can answer. Run on the host with
/// `-d flutter-tester` instead, no plugin answers and a temp directory stands
/// in; the frame clock, the pointers and the filesystem are all still real
/// there, which is most of what this file is for.
Future<Directory> _saveDirectory() async {
  Directory parent;
  try {
    parent = await getApplicationSupportDirectory();
  } on Exception {
    parent = Directory.systemTemp;
  }

  final directory = Directory('${parent.path}/$smokeSaveDirectory');
  if (directory.existsSync()) directory.deleteSync(recursive: true);
  await directory.create(recursive: true);
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// Starts the app over [store], the way `main.dart` starts it.
Future<void> _launch(WidgetTester tester, SaveStore store) async {
  final loaded = await store.load();
  final root = UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(loaded),
      ],
    ),
    child: const ZiboGamesApp(),
  );
  addTearDown(root.container.dispose);

  await tester.pumpWidget(root);
  await tester.pumpAndSettle();
}

/// Home, then the arcade, then a run — the way a child reaches one.
///
/// The last leg is pumped rather than settled: `InvadersGame` runs a live
/// ticker from the moment it mounts, so nothing on this screen ever reaches a
/// settled frame and `pumpAndSettle` would wait for one forever.
Future<InvadersGame> _openInvaders(WidgetTester tester) async {
  await tester.tap(find.text('Arcade'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(playInvadersLabel));

  final field = find.byType(GameWidget<InvadersGame>);
  await _pumpUntil(
    tester,
    () => field.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
    what: 'the Invaders field',
  );
  // Past the page transition and far enough in for the accumulator to have
  // asked for its first steps.
  await _pumpFor(tester, const Duration(milliseconds: 500));
  return tester.widget<GameWidget<InvadersGame>>(field).game!;
}

/// Puts a finger down on one pad button and leaves it there.
///
/// The caller releases it. Nothing here taps: every one of LEFT, RIGHT and
/// FIRE is a held control, and a tap would exercise a press and a release in
/// the same frame — which is not how any of them is used.
Future<TestGesture> _hold(WidgetTester tester, Key button) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(button)),
  );
  await tester.pump();
  return gesture;
}

/// The app going into the background, as the platform does it.
///
/// Every step of the transition, because `AppLifecycleListener` asserts on one
/// that skips a step — and because `paused` is the last callback Android
/// guarantees before the process can be killed (`app.dart`).
void _goAway(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

/// The app coming back to the foreground.
void _comeBack(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

/// Draws frames for [duration], in slices a display can actually produce.
///
/// A single `pump(duration)` would wait out the whole span and then draw one
/// frame, which is one accumulator update for the lot — the opposite of what a
/// test of the frame loop wants.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final frames = duration.inMilliseconds ~/ 16;
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Draws frames until [condition] holds, or fails saying what never happened.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what did not happen within ${timeout.inSeconds}s');
    }
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Waits until `save.json` holds a single Invaders high score worth [score],
/// and returns the progress it was read from.
///
/// A poll rather than a read, because the write is debounced and then queued
/// behind whatever was already in flight (`progress_repository.dart`): the
/// flush in `GameShell._record` starts it, and this waits for it to land.
Future<ArcadeGameProgress> _expectSaved(Directory directory, int score) async {
  final deadline = DateTime.now().add(writeTimeout);

  var progress = _savedProgress(directory);
  while (progress?.highScores.length != 1 ||
      progress?.highScores.single.score != score) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'after ${writeTimeout.inSeconds}s, save.json holds '
        '${progress == null ? 'no Invaders progress' : '${progress.highScores.map((s) => s.score).toList()}'} '
        'rather than a single score of $score',
      );
    }
    await _wait(const Duration(milliseconds: 50));
    progress = _savedProgress(directory);
  }
  return progress!;
}

/// The Invaders progress `save.json` holds, or null while it holds none.
///
/// The file is read directly rather than through a [FileSaveStore], which
/// deletes a leftover `save.json.tmp` as it loads — harmless at launch, and a
/// file deleted out from under a write that is still running here.
ArcadeGameProgress? _savedProgress(Directory directory) {
  final file = File('${directory.path}/$saveFileName');
  if (!file.existsSync()) return null;

  // Whole or absent, never half: the store writes a temp file and renames it
  // over this one (`save_store.dart`).
  return decodeSave(
    file.readAsStringSync(),
  ).activeProfile.arcade.games[invadersGameId];
}

/// Waits without drawing.
///
/// The binding produces no frames while the app is paused, so a `pump` there
/// would wait for one that is never coming. This test runs on a live binding,
/// where a delay is a real one.
Future<void> _wait(Duration duration) => Future<void>.delayed(duration);
