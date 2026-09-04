// The arcade's second device test (`PLAN-phase-7-snake.md` §6, PR 7).
//
// **CI does not run it**, for the same reason `invaders_smoke_test.dart` says:
// there is no emulator in the workflow, an emulator job is `PLAN.md` §9's open
// question, and `AGENTS.md` says how to run this by hand. What runs on every
// commit is `test/features/arcade/snake/` and `test/features/arcade/`, which
// carry the same criteria over a fake controller and an in-memory store — so
// what is left here is exactly what those have to fake:
//
// - Real pointers on real hardware, and in particular two of them close
//   together: `PadLayout.dPad`'s four buttons sit with their *bounding
//   boxes* overlapping by design (`on_screen_pad.dart`'s own comment on
//   `_dPadReach`), which `ClipOval` is what keeps a tap inside one button's
//   drawn circle from resolving to its neighbour. A widget test's synthetic
//   pointers are the least faithful simulation of the arena there is
//   (`invaders_smoke_test.dart`'s own header); this holds RIGHT and DOWN
//   down together, adjacent corners on the diamond, and checks the raw
//   `Listener`s underneath ClipOval agree with what real touchscreen
//   hit-testing says they should.
// - A real frame clock, the same way `invaders_smoke_test.dart` uses one:
//   the device's own vsync drives `SnakeGame`'s accumulator, which is the
//   only place the 60 Hz and 144 Hz question is answered by a display
//   rather than by `snake_sim_equivalence_test.dart`'s arithmetic.
// - `path_provider` really answers, and the run's score really goes through
//   a file: the directory the platform hands back, a temp file, and a
//   rename.
//
// **Steering to an actual target, not a debug seam.** `SnakeSim` carries
// `debugSetBody`/`debugSetTargets` for exactly the reason `snake_sim_test.dart`
// uses them — reaching a specific board shape through real play would make a
// collision test about navigating there rather than about the rule under
// test — but that reasoning cuts the other way here: this file's whole point
// is that a real finger on the D-pad can steer the snake onto a real target
// and have the resulting score reach `save.json`, the same "real gameplay
// produces the number the save holds" `invaders_smoke_test.dart` proves by
// steering into the gap between two bunkers rather than teleporting there.
//
// The run is played in easy mode — `SnakeRules.easy.wrapWalls` is true — for
// a reason that has nothing to do with `PLAN.md` §9's open question about
// which mode a five-year-old finds playable: `_steerTo` below reaches any
// cell by turning at most twice, in whichever direction is convenient, and
// then simply continuing until the wrap brings the target row or column
// around — never needing to reverse, which `SnakeSim._isReversal` refuses
// and a genuine controller has no business attempting. Normal mode's walls
// would turn the same two-turn plan into a search over which of four
// directions does not end in a crash, which is a pathfinder, not a smoke
// test.
//
// The app going away mid-run is driven the same way
// `invaders_smoke_test.dart` drives it — there is no portable way to make a
// platform actually background an app under `flutter test`. This file was
// not itself run red against a deliberately broken build the way
// `invaders_smoke_test.dart` records having been (§8's checklist says why:
// this session's container cannot get either smoke test past its audio
// dependency) — but the same two bugs that check caught would fail it by
// the same construction: `GameShell` quitting without calling `_record`
// would fail at the read-back from `save.json`, and `OnScreenPad`'s buttons
// sharing one "something is down" flag instead of a pointer id each would
// fail the two-finger assertion below, with the snake having turned only
// once instead of twice.
//
// Nothing here asserts an exact score. The run's seed is the clock
// (`snake_screen.dart`'s own `_seed`) and where its one target lands is
// therefore different every run; what is fixed is that a run which scored is
// the run the save holds, and the scoring rules themselves are frozen by
// `snake_sim_test.dart`.

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
import 'package:zibo_games/features/arcade/shared/game_shell.dart';
import 'package:zibo_games/features/arcade/shared/on_screen_pad.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_sim.dart';
import 'package:zibo_games/features/arcade/snake/snake_game.dart';
import 'package:zibo_games/features/arcade/snake/snake_screen.dart';

/// The directory this test's save lives in, inside the one `path_provider`
/// would resolve. Its own, for the same two reasons
/// `invaders_smoke_test.dart`'s copy gives: a run cannot touch the high
/// scores on the device it runs on, and it starts from a known save however
/// many times it has been run before.
const String smokeSaveDirectory = 'integration_test_arcade_save';

/// The "nothing is being simulated at all" timeout for one leg of the run —
/// steering onto a target, or the field appearing at all — not a measurement
/// of how long either normally takes.
const Duration playTimeout = Duration(seconds: 30);

/// How long the save is given to reach the disk after the run is quit.
const Duration writeTimeout = Duration(seconds: 10);

/// How long the app is left in the background mid-run.
const Duration awaySpan = Duration(seconds: 1);

