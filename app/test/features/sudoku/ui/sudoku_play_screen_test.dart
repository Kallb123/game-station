// The play screen's tests: the load, the clock, and the save.
//
// The screen is pumped on its own rather than through the app's routes, so that
// each test can hand it a source that stalls, a save that already holds a board,
// or a settings block with the timer on. The route itself, and the resume that
// crosses a relaunch, are tested through the whole app instead —
// `app_test.dart` and `resume_test.dart`.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/progress_repository.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/core/ui/theme.dart';
import 'package:game_station/features/sudoku/data/providers.dart';
import 'package:game_station/features/sudoku/data/puzzle_record.dart';
import 'package:game_station/features/sudoku/data/puzzle_source.dart';
import 'package:game_station/features/sudoku/model/session_codec.dart';
import 'package:game_station/features/sudoku/model/sudoku_session.dart';
import 'package:game_station/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:game_station/features/sudoku/ui/sudoku_keypad.dart';
import 'package:game_station/features/sudoku/ui/sudoku_play_screen.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../app_harness.dart';
import '../../../core/ui/ui_harness.dart';
import '../puzzle_fixtures.dart';

void main() {
  final id = PuzzleId.parse('sudoku:6x6:easy:7');

  /// The screen, the scope under it, and the store the scope writes to.
  ///
  /// Returns the container so a test can assert what the screen saved rather
  /// than only what it drew — the save is the point of this screen, and it is
  /// not visible on it.
  Future<ProviderContainer> pumpPlay(
    WidgetTester tester, {
    PuzzleId? puzzle,
    PuzzleSource? source,
    SaveData? save,
    ThemeData? theme,
    double textScale = 1,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    final store = MemorySaveStore(initial: save ?? freshSave());
    final container = ProviderContainer(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(await store.load()),
        puzzleSourceProvider.overrideWithValue(source ?? FakePuzzleSource()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: theme ?? AppTheme.day(),
          debugShowCheckedModeBanner: false,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              // System insets — a notch, a home indicator, a gesture bar.
              padding: padding,
            ),
            child: child!,
          ),
          home: SudokuPlayScreen(args: SudokuPlayArgs(puzzle ?? id)),
        ),
      ),
    );
    // One frame for the load's microtask, which is all a cached or fixture
    // puzzle needs. Not `pumpAndSettle`: that would run the spinner delay out
    // and hide the difference these tests are about.
    await tester.pump();
    return container;
  }

  /// The session the board is drawing, which is the only handle a test has on
  /// the state the screen built.
  SudokuSession sessionOf(WidgetTester tester) =>
      tester.widget<SudokuGridView>(find.byType(SudokuGridView)).session;

  ProgressRepository repositoryOf(ProviderContainer container) =>
      container.read(progressRepositoryProvider);

  PuzzleInProgress? savedIn(ProviderContainer container) =>
      repositoryOf(container).activeProfile.sudoku.inProgress[id.value];

  /// The first cell a child could type into.
  int firstEmpty(SudokuSession session) => emptyCells(session).first;

  group('the load', () {
    testWidgets('draws the board and the keypad', (tester) async {
      await pumpPlay(tester);

      expect(find.byType(SudokuGridView), findsOneWidget);
      expect(find.byType(SudokuKeypad), findsOneWidget);
    });

    testWidgets('shows no spinner for a puzzle that arrives inside the '
        'delay', (tester) async {
      // A cached puzzle is instant and a 9x9 Easy is a millisecond
      // (`PLAN.md` §3.5). A spinner for either is a flash that reads as a
      // glitch, which is what `puzzleSpinnerDelay` exists to prevent.
      await pumpPlay(tester);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(puzzleSpinnerDelay * 2);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows one for a puzzle that does not', (tester) async {
      final source = _StalledPuzzleSource();
      await pumpPlay(tester, source: source);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump(puzzleSpinnerDelay);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(SudokuGridView), findsNothing);

      source.finish(id);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SudokuGridView), findsOneWidget);
    });

    testWidgets('says one plain sentence when the puzzle will not come', (
      tester,
    ) async {
      // Not a stack trace and not a retry loop: a child cannot act on either
      // (`AGENTS.md`). The way back is the header's own back control.
      await pumpPlay(tester, source: _BrokenPuzzleSource());
      await tester.pump(puzzleSpinnerDelay * 2);

      expect(find.text(puzzleFailedMessage), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(SudokuGridView), findsNothing);
    });
  });

  group('the clock', () {
    testWidgets('is hidden until the setting asks for it', (tester) async {
      await pumpPlay(tester);
      expect(find.text('0:00'), findsNothing);
    });

    testWidgets('counts while the app is running', (tester) async {
      await pumpPlay(
        tester,
        save: freshSave(settings: const AppSettings(showTimer: true)),
      );
      expect(find.text('0:00'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));

      expect(find.text('0:03'), findsOneWidget);
      expect(sessionOf(tester).elapsed, const Duration(seconds: 3));
    });

    testWidgets('stops while the app is not', (tester) async {
      // A tablet left face-down for an hour has not been played for an hour,
      // and the time it stores decides a best time (`PLAN.md` §5.2).
      final container = await pumpPlay(
        tester,
        save: freshSave(settings: const AppSettings(showTimer: true)),
      );
      await tester.pump(const Duration(seconds: 2));

      _goAway(tester);
      await tester.pump(const Duration(minutes: 5));

      expect(find.text('0:02'), findsOneWidget);
      expect(sessionOf(tester).elapsed, const Duration(seconds: 2));
      // Stopping is also when it is written: nothing else would write the
      // seconds between the last move and the app going away.
      expect(savedIn(container)?.elapsedMs, 2000);

      _comeBack(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('0:03'), findsOneWidget);
    });

    testWidgets('reads minutes and seconds, and hours only once there are '
        'some', (tester) async {
      expect(formatElapsed(Duration.zero), '0:00');
      expect(formatElapsed(const Duration(seconds: 9)), '0:09');
      expect(formatElapsed(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(formatElapsed(const Duration(minutes: 59)), '59:00');
      expect(
        formatElapsed(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
    });
  });

  group('the save', () {
    testWidgets('holds the board after every move', (tester) async {
      final container = await pumpPlay(tester);
      final session = sessionOf(tester);
      final target = firstEmpty(session);

      session
        ..select(target)
        ..enter(3);
      await tester.pump();

      final saved = savedIn(container);
      expect(saved, isNotNull);
      expect(decodeGrid(session.spec, saved!.grid)[target], 3);
      expect(saved.undoStack, hasLength(1));
    });

    testWidgets('is not rewritten by a tap that only moves the selection', (
      tester,
    ) async {
      // The session notifies on a selection as it does on a move — the board
      // has to repaint either way — and this screen answers every notification
      // with a save. What keeps that from being a write per tap is that the
      // stored form holds no selection, so the repository sees a value equal to
      // the one it has and schedules nothing (`progress_repository.dart`).
      final container = await pumpPlay(tester);
      final session = sessionOf(tester);
      final empty = emptyCells(session);
      final repository = repositoryOf(container);

      session
        ..select(empty[0])
        ..enter(3);
      await tester.pump();
      await repository.flush();

      session.select(empty[1]);
      await tester.pump();

      expect(repository.isSaving, isFalse);
    });

    testWidgets('holds the pencil marks too', (tester) async {
      final container = await pumpPlay(tester);
      final session = sessionOf(tester);
      final target = firstEmpty(session);

      session
        ..select(target)
        ..pencilMode = true
        ..enter(2);
      await tester.pump();

      final saved = savedIn(container);
      expect(decodeNotes(session.spec, saved!.notes)[target], 1 << 1);
    });

    testWidgets('resumes the board a previous run left', (tester) async {
      final played = fixtureSession(id);
      final target = firstEmpty(played);
      played
        ..select(target)
        ..enter(4)
        ..elapsed = const Duration(seconds: 42);

      final container = await pumpPlay(tester, save: _saveHolding(id, played));
      final session = sessionOf(tester);

      expect(session.digitAt(target), 4);
      expect(session.elapsed, const Duration(seconds: 42));
      expect(session.canUndo, isTrue, reason: 'the undo stack came back too');
      expect(
        savedIn(container),
        played.toSaved(),
        reason: 'resuming stores nothing new',
      );
    });

    testWidgets('starts fresh from a saved board that will not decode', (
      tester,
    ) async {
      // A truncated or hand-edited entry. The child gets a playable puzzle and
      // no explanation, and the entry that cannot be read is dropped rather
      // than left to fail the same way on the next launch.
      final container = await pumpPlay(
        tester,
        save: _saveHolding(id, null, grid: 'nonsense'),
      );

      expect(find.byType(SudokuGridView), findsOneWidget);
      expect(sessionOf(tester).canUndo, isFalse);
      expect(savedIn(container), isNull);
    });

    // Where the clock stopped is written by the pop rather than by the screen's
    // disposal (`sudoku_play_screen.dart`), so the test for it is one that pops
    // a route: `completion_test.dart`, which runs the app's own routes.
  });

  // The whole screen on the smallest target, at both sizes, in both themes, at
  // 100% and 200% text scale (`PLAN-phase-3.md` §1). This is where the chrome
  // is paid for: an overflow fails the first check, and a board crushed by a
  // header that grew instead fails the second.
  //
  // It replaces PR 5's `board_layout_test.dart`, which asked the same eight
  // questions of the board and keypad alone — the pair was never the thing at
  // risk, the screen around them is.
  for (final puzzle in [
    PuzzleId.parse('sudoku:6x6:easy:11'),
    PuzzleId.parse('sudoku:9x9:easy:11'),
  ]) {
    for (final entry in appThemes.entries) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('a ${puzzle.spec.label} fits a small phone at '
            '${(scale * 100).round()}% text scale in ${entry.key}', (
          tester,
        ) async {
          await usePhoneSurface(tester);
          await pumpPlay(
            tester,
            puzzle: puzzle,
            // The timer on, because it is the part of the header that grows
            // with the text scale.
            save: freshSave(settings: const AppSettings(showTimer: true)),
            theme: entry.value(),
            textScale: scale,
            padding: const EdgeInsets.only(top: 44, bottom: 34),
          );

          expect(tester.takeException(), isNull);

          final board = tester.getSize(
            find
                .descendant(
                  of: find.byType(SudokuGridView),
                  matching: find.byType(DecoratedBox),
                )
                .first,
          );
          expect(board.width, board.height, reason: 'still square');
          // A cell of at least 16 dp. Not a target — the same board is 194 dp
          // across on this phone at 100% — but the floor under the worst case
          // in this matrix, which is a 9x9 at 200% where the keypad's own
          // floors have taken what they need first. A board thinner than this
          // is one no child can play, and it is what a heading at display size
          // did to this screen before it grew its own.
          expect(
            board.width,
            greaterThanOrEqualTo(puzzle.spec.digits * 16),
            reason: 'a ${puzzle.spec.label} board of ${board.width} dp',
          );
        });
      }
    }
  }
}

/// The app leaving the foreground, in the steps the platform makes them in —
/// `AppLifecycleListener` asserts on a transition that skips one.
void _goAway(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

void _comeBack(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

/// A save whose active profile is part-way through [id].
///
/// Either the board [played] left, or one built by hand from [grid] — which is
/// how a test spells a saved entry that no run of this app could have written.
SaveData _saveHolding(PuzzleId id, SudokuSession? played, {String grid = ''}) {
  final save = freshSave();
  final progress = played?.toSaved() ?? PuzzleInProgress(grid: grid);

  return save.copyWith(
    profiles: [
      for (final profile in save.profiles)
        profile.copyWith(
          sudoku: profile.sudoku.copyWith(inProgress: {id.value: progress}),
        ),
    ],
  );
}

/// A source whose loads finish when the test says so, so that the spinner has
/// something to appear over.
class _StalledPuzzleSource implements PuzzleSource {
  final Map<String, Completer<PuzzleRecord>> _waiting = {};

  void finish(PuzzleId id) => _waiting[id.value]!.complete(fixtureRecord(id));

  @override
  Future<PuzzleRecord> load(PuzzleId id) =>
      (_waiting[id.value] ??= Completer<PuzzleRecord>()).future;

  @override
  void prewarm(PuzzleId id) {}
}

/// A source that fails, as an isolate that died would.
class _BrokenPuzzleSource implements PuzzleSource {
  @override
  Future<PuzzleRecord> load(PuzzleId id) =>
      Future<PuzzleRecord>.error(StateError('no isolate'));

  @override
  void prewarm(PuzzleId id) {}
}
