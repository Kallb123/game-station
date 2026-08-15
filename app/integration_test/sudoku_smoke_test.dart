// The one test in this repository written to run on a device, and the only
// place a puzzle is generated on a real isolate and a board is read back out of
// a real file.
//
// **CI does not run it** (`PLAN-phase-3.md` §7). There is no emulator in the
// workflow, and adding one is `PLAN.md` §9's open question; `AGENTS.md` says how
// to run this by hand. The check that runs on every commit is
// `test/features/sudoku/resume_test.dart`, which carries the same criterion over
// a fake source and an in-memory store — so what is left here is exactly what
// that one has to fake:
//
// - `compute` really spawns an isolate, and `generateSudoku` really runs in it.
//   A 9x9 Medium rather than the 6x6 the widget test uses, because the tail of
//   a real generation is what the spinner exists for (`PLAN.md` §3.5).
// - `path_provider` really answers, and the save really goes through a file:
//   the directory the platform hands back, a temp file, an `fsync` and a rename.
//
// What is *not* more real here is the app going away. There is no portable way
// to make a platform background an app mid-test, so the lifecycle transitions
// are posted to the binding exactly as the widget test posts them. What they
// drive is the difference: the flush in `app.dart` runs against a filesystem,
// and the board it lands is read back as characters.
//
// The board assertions are deliberately thin. The encoding is frozen by
// `session_codec_test.dart` and the resume path is asserted cell by cell in
// `resume_test.dart`; repeating either here would put a test that nothing runs
// in front of one that everything runs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/app.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_codec.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/features/sudoku/data/puzzle_record.dart';
import 'package:game_station/features/sudoku/model/sudoku_session.dart';
import 'package:game_station/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:game_station/features/sudoku/ui/sudoku_menu_screen.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

/// The puzzle this test plays.
///
/// Medium rather than Easy because Easy is a millisecond and proves nothing
/// about generation being off the raster thread, and rather than Hard because
/// the tail of a Hard is half a second on a desktop and several times that on a
/// cheap tablet (`PLAN.md` §3.5) — long enough to make the test's own timeout
/// the thing being measured.
const SudokuSpec smokeSpec = SudokuSpec.s9x9;

/// See [smokeSpec].
const Difficulty smokeDifficulty = Difficulty.medium;

/// The directory this test's save lives in, inside the one the app would use.
///
/// Its own rather than the app's, so a run cannot delete progress a child has
/// on the device it is being run on, and so the test starts from a known save
/// however many times it has been run before.
const String smokeSaveDirectory = 'integration_test_save';

/// How long a real generation is given before the test calls it a failure.
///
/// Far past the §3.5 tail: what this catches is a generation that never
/// finished — an isolate that failed to spawn on a platform, which is the
/// failure this file exists to find — not one that was slow.
const Duration generationTimeout = Duration(seconds: 30);

/// How long the save is given to reach the disk after the app is backgrounded.
const Duration writeTimeout = Duration(seconds: 10);

