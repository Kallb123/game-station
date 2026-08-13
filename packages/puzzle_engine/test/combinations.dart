// The seven size-and-label pairs the engine builds, in one place because four
// files iterate them — the generator test, the goldens, the fuzz and the tool
// that writes the goldens. A second copy would let a combination be added to
// one list and missed by another, which is the failure a golden file exists to
// make loud rather than one to introduce here.

import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:puzzle_engine/src/technique_solver.dart';

/// Every size and label the engine builds.
///
/// 6x6 Expert is absent because it does not exist: `PLAN.md` §3.4 gives a 6x6
/// no room for a genuine T4, `PuzzleId.parse` refuses to spell it and
/// `recipeFor` throws for it.
const List<(SudokuSpec, Difficulty)> combinations = [
  (SudokuSpec.s9x9, Difficulty.easy),
  (SudokuSpec.s9x9, Difficulty.medium),
  (SudokuSpec.s9x9, Difficulty.hard),
  (SudokuSpec.s9x9, Difficulty.expert),
  (SudokuSpec.s6x6, Difficulty.easy),
  (SudokuSpec.s6x6, Difficulty.medium),
  (SudokuSpec.s6x6, Difficulty.hard),
];
