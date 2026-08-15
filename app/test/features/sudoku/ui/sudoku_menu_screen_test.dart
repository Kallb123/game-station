// The menu's tests: what it draws for a given save, and that everything it
// draws leads to a board.
//
// Two harnesses, for the two halves. [pumpMenu] pumps the screen on its own, so
// a test can hand it a save and read what it made of it. The launch tests run
// the whole app instead, because tapping a card pushes a named route and the
// route table is the app's — a screen pumped as a bare `home:` would fail on
// the push rather than open the board.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/sudoku/data/providers.dart';
import 'package:zibo_games/features/sudoku/model/difficulties.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_menu_screen.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_play_screen.dart';

import '../../../app_harness.dart';
import '../../../core/ui/ui_harness.dart' show appThemes, usePhoneSurface;
import '../puzzle_fixtures.dart';

void main() {
  /// Which daily puzzle the fixed clock in [testClock] falls on.
  final today = dayIndexFor(testClock());

  /// A save whose only profile has [sudoku] behind it.
  SaveData saveWith(SudokuProgress sudoku) {
    final save = freshSave();
    return save.copyWith(
      profiles: [save.profiles.single.copyWith(sudoku: sudoku)],
    );
  }

  /// The menu on its own, over a save.
  ///
  /// Returns the container so a test can change the profile under the screen,
  /// which is the only way to ask whether the numbers on it are the active
  /// profile's or the file's first.
  Future<ProviderContainer> pumpMenu(
    WidgetTester tester, {
    SaveData? save,
    FakePuzzleSource? source,
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
        nowProvider.overrideWithValue(testClock),
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
          home: const SudokuMenuScreen(),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  /// The whole app, opened on the menu the way a child opens it.
  Future<void> openMenu(WidgetTester tester, {SaveData? save}) async {
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: save ?? freshSave()),
      overrides: [
        puzzleSourceProvider.overrideWithValue(FakePuzzleSource()),
        nowProvider.overrideWithValue(testClock),
      ],
    );
    await tester.tap(find.text('Sudoku'));
    await tester.pumpAndSettle();
  }

  /// The board the play screen is drawing, which is how a launch test says
  /// *which* puzzle it opened rather than only that it opened one.
  PuzzleId playedPuzzle(WidgetTester tester) =>
      tester.widget<SudokuGridView>(find.byType(SudokuGridView)).session.id;

  /// Taps what [label] names, scrolling it into view first: the menu scrolls,
  /// and the bottom rows of the list are under the fold on a small surface.
  Future<void> tapMenu(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  /// Opens whatever [label] names and waits for the board.
  ///
  /// Explicit pumps rather than `pumpAndSettle`, as `resume_test.dart` has it:
  /// the play screen's clock is a periodic timer, and settling would advance it
  /// by however long the route transition took.
  Future<void> tapAndPlay(WidgetTester tester, String label) async {
    await tapMenu(tester, label);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// The play screen's own back control, not the menu's: the route underneath
  /// stays in the tree while a route is pushed over it, so both are findable.
  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(SudokuPlayScreen),
        matching: find.byTooltip('Back'),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('every difficulty the menu can offer has a label and a glyph', () {
    // The screen reads these with a `!`: a tier added to the engine and not to
    // this map would throw on the way into the menu rather than be drawn
    // without a picture.
    for (final difficulty in Difficulty.values) {
      expect(difficultyChoices, contains(difficulty));
    }
    expect(sudokuSizes.map(sizeIcon).toSet(), hasLength(sudokuSizes.length));
  });

  group('the daily card', () {
    testWidgets('offers today\'s puzzle', (tester) async {
      await pumpMenu(tester);

      expect(find.text(dailyPuzzleTitle), findsOneWidget);
      expect(
        find.text(
          dailyPlayLabel(PuzzleId(SudokuSpec.s9x9, Difficulty.easy, today)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('pre-warms exactly one puzzle when the menu opens', (
      tester,
    ) async {
      // The pre-warm is what makes the card that is hardest to resist open
      // instantly (`PLAN.md` §3.5). One id: warming the whole difficulty list
      // would generate puzzles nobody asked for.
      final source = FakePuzzleSource();
      await pumpMenu(tester, source: source);

      expect(source.prewarms, [
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, today),
      ]);
      expect(source.loads, isEmpty, reason: 'nothing is being played yet');
    });

    testWidgets('shows the streak, and the tier last played', (tester) async {
      await pumpMenu(
        tester,
        save: saveWith(
          const SudokuProgress(
            inProgress: {'sudoku:6x6:hard:2': PuzzleInProgress(grid: '.')},
            dailyStreak: DailyStreak(current: 3, best: 5, lastDayIndex: 222),
          ),
        ),
      );

      expect(find.text(streakLabel(3)), findsOneWidget);
      expect(
        find.text(
          dailyPlayLabel(PuzzleId(SudokuSpec.s6x6, Difficulty.hard, today)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('invites a profile with no streak to start one', (
      tester,
    ) async {
      await pumpMenu(tester);

      expect(find.text(streakLabel(0)), findsOneWidget);
    });
  });

  group('the continue card', () {
    testWidgets('is absent when nothing is half-finished', (tester) async {
      await pumpMenu(tester);

      expect(find.textContaining('Keep going'), findsNothing);
    });

    testWidgets('names the board that was left', (tester) async {
      await pumpMenu(
        tester,
        save: saveWith(
          const SudokuProgress(
            inProgress: {
              'sudoku:9x9:medium:4': PuzzleInProgress(
                grid: '.',
                elapsedMs: 120000,
              ),
            },
          ),
        ),
      );

      expect(
        find.text(
          continueLabel(const PuzzleId(SudokuSpec.s9x9, Difficulty.medium, 4)),
        ),
        findsOneWidget,
      );
    });
  });

  group('the difficulty list', () {
    testWidgets('offers 6x6 without Expert', (tester) async {
      await pumpMenu(tester);
      expect(find.text(difficultyChoices[Difficulty.expert]!.label), findsOne);

      await tester.tap(find.text(SudokuSpec.s6x6.label));
      await tester.pump();

      for (final difficulty in difficultiesFor(SudokuSpec.s6x6)) {
        expect(find.text(difficultyChoices[difficulty]!.label), findsOne);
      }
      // The one combination the engine refuses outright — `PuzzleId.parse` will
      // not spell it and `generateSudoku` throws for it — so the menu cannot be
      // allowed to draw it.
      expect(
        find.text(difficultyChoices[Difficulty.expert]!.label),
        findsNothing,
      );
    });

    testWidgets('shows what each tier has cost so far', (tester) async {
      await pumpMenu(
        tester,
        save: saveWith(
          const SudokuProgress(
            solved: {
              'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 245000),
              'sudoku:9x9:easy:1': SolvedPuzzle(timeMs: 301000),
            },
            bestTimeMs: {'9x9:easy': 245000},
          ),
        ),
      );

      expect(
        find.text(tierProgressLabel(solved: 2, bestTimeMs: 245000)),
        findsOneWidget,
      );
      expect(find.text('Solved 2 · Best 4:05'), findsOneWidget);
      expect(
        find.text(tierProgressLabel(solved: 0, bestTimeMs: null)),
        findsNWidgets(difficultiesFor(SudokuSpec.s9x9).length - 1),
      );
    });
  });

  testWidgets('the counts, times and streak are the active profile\'s', (
    tester,
  ) async {
    // Two children share the tablet, and the menu is the screen that says whose
    // history is whose (`PLAN-phase-3.md` §4.7's done-criterion).
    final save = freshSave();
    final container = await pumpMenu(
      tester,
      save: save.copyWith(
        profiles: [
          save.profiles.single.copyWith(
            sudoku: const SudokuProgress(
              solved: {'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 245000)},
              dailyStreak: DailyStreak(current: 3, best: 3, lastDayIndex: 222),
              bestTimeMs: {'9x9:easy': 245000},
            ),
          ),
          Profile(
            id: 'p2',
            name: 'Bo',
            avatar: AvatarId.owl,
            createdAt: testClock(),
            sudoku: const SudokuProgress(
              dailyStreak: DailyStreak(current: 9, best: 9, lastDayIndex: 223),
            ),
          ),
        ],
      ),
    );

    expect(find.text(streakLabel(3)), findsOneWidget);
    expect(
      find.text(tierProgressLabel(solved: 1, bestTimeMs: 245000)),
      findsOneWidget,
    );

    final repository = container.read(progressRepositoryProvider);
    repository.selectProfile('p2');
    // Awaited rather than pumped past: a test that pumped the 500 ms debounce
    // would be testing the timer, and one that left it pending fails on the
    // binding's own invariant check (`app_test.dart`).
    await repository.flush();
    await tester.pump();

    expect(find.text(streakLabel(9)), findsOneWidget);
    expect(find.text(streakLabel(3)), findsNothing);
    expect(
      find.text(tierProgressLabel(solved: 1, bestTimeMs: 245000)),
      findsNothing,
    );
    expect(
      find.text(tierProgressLabel(solved: 0, bestTimeMs: null)),
      findsNWidgets(difficultiesFor(SudokuSpec.s9x9).length),
    );
  });

  group('through the app', () {
    testWidgets('every difficulty of both sizes opens a playable board', (
      tester,
    ) async {
      // The pull request's done-criterion, as far as a widget test carries it
      // (`PLAN-phase-3.md` §6): a row that named a puzzle the engine will not
      // build, or that launched the wrong one, is a dead end a child finds
      // before anyone else does.
      await openMenu(tester);

      for (final spec in sudokuSizes) {
        await tapMenu(tester, spec.label);
        await tester.pumpAndSettle();

        for (final difficulty in difficultiesFor(spec)) {
          await tapAndPlay(tester, difficultyChoices[difficulty]!.label);

          expect(
            playedPuzzle(tester),
            PuzzleId(spec, difficulty, 0),
            reason: '${spec.label} ${difficulty.name}',
          );
          await goBack(tester);
        }
      }
    });

    testWidgets('the daily card opens today\'s board', (tester) async {
      await openMenu(tester);
      final daily = PuzzleId(SudokuSpec.s9x9, Difficulty.easy, today);

      await tapAndPlay(tester, dailyPlayLabel(daily));

      expect(playedPuzzle(tester), daily);
      await tester.pump();
    });

    testWidgets('the continue card comes back to the board that was left', (
      tester,
    ) async {
      await openMenu(tester);
      final left = const PuzzleId(SudokuSpec.s6x6, Difficulty.easy, 0);

      await tapMenu(tester, left.spec.label);
      await tester.pumpAndSettle();
      await tapAndPlay(tester, difficultyChoices[left.difficulty]!.label);
      await goBack(tester);

      // The save was written by the screen that was just closed, so the card
      // is drawn from a `PuzzleInProgress` rather than from anything this test
      // built.
      await tapAndPlay(tester, continueLabel(left));

      expect(playedPuzzle(tester), left);
    });

    testWidgets('a solved puzzle moves its tier on to the next one', (
      tester,
    ) async {
      await openMenu(
        tester,
        save: saveWith(
          const SudokuProgress(
            solved: {
              'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 1000),
              'sudoku:9x9:easy:1': SolvedPuzzle(timeMs: 1000),
            },
          ),
        ),
      );

      await tapAndPlay(tester, difficultyChoices[Difficulty.easy]!.label);

      expect(
        playedPuzzle(tester),
        const PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 2),
      );
    });
  });

  // The whole screen on the smallest target, in both themes, at 100% and 200%
  // text scale (`PLAN-phase-3.md` §1). The list scrolls, so what is at risk
  // here is a row that cannot: the size toggle is two buttons side by side, and
  // each card is a glyph beside a line of text that has to wrap rather than
  // run off the edge.
  for (final entry in appThemes.entries) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('the menu fits a small phone at '
          '${(scale * 100).round()}% text scale in ${entry.key}', (
        tester,
      ) async {
        await usePhoneSurface(tester);
        await pumpMenu(
          tester,
          // A save with something in every card, so the matrix covers the
          // tallest the screen gets rather than its empty state.
          save: saveWith(
            const SudokuProgress(
              solved: {'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 245000)},
              inProgress: {'sudoku:9x9:medium:4': PuzzleInProgress(grid: '.')},
              dailyStreak: DailyStreak(current: 12, best: 12),
              bestTimeMs: {'9x9:easy': 245000},
            ),
          ),
          theme: entry.value(),
          textScale: scale,
          padding: const EdgeInsets.only(top: 44, bottom: 34),
        );

        expect(tester.takeException(), isNull);

        // Every row a child taps clears the floor in `PLAN.md` §4.2, at every
        // scale — a tile that grew its text but not its height would still be
        // a 40 dp target.
        for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
          expect(
            tester.getSize(find.byWidget(tile)).height,
            greaterThanOrEqualTo(AppTapTargets.min),
          );
        }
      });
    }
  }
}