/// How long the clock is watched, on each side of the app going away.
///
/// Two ticks rather than one: a single tick is also what a clock that ticked
/// once and stopped would produce.
const Duration clockWindow = Duration(milliseconds: 2500);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real puzzle survives the app going away and coming back', (
    tester,
  ) async {
    final directory = await _saveDirectory();
    final container = await _launch(tester, FileSaveStore(directory));

    final session = await _openARealPuzzle(tester);
    expect(session.id.spec, smokeSpec);
    expect(session.id.difficulty, smokeDifficulty);

    // The generated puzzle went into the save's cache on its way to the screen
    // (`PLAN-phase-3.md` §4.1), which is also where the solution is: the
    // session does not hand it out, and a test that guessed digits would enter
    // mistakes it then had to correct.
    final record = _cachedRecord(container, session.id);
    await _enterThreeDigits(tester, session, record);
    expect(
      session.mistakes,
      0,
      reason: 'the digits entered were the solution’s',
    );

    // The clock, before and after. It stops while the app is away and starts
    // again when it comes back (`sudoku_play_screen.dart`), and a puzzle that
    // counted the minutes a tablet spent in a bag would hand out a best time
    // nobody played for.
    await tester.pump(clockWindow);
    final playedFor = session.elapsed;
    expect(playedFor, greaterThan(Duration.zero), reason: 'the clock started');

    final played = session.toSaved();
    _goAway(tester);
    await _wait(clockWindow);
    expect(session.elapsed, playedFor, reason: 'the clock stopped');

    _comeBack(tester);
    await tester.pump();

    // Back on the same board — same session, same digits, nothing reloaded and
    // nothing reset. A foreground that rebuilt the screen would fail here
    // rather than in the file below.
    expect(_boardOf(tester), same(session));
    for (final cell in _firstEmptyCells(session, 3)) {
      expect(
        session.digitAt(cell),
        int.parse(record.solution[cell]),
        reason: 'cell $cell',
      );
    }

    // The file half, and the assertion the widget test cannot make at all: the
    // board comes back out of `save.json` as characters. It is also what makes
    // the backgrounding load-bearing rather than ceremony — the digits were
    // written as they were entered, but the seconds on the clock are only in
    // memory until something leaves the screen or the app
    // (`PLAN-phase-3.md` §4.8), so a `paused` that did not reach the flush in
    // `app.dart` fails here.
    //
    // Checked once the app is back rather than while it is away, which is not
    // where it reads best: the binding draws no frames while the app is paused,
    // so a failure there would be raised into a tree that cannot be taken down
    // and the run would hang instead of reporting. Nothing writes on the way
    // back — resuming only starts the clock — so the file still holds what the
    // pause put in it.
    await _expectSaved(directory, session.id, played);

    await tester.pump(clockWindow);
    expect(
      session.elapsed,
      greaterThan(playedFor),
      reason: 'the clock started again',
    );
  });
}

/// Where this run's save goes: a directory of its own inside the one
/// `path_provider` resolves, emptied first so the app starts from a fresh save.
///
/// Resolving it is itself part of the test — it is a plugin call, and a plugin
/// call is one of the things only a device can answer. Run on the host with
/// `flutter test` instead, no plugin answers and a temp directory stands in;
/// the isolate, the codec and the filesystem are all still real there, which is
/// most of what this file is for.
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
///
/// The composition is `main`'s: the store is read before the first frame and
/// both it and what it loaded are handed to the scope, so every screen reads a
/// synchronous save. Only where the directory is differs, and [_saveDirectory]
/// says why.
Future<ProviderContainer> _launch(WidgetTester tester, SaveStore store) async {
  final loaded = await store.load();
  final root = UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(loaded),
      ],
    ),
    child: const GameStationApp(),
  );
  addTearDown(root.container.dispose);

  await tester.pumpWidget(root);
  await tester.pumpAndSettle();
  return root.container;
}

/// Home, then the menu, then a puzzle that has to be generated before it can be
/// drawn — the way a child reaches one.
///
/// Nothing here is overridden, so the tap on the difficulty row is followed by
/// a real `compute` on a real isolate. The wait is a poll rather than a
/// `pumpAndSettle`: settling stops when no frame is scheduled, and a screen
/// waiting on an isolate schedules none.
Future<SudokuSession> _openARealPuzzle(WidgetTester tester) async {
  await tester.tap(find.text(sudokuMenuTitle));
  await tester.pumpAndSettle();
  // Tapped even though a fresh save opens on it already: the toggle is what a
  // child picking this size presses, and a default that moves later should
  // break this test rather than quietly change what it plays.
  await tester.tap(find.text(smokeSpec.label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(difficultyChoices[smokeDifficulty]!.label));

  await _pumpUntil(
    tester,
    find.byType(SudokuGridView),
    timeout: generationTimeout,
    what:
        'a generated ${smokeSpec.label} '
        '${difficultyChoices[smokeDifficulty]!.label} board',
  );
  return _boardOf(tester);
}

/// The record the app cached on its way to drawing [id].
///
/// Read from the repository rather than generated a second time here: a second
/// generation would be a second answer to a question the id is supposed to have
/// only one of, and asserting the cache was written is worth having anyway.
PuzzleRecord _cachedRecord(ProviderContainer container, PuzzleId id) {
  final encoded = container
      .read(progressRepositoryProvider)
      .data
      .puzzleCache[id.value];
  expect(encoded, isNotNull, reason: 'the generated puzzle was cached');
  return PuzzleRecord.decode(id.spec, encoded!);
}

/// Fills the first three empty cells with the digits that belong in them, by
/// tapping a cell and then a keypad button.
///
/// Three rather than the whole board: a 9x9 Medium leaves about fifty cells
/// empty, and driving each one through a real frame pipeline would buy nothing
/// the sixth-through-fiftieth digit does not already say. Three is enough for
/// the board on disk to differ from the one the puzzle started as.
Future<void> _enterThreeDigits(
  WidgetTester tester,
  SudokuSession session,
  PuzzleRecord record,
) async {
  for (final cell in _firstEmptyCells(session, 3)) {
    // By key rather than by position in the tree: the grid keys every cell with
    // its index (`sudoku_grid_view.dart`).
    await tester.tap(find.byKey(ValueKey<int>(cell)));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, record.solution[cell]));
    await tester.pump();
  }
}

