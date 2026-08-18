// Finishing a puzzle: the card, what it says, what it stores, and the two ways
// on from it.
//
// The 6x6 is solved by tapping — a cell, then a digit, twenty times over —
// through the app's own routes and its own save store, because what is being
// checked is the whole path from a child's finger to a `SolvedPuzzle` on disk
// (`PLAN-phase-3.md` §6). A test that called `session.enter` would exercise the
// model, which `sudoku_session_test.dart` already does in milliseconds.
//
// Every pump is explicit rather than `pumpAndSettle`: the play screen's clock
// is a periodic timer, and settling would advance it by however long a route
// transition happened to take, which is the number these tests assert on.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/audio/motif.dart';
import 'package:zibo_games/core/audio/providers.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/sudoku/data/providers.dart';
import 'package:zibo_games/features/sudoku/model/sudoku_session.dart';
import 'package:zibo_games/features/sudoku/ui/completion_card.dart';
import 'package:zibo_games/features/sudoku/ui/confetti.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_menu_screen.dart';

import '../../../app_harness.dart';
import '../../../core/audio/recording_audio.dart';
import '../puzzle_fixtures.dart';

/// The board these tests finish.
///
/// 6x6 Easy because filling it by tapping is twenty cells rather than sixty,
/// and index 0 because that is what the menu's Easy row offers a profile with
/// nothing solved (`sudoku_menu.dart`).
const PuzzleId solvedPuzzle = PuzzleId(SudokuSpec.s6x6, Difficulty.easy, 0);

