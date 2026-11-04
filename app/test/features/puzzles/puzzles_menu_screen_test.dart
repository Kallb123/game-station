// The Puzzles menu: two cards, each leading to its game's menu, and nothing
// else on the screen (PLAN-phase-9-tracks.md §4.14).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/puzzles/puzzles_menu_screen.dart';
import 'package:zibo_games/features/sudoku/data/providers.dart';
import 'package:zibo_games/features/sudoku/ui/sudoku_menu_screen.dart';
import 'package:zibo_games/features/tracks/data/providers.dart';
import 'package:zibo_games/features/tracks/model/tracks_difficulties.dart';
import 'package:zibo_games/features/tracks/ui/tracks_menu_screen.dart';

import '../../app_harness.dart';
import '../sudoku/puzzle_fixtures.dart';
import '../tracks/tracks_puzzle_fixtures.dart';

void main() {
  Future<void> openPuzzles(WidgetTester tester) async {
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [
        puzzleSourceProvider.overrideWithValue(FakePuzzleSource()),
        tracksPuzzleSourceProvider.overrideWithValue(FakeTracksPuzzleSource()),
      ],
    );
    await tester.tap(find.text(puzzlesMenuTitle));
    await tester.pumpAndSettle();
  }

  testWidgets('it offers Sudoku and Tracks, each with a picture', (
    tester,
  ) async {
    await openPuzzles(tester);

    expect(find.text(sudokuMenuTitle), findsOneWidget);
    expect(find.text(tracksMenuTitle), findsOneWidget);
    expect(find.byIcon(puzzlesSudokuIcon), findsOneWidget);
    expect(find.byIcon(puzzlesTracksIcon), findsOneWidget);
    expect(find.byType(FilledButton), findsNWidgets(2));
  });

  testWidgets('Sudoku opens the Sudoku menu', (tester) async {
    await openPuzzles(tester);

    await tester.tap(find.text(sudokuMenuTitle));
    await tester.pumpAndSettle();

    expect(find.byType(SudokuMenuScreen), findsOneWidget);
  });

  testWidgets('Tracks opens the Tracks menu', (tester) async {
    await openPuzzles(tester);

    await tester.tap(find.text(tracksMenuTitle));
    await tester.pumpAndSettle();

    expect(find.byType(TracksMenuScreen), findsOneWidget);
  });

  for (final entry in const {
    'portrait': Size(360, 640),
    'landscape': Size(640, 360),
  }.entries) {
    testWidgets('both cards are visible in ${entry.key}', (tester) async {
      tester.view.physicalSize = entry.value;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await openPuzzles(tester);

      for (final label in const [sudokuMenuTitle, tracksMenuTitle]) {
        final rect = tester.getRect(find.text(label));
        expect(rect.isEmpty, isFalse);
        expect(
          Offset.zero & entry.value,
          predicate<Rect>((screen) => screen.overlaps(rect)),
          reason: '$label is on screen',
        );
      }
    });
  }
}
