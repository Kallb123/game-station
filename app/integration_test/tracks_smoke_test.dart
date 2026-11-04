// The Puzzles menu's second device test (`PLAN-phase-9-tracks.md` §6, PR 10): a
// real Tracks puzzle, reached from the home screen and drawn to solved with a
// finger, and the solve read back out of a real file.
//
// **CI does not run it**, for the reason `sudoku_smoke_test.dart` gives: there
// is no emulator in the workflow, an emulator job is `PLAN.md` §9's open
// question, and `AGENTS.md` says how to run this by hand. What runs on every
// commit is `test/features/tracks/`, which carries the same criteria over a
// fixture puzzle source and an in-memory store — so what is left here is exactly
// what those have to fake:
//
// - `compute` really spawns an isolate, and `generateTracks` really runs in it.
//   `TracksPuzzleSource` is the only caller (`generation_call_site_test.dart`),
//   and the widget tests replace it, so this is the one place the real source
//   is on the path.
// - A drag across a board laid out at the device's own size and pixel ratio.
//   `PLAN-phase-9-tracks.md` §7 lists "drags at 32 dp cells on a small phone
//   lay the wrong connection" as a medium risk. The pointer is still synthetic,
//   even on a device, but the stroke below walks the whole solution through the
//   same `GestureDetector`, pan slop and position arithmetic a child's finger
//   reaches, on the real screen rather than a widget test's chosen surface.
//   What this file cannot say is whether 32 dp is big enough for a finger: the
//   §8 device line about cell size is answered by a person holding a phone.
// - `path_provider` really answers, and the solve really goes through a file:
//   the directory the platform hands back, a temp file, an `fsync` and a rename.
//
// The solution the stroke follows is the one the real source cached on its way
// to the screen, read from the save's `puzzleCache` — the same reasoning
// `sudoku_smoke_test.dart` gives for not generating a second time here: a
// second generation would be a second answer to a question the id is supposed
// to have only one of. A test that guessed the route would draw mistakes it then
// had to take back.
//
// What is *not* more real here is the app going away. There is no portable way
// to make a platform background an app mid-test, so the lifecycle transitions
// are posted to the binding exactly as the other smoke tests post them. The solve
// is recorded the moment the board is solved rather than when the journey ends
// (`PLAN-phase-9-tracks.md` §6, PR 7 note 3), so this does not depend on the
// background to *get* a write; what the pause drives is the flush in `app.dart`
// landing the clock, and what is read back is a file, not the repository's
// memory.
//
// The board assertions are deliberately thin. The session's rules are asserted
// cell by cell in `test/features/tracks/model/`, the painter in
// `tracks_board_painter_test.dart`, and the codec is frozen by its own tests;
// repeating any of them here would put a test that nothing runs in front of one
// that everything runs.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/app.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_codec.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/completion_card.dart';
import 'package:zibo_games/core/ui/puzzle_menu.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_record.dart';
import 'package:zibo_games/features/tracks/model/tracks_difficulties.dart';
import 'package:zibo_games/features/tracks/skins/track_skin.dart';
import 'package:zibo_games/features/tracks/ui/tracks_board.dart';

/// The size this test plays.
///
/// 5x5 rather than a larger board because the point is the drag, not the
/// length of one: a 9x9 route is a long stroke through the same code, and its
/// journey runs past ten seconds. 5x5 also has the largest cells a phone gives
/// Tracks, so it is the *kindest* board for a real finger — the 32 dp question
/// belongs to the 9x9, and is the §8 device line, not this file's.
const TracksSpec smokeSpec = TracksSpec.s5x5;

/// See [smokeSpec].
///
/// Easy because it is the first rung a fresh profile is offered, so the tap
/// below is the one a child makes first, and its puzzles are the ones with the
/// most clues given — a short, certain stroke.
const Difficulty smokeDifficulty = Difficulty.easy;

/// The directory this test's save lives in, inside the one the app would use.
///
/// Its own rather than the app's, so a run cannot delete progress a child has
/// on the device it is being run on, and so the test starts from a known save
/// however many times it has been run before.
const String smokeSaveDirectory = 'integration_test_tracks_save';

/// How long a real generation is given before the test calls it a failure.
///
/// Far past the tail `PLAN-phase-9-tracks.md` §4.5 measures: what this catches
/// is a generation that never finished — an isolate that failed to spawn — not
/// one that was slow.
const Duration generationTimeout = Duration(seconds: 30);

/// How long the journey and the arrival time after it are given to reach the
/// card. A tap on the board skips the journey, so this only has to cover the
/// arrival motif's hold-back.
const Duration cardTimeout = Duration(seconds: 15);

