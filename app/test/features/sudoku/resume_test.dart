// Phase 3's done-criterion, as far as a widget test can carry it: a force-quit
// mid-puzzle restores the exact board, notes, timer and undo stack
// (`PLAN.md` §7, `PLAN-phase-3.md` §1).
//
// The second launch reads the save back out of a [MemorySaveStore], which holds
// it as encoded text: the board that comes up is built from characters the
// first run wrote, not from an object the two runs share. That is the whole
// point of the test — an in-memory hand-off would pass while the encoding was
// broken.
//
// The device half of the criterion — an actual force-quit on Android — is
// `PLAN-phase-3.md` §8's list and cannot be run here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/features/sudoku/data/providers.dart';
import 'package:game_station/features/sudoku/model/sudoku_session.dart';
import 'package:game_station/features/sudoku/ui/sudoku_grid_view.dart';
import 'package:game_station/features/sudoku/ui/sudoku_launcher_screen.dart';

import '../../app_harness.dart';
import 'puzzle_fixtures.dart';

void main() {
  testWidgets('a force-quit mid-puzzle brings the same board back', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: freshSave());
    final overrides = [
      puzzleSourceProvider.overrideWithValue(FakePuzzleSource()),
    ];

    await pumpApp(tester, store: store, overrides: overrides);
    await _openTheBoard(tester);

    final before = _boardOf(tester);
    final empty = emptyCells(before);

    // A digit, a digit the solution disagrees with, and a pencil mark: the
    // three things on a board that are not clues. The wrong one is deliberate —
    // a child's mistake has to come back as faithfully as their correct answer,
    // and a resume that quietly dropped it would hand out a clean star.
    await _enterDigit(
      tester,
      cell: empty[0],
      digit: _digitFor(empty[0], wrong: false),
    );
    await _enterDigit(
      tester,
      cell: empty[1],
      digit: _digitFor(empty[1], wrong: true),
    );
    await tester.tap(find.byTooltip('Pencil marks'));
    await tester.pump();
    await _enterDigit(tester, cell: empty[2], digit: 2);

    await tester.pump(const Duration(seconds: 7));
    expect(before.elapsed, const Duration(seconds: 7));
    expect(before.mistakes, 1, reason: 'the wrong digit was counted');

    _forceQuit(tester);
    await tester.pump();
    expect(store.writes, greaterThan(0), reason: 'the pause wrote the board');

    // The relaunch. Same store, nothing else carried over.
    //
    // The app is brought back to `resumed` first, which is not ceremony: a
    // relaunch is a new process and a new process starts resumed, and the test
    // binding draws no frames while the app is paused — so a `pumpWidget` here
    // would quietly do nothing and the assertions below would all be made
    // against the first run's own screen.
    _comeBack(tester);
    await pumpApp(tester, store: store, overrides: overrides);
    await _openTheBoard(tester);
    final after = _boardOf(tester);

    expect(identical(after, before), isFalse);
    for (var index = 0; index < before.spec.cells; index++) {
      expect(
        after.digitAt(index),
        before.digitAt(index),
        reason: 'cell $index',
      );
      expect(
        after.notesAt(index),
        before.notesAt(index),
        reason: 'pencil marks on cell $index',
      );
      expect(
        after.isGiven(index),
        before.isGiven(index),
        reason: 'the clues of cell $index',
      );
    }
    expect(after.elapsed, before.elapsed);
    expect(after.mistakes, before.mistakes);
    // Everything stored, in one comparison, so a field added to
    // `PuzzleInProgress` later is covered by this test without being named in
    // it.
    expect(after.toSaved(), before.toSaved());

    // And the undo stack works, rather than merely having the right length: a
    // restored stack of entries that restore nothing would pass every check
    // above.
    after.undo();
    expect(after.notesAt(empty[2]), 0);
  });
}

/// Home, then the temporary launcher, then the board.
///
/// Explicit pumps rather than `pumpAndSettle`: the clock on the play screen is
/// a periodic timer, and settling would advance it by however long the route
/// transition happened to take. 400 ms is past the transition and short of the
/// first tick.
Future<void> _openTheBoard(WidgetTester tester) async {
  await tester.tap(find.text('Sudoku'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(launcherLabel));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(find.byType(SudokuGridView), findsOneWidget);
}

/// The app going away the way a child makes it go away.
///
/// Every step of the transition, because `AppLifecycleListener` asserts on one
/// that skips a step — and because `paused` is the last callback Android
/// guarantees before the process can be killed (`app.dart`).
void _forceQuit(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
}

/// The app running again, which a launch is.
void _comeBack(WidgetTester tester) {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

SudokuSession _boardOf(WidgetTester tester) =>
    tester.widget<SudokuGridView>(find.byType(SudokuGridView)).session;

/// A digit for [cell] of the launcher's puzzle that the solution disagrees
/// with when [wrong] is set, and the one it agrees with when it is not.
///
/// Asked of a throwaway session over the same fixture rather than guessed: the
/// board is whatever the generator makes of `sudoku:6x6:easy:0`, so a hardcoded
/// digit would be right today and wrong after a `generatorVersion` bump —
/// which is the difference between this test counting one mistake and two.
int _digitFor(int cell, {required bool wrong}) {
  final scratch = fixtureSession(launcherPuzzle)..select(cell);
  for (var digit = 1; digit <= scratch.spec.digits; digit++) {
    scratch.enter(digit);
    if (scratch.isWrong(cell) == wrong) return digit;
  }
  throw StateError('cell $cell takes no ${wrong ? 'wrong' : 'right'} digit');
}

/// Taps [cell] and then [digit], as a child does it.
///
/// By key rather than by position in the tree: the grid keys every cell with
/// its index (`sudoku_grid_view.dart`), so this cannot drift if the board is
/// ever laid out in another order.
Future<void> _enterDigit(
  WidgetTester tester, {
  required int cell,
  required int digit,
}) async {
  await tester.tap(find.byKey(ValueKey<int>(cell)));
  await tester.pump();
  await tester.tap(find.widgetWithText(FilledButton, '$digit'));
  await tester.pump();
}
