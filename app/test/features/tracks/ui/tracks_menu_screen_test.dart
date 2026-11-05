// The Tracks menu's tests: what it draws for a given save, and that everything
// it draws leads to a board.
//
// The launch tests run the whole app, because tapping a row pushes a named
// route and the route table is the app's. The layout test pumps the screen on
// its own so it can set the text scale.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/puzzle_menu.dart';
import 'package:zibo_games/features/tracks/data/providers.dart';
import 'package:zibo_games/features/tracks/model/tracks_difficulties.dart';
import 'package:zibo_games/features/tracks/ui/tracks_board.dart';
import 'package:zibo_games/features/tracks/ui/tracks_menu_screen.dart';
import 'package:zibo_games/features/tracks/ui/tracks_theme_picker.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../../../core/ui/ui_harness.dart' show appThemes, usePhoneSurface;
import '../tracks_fixtures.dart';
import '../tracks_puzzle_fixtures.dart';
import 'tracks_play_harness.dart' show repositoryOf, sessionOf;

void main() {
  TracksPuzzleId idOf(TracksSpec spec, Difficulty difficulty, int index) =>
      TracksPuzzleId(spec, difficulty, index);

  SolvedPuzzle solved({int timeMs = 65000}) =>
      SolvedPuzzle(timeMs: timeMs, solvedAt: DateTime.utc(2026, 8, 1));

  /// A board of [id] that resumes: the fixed pieces and nothing else.
  TracksInProgress untouched(TracksPuzzleId id, {int elapsedMs = 1000}) {
    final puzzle = puzzleFor(id.value);
    return TracksInProgress(
      cells: [
        for (final mask in initialBoard(puzzle.clues)) mask.toRadixString(16),
      ].join(),
      elapsedMs: elapsedMs,
    );
  }

  SaveData saveWith(TracksProgress tracks) {
    final save = freshSave();
    return save.copyWith(
      profiles: [save.profiles.single.copyWith(tracks: tracks)],
    );
  }

  /// The whole app, opened on the Tracks menu.
  Future<ProviderContainer> openMenu(
    WidgetTester tester, {
    SaveData? save,
    FakeTracksPuzzleSource? source,
  }) async {
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: save ?? freshSave()),
      overrides: [
        tracksPuzzleSourceProvider.overrideWithValue(
          source ?? FakeTracksPuzzleSource(),
        ),
      ],
    );
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(AppRoutes.tracks),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> tapMenu(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
  }

  /// Taps [target] and waits for the board, with bounded pumps: the play
  /// screen's clock is a periodic timer, so settling would advance it.
  Future<void> tapAndPlay(WidgetTester tester, Finder target) async {
    await tapMenu(tester, target);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TracksBoard), findsOneWidget);
  }

  /// Takes the tree down with the repository flushed, so no timer is pending.
  Future<void> finish(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await repositoryOf(container).flush();
    await tester.pump(const Duration(seconds: 1));
  }

  Finder row(String label) => find.widgetWithText(ListTile, label);

  test('every size has a distinct glyph, and every tier a label', () {
    expect(
      tracksSizes.map(tracksSizeIcon).toSet(),
      hasLength(tracksSizes.length),
    );
    for (final spec in tracksSizes) {
      for (final difficulty in tracksDifficultiesFor(spec)) {
        expect(tracksTierLabel(spec, difficulty), startsWith(spec.label));
      }
    }
  });

  group('the size toggle and the rows', () {
    testWidgets('5x5 offers two rows, 7x7 and 9x9 three', (tester) async {
      await openMenu(tester);
      expect(find.byType(ListTile), findsNWidgets(2));
      expect(row('Hard'), findsNothing);

      await tapMenu(tester, find.text('7x7'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(row('Hard'), findsOneWidget);

      await tapMenu(tester, find.text('9x9'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(3));
    });

    testWidgets('a profile with no history opens on 5x5 and no Keep going', (
      tester,
    ) async {
      await openMenu(tester);

      expect(find.textContaining('Keep going'), findsNothing);
      expect(find.text('Not solved yet'), findsNWidgets(2));
    });

    testWidgets('a row shows the solved count and the best time', (
      tester,
    ) async {
      await openMenu(
        tester,
        save: saveWith(
          TracksProgress(
            solved: {
              idOf(TracksSpec.s5x5, Difficulty.easy, 0).value: solved(),
              idOf(TracksSpec.s5x5, Difficulty.easy, 1).value: solved(),
            },
            bestTimeMs: {
              TracksProgress.bestTimeKey(TracksSpec.s5x5, Difficulty.easy):
                  65000,
            },
          ),
        ),
      );

      // No `bestSolve` here, so the detail comes from the solved entry at the best
      // time (`PLAN-best-time-assists.md` §4.3).
      expect(find.textContaining('Solved 2 · Best 1:05'), findsOneWidget);
      expect(find.text('Not solved yet'), findsOneWidget);
    });

    testWidgets('a row shows what the best time cost', (tester) async {
      final key = TracksProgress.bestTimeKey(TracksSpec.s5x5, Difficulty.easy);
      await openMenu(
        tester,
        save: saveWith(
          TracksProgress(
            solved: {idOf(TracksSpec.s5x5, Difficulty.easy, 0).value: solved()},
            bestTimeMs: {key: 65000},
            bestSolve: {
              key: const SolvedPuzzle(timeMs: 65000, hints: 2, mistakes: 1),
            },
          ),
        ),
      );

      expect(
        find.text(
          tierProgressLabel(
            solved: 1,
            bestTimeMs: 65000,
            bestAssists: (hints: 2, mistakes: 1),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Solved 1 · Best 1:05 · 2 hints, 1 mistake'),
        findsOneWidget,
      );
    });

    testWidgets('a row launches the lowest unsolved index', (tester) async {
      final source = FakeTracksPuzzleSource();
      final container = await openMenu(
        tester,
        source: source,
        save: saveWith(
          TracksProgress(
            solved: {
              idOf(TracksSpec.s5x5, Difficulty.easy, 0).value: solved(),
              idOf(TracksSpec.s5x5, Difficulty.easy, 2).value: solved(),
            },
          ),
        ),
      );

      await tapAndPlay(tester, row('Easy'));

      expect(sessionOf(tester).id, idOf(TracksSpec.s5x5, Difficulty.easy, 1));
      await finish(tester, container);
    });
  });

  group('Keep going', () {
    testWidgets('appears with the tier it resumes, and launches that board', (
      tester,
    ) async {
      final id = idOf(TracksSpec.s7x7, Difficulty.easy, 3);
      final container = await openMenu(
        tester,
        save: saveWith(TracksProgress(inProgress: {id.value: untouched(id)})),
      );

      expect(find.text('Keep going: 7x7 Easy'), findsOneWidget);
      // The menu opens on the size the child left, too.
      expect(find.byType(ListTile), findsNWidgets(3));

      await tapAndPlay(tester, find.text('Keep going: 7x7 Easy'));

      expect(sessionOf(tester).id, id);
      await finish(tester, container);
    });
  });

  group('the theme picker', () {
    Finder pictureButton(String name) => find.bySemanticsLabel(name);

    testWidgets('offers all four themes, train selected', (tester) async {
      await openMenu(tester);

      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Train'), findsOneWidget);
      expect(find.text('Water'), findsOneWidget);
      expect(find.text('Santa'), findsOneWidget);
      expect(find.text('Snail'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TracksThemePicker),
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
    });

    testWidgets('each button is at least a primary tap target tall', (
      tester,
    ) async {
      await openMenu(tester);

      for (final name in ['Train', 'Santa', 'Snail', 'Water']) {
        final size = tester.getSize(
          find
              .ancestor(of: find.text(name), matching: find.byType(InkWell))
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(64));
      }
    });

    testWidgets('are announced as selectable buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await openMenu(tester);

      expect(
        tester.getSemantics(pictureButton('Train')),
        matchesSemantics(
          label: 'Train',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
          hasEnabledState: false,
          isFocusable: false,
        ),
      );
      handle.dispose();
    });

    testWidgets('tapping Water selects it and stores it', (tester) async {
      final container = await openMenu(tester);

      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();

      expect(
        repositoryOf(container).activeProfile.tracksTheme,
        TracksTheme.water,
      );
      expect(
        tester.getSemantics(pictureButton('Water')),
        matchesSemantics(
          label: 'Water',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          hasTapAction: true,
        ),
      );
      await finish(tester, container);
    });

    testWidgets('choosing water on one profile leaves another on the train', (
      tester,
    ) async {
      final container = await openMenu(tester);
      final repository = repositoryOf(container);
      final first = repository.activeProfile.id;
      final second = repository
          .createProfile(name: 'Bo', avatar: AvatarId.owl)
          .id;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Water'));
      await tester.pumpAndSettle();
      expect(repository.activeProfile.tracksTheme, TracksTheme.water);

      repository.selectProfile(first);
      await tester.pumpAndSettle();

      expect(repository.activeProfile.tracksTheme, TracksTheme.train);
      expect(
        repository.profiles.firstWhere((p) => p.id == second).tracksTheme,
        TracksTheme.water,
      );
      // The picker follows the profile: train is the checked card now.
      final checked = find.descendant(
        of: find.ancestor(
          of: find.text('Train'),
          matching: find.byType(InkWell),
        ),
        matching: find.byIcon(Icons.check_circle),
      );
      expect(checked, findsOneWidget);
      await finish(tester, container);
    });

    testWidgets(
      'choosing the snail on one profile leaves another on the train',
      (tester) async {
        final container = await openMenu(tester);
        final repository = repositoryOf(container);
        final first = repository.activeProfile.id;
        final second = repository
            .createProfile(name: 'Bo', avatar: AvatarId.owl)
            .id;
        await tester.pumpAndSettle();

        await tester.tap(find.text('Snail'));
        await tester.pumpAndSettle();
        expect(repository.activeProfile.tracksTheme, TracksTheme.snail);

        repository.selectProfile(first);
        await tester.pumpAndSettle();

        expect(repository.activeProfile.tracksTheme, TracksTheme.train);
        expect(
          repository.profiles.firstWhere((p) => p.id == second).tracksTheme,
          TracksTheme.snail,
        );
        await finish(tester, container);
      },
    );
  });

  group('pre-warming', () {
    testWidgets('warms exactly the id the first suggestion would launch', (
      tester,
    ) async {
      final source = FakeTracksPuzzleSource();
      final last = idOf(TracksSpec.s7x7, Difficulty.medium, 1);
      final container = await openMenu(
        tester,
        source: source,
        save: saveWith(
          TracksProgress(
            solved: {
              idOf(TracksSpec.s7x7, Difficulty.medium, 0).value: solved(),
            },
            inProgress: {last.value: untouched(last)},
          ),
        ),
      );

      expect(source.prewarms, [idOf(TracksSpec.s7x7, Difficulty.medium, 1)]);

      // Changing the size afterwards warms nothing more.
      await tapMenu(tester, find.text('9x9'));
      await tester.pumpAndSettle();
      expect(source.prewarms, hasLength(1));
      await finish(tester, container);
    });

    testWidgets('a fresh profile warms 5x5 Easy 0', (tester) async {
      final source = FakeTracksPuzzleSource();
      await openMenu(tester, source: source);

      expect(source.prewarms, [idOf(TracksSpec.s5x5, Difficulty.easy, 0)]);
    });
  });

  group('layout', () {
    /// The screen on its own, at [textScale], on a phone.
    Future<void> pumpScreen(
      WidgetTester tester, {
      required ThemeData theme,
      required double textScale,
    }) async {
      await usePhoneSurface(tester);
      final store = MemorySaveStore(initial: freshSave());
      final container = ProviderContainer(
        overrides: [
          saveStoreProvider.overrideWithValue(store),
          initialSaveProvider.overrideWithValue(await store.load()),
          tracksPuzzleSourceProvider.overrideWithValue(
            FakeTracksPuzzleSource(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: theme,
            debugShowCheckedModeBanner: false,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
            home: const TracksMenuScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    for (final entry in appThemes.entries) {
      testWidgets('${entry.key} at 200% text scale has no overflow', (
        tester,
      ) async {
        await pumpScreen(tester, theme: entry.value(), textScale: 2);

        expect(tester.takeException(), isNull);
        expect(find.text('Water'), findsOneWidget);
        expect(find.text('Easy'), findsOneWidget);
      });
    }
  });
}