/// How long the save is given to reach the disk after the app is backgrounded.
const Duration writeTimeout = Duration(seconds: 10);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a real Tracks puzzle is drawn to solved and the solve is saved', (
    tester,
  ) async {
    final directory = await _saveDirectory();
    final container = await _launch(tester, FileSaveStore(directory));

    final id = await _openARealPuzzle(tester, container);
    expect(id.spec, smokeSpec);
    expect(id.difficulty, smokeDifficulty);
    expect(
      _savedTracks(directory)?.solved,
      anyOf(isNull, isNot(contains(id.value))),
      reason: 'the run starts with nothing solved',
    );

    // Taken from the cache the source filled on its way to the screen.
    final record = _cachedRecord(container, id);
    expect(find.text(completionTitle), findsNothing);
    await _drag(tester, _solutionStroke(id.spec, record));

    // The journey runs from the moment of solving. A tap on the board is its
    // skip (`PLAN-phase-9-tracks.md` §6, PR 7 note 3), which keeps this test from
    // waiting out the animation it is not about.
    await tester.tap(find.byType(TracksBoard));
    await _pumpUntil(
      tester,
      find.text(completionTitle),
      timeout: cardTimeout,
      what: 'the completion card',
    );

    // The file half, and the assertion no widget test can make: the solve comes
    // back out of `save.json` as characters. The pause is what makes the clock
    // and the rest of the write reach the file even if the debounce has not
    // fired (`app.dart`), and the board was never half-saved: the solve and the
    // removal of the in-progress entry are one write (`progress_repository.dart`).
    //
    // Checked once the app is back rather than while it is away, for the reason
    // `sudoku_smoke_test.dart` gives: the binding draws no frames while paused,
    // so a failure there would hang rather than report.
    _goAway(tester);
    await _wait(const Duration(milliseconds: 200));
    _comeBack(tester);
    await tester.pump();

    final tracks = await _expectSolved(directory, id);
    final solved = tracks.solved[id.value]!;
    // Not asserted positive: the clock ticks in whole seconds and a 5x5 stroke
    // is drawn in well under one, so a correct solve can be recorded at 0 ms.
    expect(solved.mistakes, 0, reason: 'every connection drawn was the answer');
    expect(solved.hints, 0);
    expect(solved.clean, isTrue);
    expect(
      tracks.inProgress,
      isNot(contains(id.value)),
      reason: 'a solved board is not also a board in progress',
    );
    expect(
      tracks.bestTimeMs[TracksProgress.bestTimeKey(id.spec, id.difficulty)],
      solved.timeMs,
      reason: 'the menu\'s best time is the one just earned',
    );
  });
}

/// Where this run's save goes: a directory of its own inside the one
/// `path_provider` resolves, emptied first so the app starts from a fresh save.
///
/// Resolving it is itself part of the test — a plugin call is one of the things
/// only a device can answer. Run on the host with `-d flutter-tester` instead, no
/// plugin answers and a temp directory stands in; the isolate, the codec and the
/// filesystem are all still real there.
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
Future<ProviderContainer> _launch(WidgetTester tester, SaveStore store) async {
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
  return root.container;
}

/// Home, then Puzzles, then Tracks, then a puzzle that has to be generated
/// before it can be drawn — the way a child reaches one.
///
/// Nothing is overridden, so the tap on the difficulty row is followed by a real
/// `compute` on a real isolate (the menu's pre-warm may already have started the
/// same one; the source makes that one generation, not two). The wait is a poll
/// rather than a `pumpAndSettle`: settling stops when no frame is scheduled, and
/// a screen waiting on an isolate schedules none.
Future<TracksPuzzleId> _openARealPuzzle(
  WidgetTester tester,
  ProviderContainer container,
) async {
  await tester.tap(find.text('Puzzles'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(tracksMenuTitle));
  await tester.pumpAndSettle();

  // Tapped even though a fresh save opens on it already: the toggle is what a
  // child picking this size presses, and a default that moves later should
  // break this test rather than quietly change what it plays. Below the fold on
  // a short window, which is where the Snake close found a bare `tap` failing.
  final size = find.text(smokeSpec.label);
  await tester.ensureVisible(size);
  await tester.pumpAndSettle();
  await tester.tap(size);
  await tester.pumpAndSettle();

  final row = find.text(difficultyChoices[smokeDifficulty]!.label);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);

  await _pumpUntil(
    tester,
    find.byType(TracksBoard),
    timeout: generationTimeout,
    what:
        'a generated ${smokeSpec.label} '
        '${difficultyChoices[smokeDifficulty]!.label} board',
  );
  await tester.pump(const Duration(milliseconds: 400));

  // The id the screen is playing: the only cached Tracks puzzle with a spec and
  // difficulty this run asked for, on a save that started empty.
  final ids = [
    for (final key
        in container.read(progressRepositoryProvider).data.puzzleCache.keys)
      if (key.startsWith('tracks:')) TracksPuzzleId.parse(key),
  ];
  expect(ids, hasLength(1), reason: 'one puzzle was generated and cached');
  return ids.single;
}