/// How long the run is watched after *Resume*.
const Duration resumeSpan = Duration(milliseconds: 200);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a run steered onto a target with the D-pad survives the app going away',
    (tester) async {
      final directory = await _saveDirectory();
      await _launch(tester, FileSaveStore(directory));

      final game = await _openSnake(tester);
      expect(
        game.debugStepsDone,
        greaterThan(0),
        reason: 'the accumulator is being fed real frames',
      );

      // Two pointers at once, on two buttons whose bounding boxes overlap by
      // design (`on_screen_pad.dart`'s own `_dPadReach` comment) — the thing
      // only hardware answers. RIGHT goes down first — the heading already
      // is right, so this presses a button without asking for a turn — and
      // DOWN is the second finger, requesting the first of `_steerTo`'s two
      // turns. Both must still read held, which is `ClipOval` keeping each
      // tap inside the circle it landed in rather than the raw `Listener`
      // underneath resolving it to whichever button is later in the stack.
      final target = game.sim.targets.first.cell;
      final right = await _hold(tester, OnScreenPad.rightKey);
      final down = await _hold(tester, OnScreenPad.downKey);
      await _pumpFor(tester, const Duration(milliseconds: 100));
      expect(
        game.input.value.right && game.input.value.down,
        isTrue,
        reason: 'two fingers on adjacent D-pad buttons both stayed held',
      );
      await right.up();
      await down.up();

      // The RIGHT press above queued its own (no-op) turn ahead of DOWN's —
      // heading was already right — so both drain before `_steerTo` may
      // safely queue anything more: `SnakeSim._turnQueue` holds at most two,
      // and a tap issued while it is still full is silently dropped, not
      // queued behind them.
      await _pumpUntil(
        tester,
        () => game.sim.heading == SnakeDirection.down,
        timeout: playTimeout,
        what: 'the queued DOWN turn taking effect',
      );

      // Steer onto the run's one real target and wait for the score it
      // pays out — see the header for why easy mode's wrapping is what
      // makes this a straight-line controller rather than a pathfinder.
      await _steerTo(tester, game, target);
      await _pumpUntil(
        tester,
        () => game.sim.score > 0,
        timeout: playTimeout,
        what: 'the snake reaching its target',
      );
      final scoreAfterEating = game.sim.score;

      // The app going away mid-run. `GameShell` pauses on the way out and
      // does not resume on the way back — a game that started moving the
      // instant a tablet unlocked would drop the player back into a run
      // before they had looked at the screen — so a child sees the paused
      // card and an explicit *Resume* either way.
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

      // Quitting mid-run still stores the run — a run stopped after one
      // target is still a run (`PLAN.md` §4.3). The score is read after the
      // confirmation is up, the same reason `invaders_smoke_test.dart` reads
      // it there: `_confirmQuit` pauses the game to ask, so the numbers
      // cannot move under the assertions below.
      await tester.tap(find.byTooltip('Back').last);
      await _pumpFor(tester, const Duration(milliseconds: 200));
      expect(find.text(quitConfirmTitle), findsOneWidget);

      final score = game.sim.score;
      final level = game.sim.level;
      final length = game.sim.longest;
      expect(
        score,
        greaterThanOrEqualTo(scoreAfterEating),
        reason: 'the score the save gets is at least what eating paid out',
      );

      await tester.tap(find.text(quitStopLabel));
      await tester.pumpAndSettle();

      // The file half, and the assertion no widget test can make: the run
      // comes back out of `save.json` as characters.
      final progress = await _expectSaved(directory, score);
      expect(progress.highScores.single.wave, level);
      expect(
        progress.highScores.single.easy,
        isTrue,
        reason: 'this run was played with easy mode on',
      );
      expect(progress.bestLength, length);
      expect(progress.gamesPlayed, 1);
      expect(progress.totalKills, greaterThan(0));

      // And the same number back on the card the child sees, which is the
      // whole point of storing it (`PLAN-phase-7-snake.md` §4.9).
      expect(
        find.text(
          bestScoreLabel(
            HighScore(score: score, wave: level, easy: true),
            roundLabel: 'Level',
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(longestSnakeLabel(length)), findsOneWidget);
    },
  );
}

/// Where this run's save goes, emptied first so the app starts from a fresh
/// save — the same reasoning `invaders_smoke_test.dart`'s copy gives.
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

/// Home, then the arcade, switches easy mode on, then a Snake run — the way
/// a child reaches one, plus the one toggle this file's header explains.
///
/// The last leg is pumped rather than settled, the same reason
/// `invaders_smoke_test.dart`'s copy gives: `SnakeGame` runs a live ticker
/// from the moment it mounts, so nothing on this screen ever reaches a
/// settled frame.
Future<SnakeGame> _openSnake(WidgetTester tester) async {
  await tester.tap(find.text('Arcade'));
  await tester.pumpAndSettle();
  // Both are below the fold on a short window: the Options section holding
  // Easy mode sits under both game cards, and the Snake card's own Play
  // button can be off the bottom of a small device too.
  await tester.ensureVisible(find.text(easyModeLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(easyModeLabel));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text(playSnakeLabel));
  await tester.pumpAndSettle();
  await tester.tap(find.text(playSnakeLabel));

  final field = find.byType(GameWidget<SnakeGame>);
  await _pumpUntil(
    tester,
    () => field.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 10),
    what: 'the Snake field',
  );
  // Past the page transition and far enough in for the accumulator to have
  // asked for its first steps.
  await _pumpFor(tester, const Duration(milliseconds: 500));
  return tester.widget<GameWidget<SnakeGame>>(field).game!;
}

