/// Deterministic Sudoku generation and solving for Zibo Games, and the
/// identity and encoding of its Tracks puzzles.
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
/// Tracks (`PLAN-phase-9-tracks.md`) follows the same rule: a puzzle is a
/// function of its [TracksPuzzleId], and [TracksClues] is the one-line form of
/// what the player sees.
///
/// ```dart
/// final puzzle = generateTracks(TracksPuzzleId.parse('tracks:7x7:medium:412'));
/// final hint = nextTracksStep(puzzle.clues, List.filled(49, 0));
/// ```
///
/// Four things are deliberately *not* exported. `Rng` and `fnv1a32` are the
/// frozen sequence itself, and freezing it is only meaningful if nothing
/// outside this package can start a different one — `Rng(DateTime.now())` in
/// the app does not compile because the type is not there to name.
/// `countSolutions`, its Tracks counterparts `countTracksSolutions` and
/// `solveTracks`, and `CandidateGrid` are how a puzzle is built and judged
/// rather than anything the app has a question for; the answers it wants are
/// already fields on [GeneratedPuzzle] and [TracksPuzzle].
library;

export 'src/difficulty.dart';
export 'src/generator.dart' show GeneratedPuzzle, generateSudoku;
export 'src/generator_version.dart';
export 'src/puzzle_id.dart';
export 'src/sudoku_board.dart';
export 'src/sudoku_spec.dart';
export 'src/technique_solver.dart';
export 'src/tracks/track_side.dart';
export 'src/tracks/tracks_clues.dart';
export 'src/tracks/tracks_deduction.dart' show TracksStep, nextTracksStep;
export 'src/tracks/tracks_generator.dart' show generateTracks;
export 'src/tracks/tracks_puzzle.dart';
export 'src/tracks/tracks_puzzle_id.dart';
export 'src/tracks/tracks_spec.dart';