/// The record the app cached on its way to drawing [id].
TracksPuzzleRecord _cachedRecord(
  ProviderContainer container,
  TracksPuzzleId id,
) {
  final encoded = container
      .read(progressRepositoryProvider)
      .data
      .puzzleCache[id.value];
  expect(encoded, isNotNull, reason: 'the generated puzzle was cached');
  return TracksPuzzleRecord.decode(id, encoded!);
}

/// A stroke position: a cell, or a port just outside the grid.
typedef _Position = (int row, int column);

/// The positions of one stroke that lays the whole solution: the start port,
/// every solution cell from the start to the goal, the goal port.
///
/// Walked from the record's solution rather than taken from a helper in `test/`,
/// which this directory does not import: leaving a cell by the side it was not
/// entered through is enough, because a solution is one path with no branches.
List<_Position> _solutionStroke(TracksSpec spec, TracksPuzzleRecord record) {
  final clues = record.clues;
  final cells = <int>[];
  var cell = clues.startCell;
  var cameIn = TrackSide.west;
  while (true) {
    cells.add(cell);
    final out = record.solution[cell] & ~cameIn;
    if (cell == clues.goalCell && out == TrackSide.south) break;
    final row =
        spec.rowOf(cell) +
        (out == TrackSide.south ? 1 : 0) -
        (out == TrackSide.north ? 1 : 0);
    final column =
        spec.columnOf(cell) +
        (out == TrackSide.east ? 1 : 0) -
        (out == TrackSide.west ? 1 : 0);
    cell = spec.indexAt(row, column);
    cameIn = TrackSide.opposite(out);
  }

  return [
    (clues.startRow, -1),
    for (final cell in cells) (spec.rowOf(cell), spec.columnOf(cell)),
    (spec.side, clues.goalColumn),
  ];
}

/// Drags one finger through [positions] and lifts it.
///
/// Through `startGesture`, not through the session, for the reason
/// `tracks_play_harness.dart` gives: the slop, the pan start and the position
/// arithmetic are what a child's finger exercises.
Future<void> _drag(WidgetTester tester, List<_Position> positions) async {
  final box = find
      .descendant(
        of: find.byType(TracksBoard),
        matching: find.byType(CustomPaint),
      )
      .evaluate()
      .first
      .renderObject!;
  final size = (box as RenderBox).size;
  final side = tester
      .widget<TracksBoard>(find.byType(TracksBoard))
      .session
      .spec
      .side;
  final layout = BoardLayout.fit(size, side);
  Offset at(_Position position) =>
      box.localToGlobal(layout.rectAt(position.$1, position.$2).center);

  final gesture = await tester.startGesture(at(positions.first));
  for (final position in positions.skip(1)) {
    await gesture.moveTo(at(position));
    await tester.pump();
  }
  await gesture.up();
  await tester.pump();
}

/// Waits until `save.json` records [id] as solved, and returns the Tracks
/// progress it was read from.
///
/// A poll rather than a read, because the write is debounced and then queued
/// behind whatever was already in flight (`progress_repository.dart`).
Future<TracksProgress> _expectSolved(
  Directory directory,
  TracksPuzzleId id,
) async {
  final deadline = DateTime.now().add(writeTimeout);

  var tracks = _savedTracks(directory);
  while (tracks == null || !tracks.solved.containsKey(id.value)) {
    if (DateTime.now().isAfter(deadline)) {
      fail(
        'after ${writeTimeout.inSeconds}s, save.json holds '
        '${tracks == null ? 'no Tracks progress' : 'solved ${tracks.solved.keys.toList()}'} '
        'rather than ${id.value}',
      );
    }
    await _wait(const Duration(milliseconds: 50));
    tracks = _savedTracks(directory);
  }
  return tracks;
}

/// The active profile's Tracks progress as `save.json` holds it, or null while
/// there is no file.
///
/// Read directly rather than through a [FileSaveStore], which deletes a leftover
/// `save.json.tmp` as it loads — harmless at launch, and a file deleted out from
/// under a write that is still running here.
TracksProgress? _savedTracks(Directory directory) {
  final file = File('${directory.path}/$saveFileName');
  if (!file.existsSync()) return null;

  // Whole or absent, never half: the store writes a temp file and renames it
  // over this one (`save_store.dart`).
  return decodeSave(file.readAsStringSync()).activeProfile.tracks;
}

/// The app going into the background, as the platform does it.
///
/// Every step of the transition, because `AppLifecycleListener` asserts on one
/// that skips a step.
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

/// Waits without drawing, for the reason `sudoku_smoke_test.dart` gives: the
/// binding produces no frames while the app is paused.
Future<void> _wait(Duration duration) => Future<void>.delayed(duration);
