// The size-and-label pairs the engine builds, in one place because four
// files iterate them — the generator test, the goldens, the fuzz and the tool
// that writes the goldens. A second copy would let a combination be added to
// one list and missed by another, which is the failure a golden file exists to
// make loud rather than one to introduce here.

import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:puzzle_engine/src/technique_solver.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';

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

/// Every Tracks size and label the engine builds, in the order the fuzz deals
/// them and the goldens are written.
///
/// 5x5 Hard is absent because it is not offered: PR 3 measured it reaching Hard
/// only with one or two of about fourteen pieces fixed
/// (`PLAN-phase-9-tracks.md` §4.1), `TracksPuzzleId.parse` refuses to spell it
/// and `tracksRecipeFor` throws for it. Expert is absent for every size.
const List<(TracksSpec, Difficulty)> tracksCombinations = [
  (TracksSpec.s5x5, Difficulty.easy),
  (TracksSpec.s5x5, Difficulty.medium),
  (TracksSpec.s7x7, Difficulty.easy),
  (TracksSpec.s7x7, Difficulty.medium),
  (TracksSpec.s7x7, Difficulty.hard),
  (TracksSpec.s9x9, Difficulty.easy),
  (TracksSpec.s9x9, Difficulty.medium),
  (TracksSpec.s9x9, Difficulty.hard),
];
