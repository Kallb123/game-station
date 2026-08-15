/// Deterministic Sudoku generation and solving for Zibo Games.
///
/// Every puzzle is a pure function of its ID, so the same ID yields the same
/// grid on every platform, in every release, with nothing stored and nothing
/// fetched. Saved progress records puzzle IDs rather than grids, so that
/// property is load-bearing rather than a nicety — see `PLAN.md` §3.1.
///
/// ```dart
/// final puzzle = generateSudoku(PuzzleId.parse('sudoku:9x9:hard:412'));
/// final board = SudokuBoard.fromClues(puzzle.id.spec, puzzle.clues);
/// final hint = nextStep(board);
/// ```
///
/// This package deliberately imports neither Flutter nor `dart:io`: it is
/// data in, data out, which keeps its tests fast enough to fuzz thousands of
/// seeds per run.
///
/// Four things are deliberately *not* exported. `Rng` and `fnv1a32` are the
/// frozen sequence itself, and freezing it is only meaningful if nothing
/// outside this package can start a different one — `Rng(DateTime.now())` in
/// the app does not compile because the type is not there to name.
/// `countSolutions` and `CandidateGrid` are how a puzzle is built and judged
/// rather than anything the app has a question for; the answers it wants are
/// already fields on [GeneratedPuzzle].
library;

export 'src/difficulty.dart';
export 'src/generator.dart' show GeneratedPuzzle, generateSudoku;
export 'src/generator_version.dart';
export 'src/puzzle_id.dart';
export 'src/sudoku_board.dart';
export 'src/sudoku_spec.dart';
export 'src/technique_solver.dart';
