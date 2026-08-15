// The rule that keeps the picker inside what the engine will build.
//
// The menu imports the same function this file does, so a difficulty offered on
// screen and a difficulty asserted here cannot be two different lists
// (`PLAN-phase-3.md` §5).

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/features/sudoku/model/difficulties.dart';

void main() {
  test('every size and difficulty the menu offers spells a puzzle id', () {
    // `PuzzleId.parse` is the engine's own gate on the combinations it builds:
    // it refuses 6x6 Expert by name, and `generateSudoku` throws for the same
    // pair. A menu that could offer a puzzle this rejects would put that
    // exception in front of a child.
    for (final spec in sudokuSizes) {
      for (final difficulty in difficultiesFor(spec)) {
        final id = PuzzleId(spec, difficulty, 0);
        expect(PuzzleId.parse(id.value), id, reason: id.value);
      }
    }
  });

  test('6x6 stops at Hard', () {
    expect(difficultiesFor(SudokuSpec.s6x6), [
      Difficulty.easy,
      Difficulty.medium,
      Difficulty.hard,
    ]);
  });

  test('9x9 offers Expert, last', () {
    // Offered rather than hidden (`PLAN-phase-3.md` §4.7), and last, so a child
    // reaches it by walking past three easier tiers rather than by accident.
    expect(difficultiesFor(SudokuSpec.s9x9), Difficulty.values);
    expect(difficultiesFor(SudokuSpec.s9x9).last, Difficulty.expert);
  });

  test('both sizes are offered, 9x9 first', () {
    expect(sudokuSizes, [SudokuSpec.s9x9, SudokuSpec.s6x6]);
    expect(defaultSudokuSpec, SudokuSpec.s9x9);
    expect(difficultiesFor(defaultSudokuSpec).first, defaultSudokuDifficulty);
  });
}
