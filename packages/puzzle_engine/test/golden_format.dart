// The format of `test/golden/*.golden`, written once and used from both ends:
// `tool/regen_goldens.dart` writes the files and `determinism_test.dart`
// rebuilds them and compares. One copy of the format, because a writer and a
// reader that drift apart would agree with each other about a puzzle that had
// changed, which is the single thing these files exist to catch.

import 'package:puzzle_engine/src/generator.dart';
import 'package:puzzle_engine/src/generator_version.dart';
import 'package:puzzle_engine/src/puzzle_id.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:puzzle_engine/src/technique_solver.dart';

/// How many indices each golden file covers, counting from 0
/// (`PLAN-phase-2.md` §4.8).
const int goldenIndices = 100;

/// The most puzzles in one file that may have been widened.
///
/// Widening is the generator settling for the closest thing to what was asked
/// for, so a file full of widened puzzles is a size and label whose recipe is
/// not reachable — a game that is quietly easier than its label, which nobody
/// would notice from the app. `PLAN-phase-2.md` §7 makes it a red build
/// instead, to be answered by moving the band with data rather than by moving
/// this number.
const int maxWidenedPerGolden = 5;

/// What to run when a golden file no longer matches the generator.
const String regenerateHint =
    'run `dart run tool/regen_goldens.dart` from packages/puzzle_engine, and '
    'read generator_version.dart before you commit the result';

/// Where the golden for [spec] and [difficulty] lives, relative to the package
/// root — which is the directory `dart test` and `dart run` start in.
String goldenPathFor(SudokuSpec spec, Difficulty difficulty) =>
    'test/golden/sudoku_${spec.label}_${difficulty.name}.golden';

/// The first line of every golden file.
///
/// It records the version rather than describing the format because it is the
/// decision a regeneration has to make: output that changed under a version
/// that did not is either a bug or an unshipped generator being edited, and the
/// line is where a reviewer sees which.
String get goldenHeader => 'generatorVersion: $generatorVersion';

/// One puzzle as a golden line: `index clueCount tier widened clues`.
///
/// The clue string verbatim rather than a hash of it (`PLAN-phase-2.md` §3):
/// the file is bigger, and in exchange a failing diff names the puzzles that
/// changed instead of saying that something did.
///
/// [clueCount] and [tier] are derivable from [GeneratedPuzzle.clues] and so add
/// nothing a re-solve could not, but they are what a reviewer reads: a diff
/// that moves a puzzle from `hard` to `medium` says what happened, where two
/// changed rows of digits do not. The `ok`/`widened` field is the one fact
/// about a line that is not in the grid at all, and the widening count is
/// checked against [maxWidenedPerGolden].
String goldenLineFor(GeneratedPuzzle puzzle) =>
    '${puzzle.id.index} ${puzzle.clueCount} ${puzzle.tier.name} '
    '${puzzle.widened ? 'widened' : 'ok'} ${puzzle.clues}';

/// The whole of one golden file as lines, generated from scratch: the header
/// followed by indices 0 to [goldenIndices] - 1.
///
/// This is the expensive call in the engine's test suite — 100 puzzles per
/// combination, generated rather than read — and it is the price of comparing
/// what the generator does now against what it did when the file was written.
List<String> goldenLinesFor(SudokuSpec spec, Difficulty difficulty) => [
  goldenHeader,
  for (var index = 0; index < goldenIndices; index++)
    goldenLineFor(generateSudoku(PuzzleId(spec, difficulty, index))),
];

/// How many of [lines] record a widened puzzle.
int widenedIn(List<String> lines) =>
    lines.where((line) => line.contains(' widened ')).length;