/// The lowest [count] cell indices [session] has no clue in.
List<int> _firstEmptyCells(SudokuSession session, int count) => [
  for (var index = 0; index < session.spec.cells; index++)
    if (!session.isGiven(index)) index,
].take(count).toList();

/// Waits until `save.json` holds [expected] for [id].
///
/// A poll rather than a read, because the write is debounced and then queued
/// behind whatever was already in flight (`progress_repository.dart`): the
/// flush on `paused` starts it, and this waits for it to land.
///
/// It waits for the board to *match* rather than for one to exist, which is not
/// pedantry: the digits are written as they are entered, so a read taken a
/// moment too early finds the board that was there before the app went away and
/// passes an assertion the pause had nothing to do with.
Future<void> _expectSaved(
  Directory directory,
  PuzzleId id,
  PuzzleInProgress expected,
) async {
  final deadline = DateTime.now().add(writeTimeout);

  var saved = _savedBoard(directory, id);
  while (saved != expected) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'after ${writeTimeout.inSeconds}s, save.json holds '
        '${saved == null ? 'no board' : '${saved.grid} at ${saved.elapsedMs} ms'} '
        'for ${id.value} rather than ${expected.grid} at '
        '${expected.elapsedMs} ms',
      );
    }
    await _wait(const Duration(milliseconds: 50));
    saved = _savedBoard(directory, id);
  }
}

/// The board `save.json` holds for [id], or null while it holds none.
///
/// The file is read directly rather than through a [FileSaveStore], which
/// deletes a leftover `save.json.tmp` as it loads — harmless at launch, and a
/// file deleted out from under a write that is still running here.
PuzzleInProgress? _savedBoard(Directory directory, PuzzleId id) {
  final file = File('${directory.path}/$saveFileName');
  if (!file.existsSync()) return null;

  // Whole or absent, never half: the store writes a temp file and renames it
  // over this one (`save_store.dart`).
  return decodeSave(
    file.readAsStringSync(),
  ).activeProfile.sudoku.inProgress[id.value];
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

/// Pumps until [finder] matches something, or fails saying what never arrived.
Future<void> _pumpUntil(
  WidgetTester tester,
  Finder finder, {
  required Duration timeout,
  required String what,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (finder.evaluate().isEmpty) {
    if (DateTime.now().isAfter(deadline)) {
      fail('$what did not appear within ${timeout.inSeconds}s');
    }
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Waits without drawing.
///
/// The binding produces no frames while the app is paused, so a `pump` there
/// returns without any time having passed — which would turn both the wait for
/// the write and the check that the clock stopped into assertions about
/// nothing. This test runs on a live binding, where a delay is a real one.
Future<void> _wait(Duration duration) => Future<void>.delayed(duration);

SudokuSession _boardOf(WidgetTester tester) =>
    tester.widget<SudokuGridView>(find.byType(SudokuGridView)).session;
