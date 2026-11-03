// PR 7's done-criterion, as far as a widget test can carry it: a force-quit
// mid-puzzle restores the exact board, marks and clock (`PLAN-phase-9-tracks.md`
// §6, PR 7).
//
// Modelled on `sudoku/resume_test.dart`: the second launch reads the save back
// out of a [MemorySaveStore], which holds it as encoded text, so the board that
// comes up is built from characters the first run wrote and not from an object
// the two runs share. The device half — an actual force-quit on Android — is
// not something this can run.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_store.dart';

import '../../app_harness.dart';
import 'tracks_fixtures.dart';
import 'ui/tracks_play_harness.dart';

void main() {
  testWidgets('a force-quit mid-puzzle brings the same board back', (
    tester,
  ) async {
    final fixture = _partialFixture();
    final puzzle = fixture.puzzle;
    final spec = puzzle.id.spec;
    final laid = fixture.found.laid;
    final wrong = fixture.found.wrong;

    final store = MemorySaveStore(initial: freshSave());
    await pumpTracks(tester, id: puzzle.id, store: store);
    final before = sessionOf(tester);

    // Part of the solution, a mark and a wrong connection: the three things on
    // a board that a resume could drop. The wrong one is deliberate: a child's
    // mistake has to come back as faithfully as their right answer, and a
    // resume that quietly forgot it would hand out a clean star.
    await drag(tester, laid);
    final marked = [
      for (var cell = 0; cell < spec.cells; cell++)
        if (before.maskAt(cell) == 0 && !wrong.touches.contains(cell)) cell,
    ].first;
    await tapCell(tester, marked);
    await drag(tester, wrong.stroke);
    await tester.pump(const Duration(seconds: 7));

    expect(before.isMarked(marked), isTrue);
    expect(before.elapsed, const Duration(seconds: 7));
    expect(before.mistakes, greaterThan(0), reason: 'the wrong connection');

    final cells = [...before.cells];
    final marks = [for (var i = 0; i < spec.cells; i++) before.isMarked(i)];
    final saved = before.toSaved();
    final elapsed = before.elapsed;

    _forceQuit(tester);
    await tester.pump();
    expect(store.writes, greaterThan(0), reason: 'the pause wrote the board');

    // The relaunch: same store, nothing else carried over. Brought back to
    // `resumed` first because a new process starts resumed, and the test binding
    // draws no frames while the app is paused.
    _comeBack(tester);
    await pumpTracks(tester, id: puzzle.id, store: store);
    final after = sessionOf(tester);

    expect(identical(after, before), isFalse);
    expect(after.cells, cells);
    for (var cell = 0; cell < spec.cells; cell++) {
      expect(after.isMarked(cell), marks[cell], reason: 'mark on cell $cell');
    }
    expect(after.elapsed, elapsed);
    // Everything stored, in one comparison, so a field added to
    // `TracksInProgress` later is covered without being named here.
    expect(after.toSaved(), saved);

    // The undo stack works rather than merely having the right length.
    final restored = snapshotOf(after);
    after.undo();
    expect(snapshotOf(after).cells, isNot(restored.cells));
  });
}

typedef _Plan = ({
  List<Position> laid,
  ({List<Position> stroke, Set<int> touches}) wrong,
});

/// A puzzle where a stroke over the first free cells of the solution leaves the
/// board unsolved, and a wrong connection can be laid after it.
///
/// Searched for rather than hard-coded, and not every puzzle qualifies: Easy
/// boards carry so many fixed pieces that a short stroke can finish one
/// (`5x5:easy:0` is such a puzzle), and a half-played board is the whole
/// subject here.
({TracksPuzzle puzzle, _Plan found}) _partialFixture() => findPuzzle<_Plan>((
  puzzle,
) {
  final spec = puzzle.id.spec;
  final path = solutionPath(puzzle);
  final free = [
    for (var i = 0; i < path.length; i++)
      if (puzzle.clues.fixed[path[i]] == 0) i,
  ];
  if (free.length < 3) return null;
  final laid = [
    solutionStroke(puzzle).first,
    for (final cell in path.take(free[1] + 1)) positionOf(spec, cell),
  ];
  final scratch = startSession(puzzle);
  stroke(scratch, laid);
  if (scratch.isSolved) return null;

  // Any cell may anchor the wrong connection: fixed pieces already hold two
  // connections and refuse a third, so the first cell that works is found by
  // trying.
  for (var from = 0; from < spec.cells; from++) {
    for (final neighbour in neighboursOf(spec, from)) {
      final trial = startSession(puzzle);
      stroke(trial, laid);
      final target = positionOf(spec, neighbour.cell);
      stroke(trial, [positionOf(spec, from), target]);
      if (trial.mistakes > 0 && !trial.isSolved) {
        return (
          laid: laid,
          wrong: (
            stroke: [positionOf(spec, from), target],
            touches: {from, neighbour.cell},
          ),
        );
      }
    }
  }
  return null;
});

/// The app going away the way a child makes it go away: every step of the
/// transition, because `AppLifecycleListener` asserts on one that skips a step.
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