void main() {
  /// The board on screen, which is the only handle a test has on the state the
  /// screen built.
  SudokuSession boardOf(WidgetTester tester) =>
      tester.widget<SudokuGridView>(find.byType(SudokuGridView)).session;

  /// Taps what [label] names on the menu, scrolling it into view first.
  ///
  /// Settling is safe here and only here: it happens while the menu is the only
  /// screen up, so there is no clock for it to advance — the tap itself is left
  /// for the caller to pump, because the tap that opens the board is the one
  /// this file's pumps are counted from.
  Future<void> tapInMenu(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  /// Launches the app over [save] and taps through the menu to [solvedPuzzle].
  Future<ProviderContainer> openTheBoard(
    WidgetTester tester, {
    SaveData? save,
    List<Override> overrides = const [],
  }) async {
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: save ?? freshSave()),
      overrides: [
        puzzleSourceProvider.overrideWithValue(FakePuzzleSource()),
        ...overrides,
      ],
    );

    await tester.tap(find.text('Sudoku'));
    await tester.pumpAndSettle();
    // Scrolled to before each tap, because the menu scrolls: at 200% text scale
    // on a small phone its difficulty rows start below the fold.
    await tapInMenu(tester, solvedPuzzle.spec.label);
    await tester.pumpAndSettle();
    await tapInMenu(tester, difficultyChoices[solvedPuzzle.difficulty]!.label);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(SudokuGridView), findsOneWidget);
    return container;
  }

  /// Puts [digit] in [cell] the way a child does: tap the cell, tap the pad.
  Future<void> tapIn(WidgetTester tester, int cell, int digit) async {
    await tester.tap(find.byKey(ValueKey<int>(cell)));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '$digit'));
    await tester.pump();
  }

  /// Fills every empty cell of the board on screen with the solution's digit,
  /// except [wrong], which gets one the solution disagrees with, and [leave],
  /// which is left empty.
  ///
  /// [byTapping] fills the board through the widgets, one cell and one keypad
  /// button at a time, which is what the phase's done-criterion asks for
  /// (`PLAN-phase-3.md` §6). It is the slow way and one test needs it; the rest
  /// drive the session the widgets are drawing, which is the same object the
  /// taps reach and about twenty pumps cheaper per board (§1's fifteen-second
  /// budget for the whole app suite).
  ///
  /// The digits come from a throwaway session over the same fixture rather than
  /// from a table: the board is whatever the generator makes of
  /// `sudoku:6x6:easy:0`, so a hardcoded digit would be right until the next
  /// `generatorVersion` bump.
  Future<void> fillBoard(
    WidgetTester tester, {
    int? wrong,
    int? leave,
    bool byTapping = false,
  }) async {
    final scratch = fixtureSession(solvedPuzzle);
    final board = boardOf(tester);

    for (final cell in emptyCells(scratch)) {
      if (cell == leave) continue;
      // A digit that is right, or the first one that is not.
      var digit = 0;
      for (digit = 1; digit <= scratch.spec.digits; digit++) {
        scratch
          ..select(cell)
          ..enter(digit);
        if (scratch.isWrong(cell) == (cell == wrong)) break;
      }

      if (byTapping) {
        await tapIn(tester, cell, digit);
      } else {
        board
          ..select(cell)
          ..enter(digit);
      }
    }
    await tester.pump();
  }

  /// Runs the celebration out.
  ///
  /// The confetti holds a ticker while it falls (`confetti.dart`), and the test
  /// framework fails a test that ends with one still running — so every test
  /// that leaves the card on screen settles it first. The clock has stopped by
  /// then, so the seconds this passes over are not counted against anyone.
  Future<void> settleCelebration(WidgetTester tester) => tester.pumpAndSettle();

  /// What the active profile stored for [id].
  SolvedPuzzle? solvedIn(ProviderContainer container, PuzzleId id) => container
      .read(progressRepositoryProvider)
      .activeProfile
      .sudoku
      .solved[id.value];

  testWidgets('a 6x6 solved by tapping is stored as a clean solve', (
    tester,
  ) async {
    final container = await openTheBoard(tester);
    final board = boardOf(tester);
    final last = emptyCells(board).last;

    await tester.pump(const Duration(seconds: 8));
    await fillBoard(tester, leave: last, byTapping: true);
    expect(
      find.byType(CompletionCard),
      findsNothing,
      reason: 'a board with a hole in it is not finished',
    );

    await tapIn(
      tester,
      last,
      int.parse(fixtureRecord(solvedPuzzle).solution[last]),
    );

    expect(find.text(completionTitle), findsOneWidget);
    expect(find.text(completionCleanLabel), findsOneWidget);
    expect(find.text('0:08'), findsOneWidget, reason: 'the time it took');
    await settleCelebration(tester);

    final solved = solvedIn(container, solvedPuzzle);
    expect(solved?.timeMs, 8000);
    expect(solved?.hints, 0);
    expect(solved?.mistakes, 0);
    expect(solved?.clean, isTrue);
    expect(
      solved?.solvedAt,
      isNotNull,
      reason: 'dated by the repository, from the clock the streak uses',
    );
    expect(
      container
          .read(progressRepositoryProvider)
          .activeProfile
          .sudoku
          .inProgress,
      isEmpty,
      reason: 'a puzzle cannot be both finished and in progress',
    );
    expect(
      container.read(progressRepositoryProvider).isSaving,
      isFalse,
      reason: 'the result was flushed rather than left in the debounce window',
    );
  });

  testWidgets('a hint and a mistake both cost the star', (tester) async {
    final container = await openTheBoard(tester);
    final board = boardOf(tester);
    final empty = emptyCells(board);

    // A wrong digit, corrected, and one cell given away — the two things that
    // clear `clean` (`PLAN.md` §3.7).
    await fillBoard(tester, wrong: empty.first, leave: empty.last);
    await tester.tap(find.byTooltip('Hint'));
    await tester.pump();
    expect(
      board.isWrong(empty.first),
      isTrue,
      reason: 'the first hint points at the mistake rather than revealing',
    );

    await tapIn(
      tester,
      empty.first,
      int.parse(fixtureRecord(solvedPuzzle).solution[empty.first]),
    );
    await tester.tap(find.byTooltip('Hint'));
    await tester.pump();

    expect(find.byType(CompletionCard), findsOneWidget);
    final solved = solvedIn(container, solvedPuzzle);
    expect(solved?.hints, 1, reason: 'only the revealing hint counted');
    expect(solved?.mistakes, 1);
    expect(solved?.clean, isFalse);
    expect(find.text(completionCleanLabel), findsNothing);
    await settleCelebration(tester);
  });

  testWidgets('the clock stops when the card appears', (tester) async {
    await openTheBoard(tester);
    final board = boardOf(tester);

    await tester.pump(const Duration(seconds: 4));
    await fillBoard(tester);
    expect(find.byType(CompletionCard), findsOneWidget);

    await settleCelebration(tester);
    await tester.pump(const Duration(minutes: 2));

    expect(board.elapsed, const Duration(seconds: 4));
  });

  testWidgets('next puzzle plays the one after it, and back leaves', (
    tester,
  ) async {
    await openTheBoard(tester);
    await fillBoard(tester);

    await tester.tap(find.text(nextPuzzleLabel));
    // Settled rather than pumped past: the finished screen is on its way out
    // while the fresh one comes in, and both hold a board until it is.
    await tester.pumpAndSettle();

    expect(boardOf(tester).id.index, solvedPuzzle.index + 1);
    expect(boardOf(tester).id.difficulty, solvedPuzzle.difficulty);
    expect(boardOf(tester).id.spec, solvedPuzzle.spec);
    expect(
      find.byType(CompletionCard),
      findsNothing,
      reason: 'a fresh board, not the one that was just finished',
    );

    // The finished puzzle was replaced rather than stacked under this one, so
    // one back tap lands on the menu (`PLAN-phase-3.md` §4.6).
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(dailyPuzzleTitle), findsOneWidget);
  });

  testWidgets('back to Sudoku leaves the board', (tester) async {
    await openTheBoard(tester);
    await fillBoard(tester);

    await tester.tap(find.text(backToSudokuLabel));
    await tester.pumpAndSettle();

    expect(find.text(dailyPuzzleTitle), findsOneWidget);
    expect(find.byType(SudokuGridView), findsNothing);
  });

  testWidgets('leaving mid-puzzle writes where the clock stopped', (
    tester,
  ) async {
    // Not a completion, but the same question one layer down: the seconds
    // between the last move and the child leaving exist only in memory until
    // something writes them, and the thing that writes them is the pop
    // (`sudoku_play_screen.dart`). Through the app's own routes, because a pop
    // is what this is about.
    final container = await openTheBoard(tester);
    final board = boardOf(tester);
    final empty = emptyCells(board).first;

    await tapIn(
      tester,
      empty,
      int.parse(fixtureRecord(solvedPuzzle).solution[empty]),
    );
    await tester.pump(const Duration(seconds: 6));

    await tester.pageBack();
    await tester.pumpAndSettle();

    final saved = container
        .read(progressRepositoryProvider)
        .activeProfile
        .sudoku
        .inProgress[solvedPuzzle.value];
    expect(saved?.elapsedMs, 6000);
    expect(
      container.read(progressRepositoryProvider).isSaving,
      isFalse,
      reason: 'flushed, because a board nobody is playing has no next write',
    );
  });

  testWidgets('the card fits a small phone at 200% text scale', (tester) async {
    // The card is the one thing on this screen a child cannot play around: if
    // *Back to Sudoku* is clipped off the bottom, the puzzle is over and there
    // is no way off the screen (`PLAN-phase-3.md` §1). It scrolls rather than
    // clipping, and this is the assertion that says so.
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    tester.platformDispatcher.textScaleFactorTestValue = 2;

    await openTheBoard(tester);
    await fillBoard(tester);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text(backToSudokuLabel));
    await tester.tap(find.text(backToSudokuLabel));
    await tester.pumpAndSettle();

    expect(find.text(dailyPuzzleTitle), findsOneWidget);
  });

  group('the confetti', () {
    testWidgets('falls over a finished board', (tester) async {
      await openTheBoard(tester);
      await fillBoard(tester);

      expect(
        find.descendant(
          of: find.byType(Confetti),
          matching: find.byType(CustomPaint),
        ),
        findsOneWidget,
      );
      await settleCelebration(tester);
    });

    testWidgets('does not, when the child asked for less moving about', (
      tester,
    ) async {
      // The stored half of the reduced-motion decision, which `app.dart` or-s
      // into `MediaQuery.disableAnimations` (`PLAN-phase-3.md` §4.6).
      await openTheBoard(
        tester,
        save: freshSave(settings: const AppSettings(reduceMotion: true)),
      );
      await fillBoard(tester);

      expect(find.byType(CompletionCard), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Confetti),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
    });
  });

  group('the completion sound', () {
    // The fanfare's own gate, not `AppSettings.sound`'s: `RecordingAudio` is a
    // fake with no dependency on the save at all, so its `sound: false` case
    // is set directly rather than through a profile
    // (`PLAN-phase-5.md` §4.2's PR 1 done-criterion).
    testWidgets('plays once on completion', (tester) async {
      final audio = RecordingAudio();
      await openTheBoard(
        tester,
        overrides: [appAudioProvider.overrideWithValue(audio)],
      );
      await fillBoard(tester);

      expect(audio.played, [Motif.sudokuComplete]);
      await settleCelebration(tester);
    });

    testWidgets('stays silent with sound off', (tester) async {
      final audio = RecordingAudio()
        ..applySettings(const AppSettings(sound: false));
      await openTheBoard(
        tester,
        overrides: [appAudioProvider.overrideWithValue(audio)],
      );
      await fillBoard(tester);

      expect(audio.played, isEmpty);
      await settleCelebration(tester);
    });
  });

  group('mistake feedback', () {
    /// Whether the digit drawn in [cell] is underlined, which is how the board
    /// says a digit is wrong without depending on its colour
    /// (`sudoku_cell.dart`).
    bool flagged(WidgetTester tester, int cell, int digit) =>
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(ValueKey<int>(cell)),
                matching: find.text('$digit'),
              ),
            )
            .style
            ?.decoration ==
        TextDecoration.underline;

    /// [save] with the active profile told when to be shown a mistake.
    SaveData savedWith(MistakeFeedback feedback) {
      final save = freshSave();
      return save.copyWith(
        profiles: [
          for (final profile in save.profiles)
            profile.copyWith(mistakeFeedback: feedback),
        ],
      );
    }

    testWidgets('immediate underlines a wrong digit as it lands', (
      tester,
    ) async {
      await openTheBoard(tester, save: savedWith(MistakeFeedback.immediate));
      final cell = emptyCells(boardOf(tester)).first;
      final wrong = _wrongDigitFor(cell);

      await tapIn(tester, cell, wrong);

      expect(flagged(tester, cell, wrong), isTrue);
    });

    testWidgets('atCompletion waits until the grid is full', (tester) async {
      await openTheBoard(tester, save: savedWith(MistakeFeedback.atCompletion));
      final cell = emptyCells(boardOf(tester)).first;
      final wrong = _wrongDigitFor(cell);

      await tapIn(tester, cell, wrong);
      expect(
        flagged(tester, cell, wrong),
        isFalse,
        reason: 'nothing is said mid-puzzle in this mode',
      );

      await fillBoard(tester, wrong: cell);

      expect(find.byType(CompletionCard), findsNothing);

      expect(
        flagged(tester, cell, wrong),
        isTrue,
        reason: 'a full grid that is not solved has to say why',
      );
    });
  });
}

/// A digit for [cell] of [solvedPuzzle] that the solution disagrees
/// with.
int _wrongDigitFor(int cell) {
  final scratch = fixtureSession(solvedPuzzle)..select(cell);
  for (var digit = 1; digit <= scratch.spec.digits; digit++) {
    scratch.enter(digit);
    if (scratch.isWrong(cell)) return digit;
  }
  throw StateError('cell $cell takes no wrong digit');
}