/// Puts a finger down on one pad button and leaves it there, for the caller
/// to release. Nothing here taps: two of this file's holds overlap in time,
/// which a tap — a press and a release in the same frame — cannot represent.
Future<TestGesture> _hold(WidgetTester tester, Key button) async {
  final gesture = await tester.startGesture(
    tester.getCenter(find.byKey(button)),
  );
  await tester.pump();
  return gesture;
}

/// One tap on [button]: down, a frame, up. What turns the snake — a turn is
/// edge-detected (`snake_sim.dart`'s own comment on why a held button does
/// not queue a second one), so a tap is the whole of what a turn needs.
Future<void> _tap(WidgetTester tester, Key button) async {
  final gesture = await _hold(tester, button);
  await gesture.up();
  await tester.pump();
}

/// Steers [game]'s snake onto [target] in exactly one more turn on top of
/// the DOWN already pressed above, never a reversal.
///
/// Easy mode wraps (`SnakeRules.easy.wrapWalls`), so continuing to move down
/// without touching the pad again cycles the head through every row in
/// [rows] in order — it is guaranteed to land on [target]'s row within
/// [rows] moves, whichever row that is, with no wall to avoid. Only once
/// that has happened does this turn RIGHT: horizontal is always 90 degrees
/// from the vertical heading DOWN left it in, so `SnakeSim._isReversal`
/// never refuses it, and the same wrapping argument then closes the column
/// within [columns] moves regardless of which side of the head [target]
/// sits on.
Future<void> _steerTo(WidgetTester tester, SnakeGame game, Cell target) async {
  await _pumpUntil(
    tester,
    () => game.sim.body.first.row == target.row,
    timeout: playTimeout,
    what: 'the snake\'s row wrapping around to the target\'s row',
  );

  await _tap(tester, OnScreenPad.rightKey);
  await _pumpUntil(
    tester,
    () => game.sim.body.first.col == target.col,
    timeout: playTimeout,
    what: 'the snake\'s column wrapping around to the target\'s column',
  );
}

/// The app going into the background, as the platform does it — the same
/// three-step sequence `invaders_smoke_test.dart`'s copy drives, and for the
/// same reason: `AppLifecycleListener` asserts on one that skips a step.
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

/// Draws frames for [duration], in slices a display can actually produce —
/// the same reasoning `invaders_smoke_test.dart`'s copy gives for not
/// pumping the whole span in one call.
Future<void> _pumpFor(WidgetTester tester, Duration duration) async {
  final frames = duration.inMilliseconds ~/ 16;
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Draws frames until [condition] holds, or fails saying what never
/// happened.
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

/// Waits until `save.json` holds a single Snake high score worth [score],
/// and returns the progress it was read from — a poll rather than a read,
/// for the same debounced-write reason `invaders_smoke_test.dart`'s copy
/// gives.
Future<ArcadeGameProgress> _expectSaved(Directory directory, int score) async {
  final deadline = DateTime.now().add(writeTimeout);

  var progress = _savedProgress(directory);
  while (progress?.highScores.length != 1 ||
      progress?.highScores.single.score != score) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'after ${writeTimeout.inSeconds}s, save.json holds '
        '${progress == null ? 'no Snake progress' : '${progress.highScores.map((s) => s.score).toList()}'} '
        'rather than a single score of $score',
      );
    }
    await _wait(const Duration(milliseconds: 50));
    progress = _savedProgress(directory);
  }
  return progress!;
}

/// The Snake progress `save.json` holds, or null while it holds none.
///
/// Read directly rather than through a [FileSaveStore], which deletes a
/// leftover `save.json.tmp` as it loads — harmless at launch, and a file
/// deleted out from under a write that is still running here.
ArcadeGameProgress? _savedProgress(Directory directory) {
  final file = File('${directory.path}/$saveFileName');
  if (!file.existsSync()) return null;

  // Whole or absent, never half: the store writes a temp file and renames it
  // over this one (`save_store.dart`).
  return decodeSave(
    file.readAsStringSync(),
  ).activeProfile.arcade.games[snakeGameId];
}

/// Waits without drawing — the same reasoning `invaders_smoke_test.dart`'s
/// copy gives: the binding produces no frames while the app is paused.
Future<void> _wait(Duration duration) => Future<void>.delayed(duration);
