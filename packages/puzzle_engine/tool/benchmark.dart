// Measures what generation costs, against `PLAN.md` §3.5's targets.
//
//   cd packages/puzzle_engine && dart run tool/benchmark.dart
//
// Prints p50, p95 and max per size and difficulty, and exits non-zero when a
// median is above three times its target. The ceiling is loose on purpose
// (`PLAN-phase-2.md` §4.9): a shared CI runner varies by more than a factor of
// two, and an assertion that goes red when the runner is busy is an assertion
// somebody deletes. What it is here to catch is an order-of-magnitude
// regression — an accidental extra uniqueness check per hole, a technique that
// rescans the grid — which no amount of runner noise produces.
//
// The median is what the ceiling applies to, not the max: one slow puzzle in
// fifty is a property of Sudoku rather than of this code, and the tail already
// has its own guard, which is the fuzz's 2 s per-puzzle ceiling over 2000
// puzzles. p95 and max are printed because a tail that moves is worth a human
// noticing even when it is not worth failing a build over.
//
// It may use dart:io. The purity check reads lib/ only, and nothing the app
// ships imports this.

import 'dart:io';

import 'package:puzzle_engine/src/generator.dart';
import 'package:puzzle_engine/src/generator_version.dart';
import 'package:puzzle_engine/src/puzzle_id.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:puzzle_engine/src/technique_solver.dart';

import '../test/combinations.dart';

/// How many puzzles to time per size and difficulty (`PLAN-phase-2.md` §4.9).
const int benchmarkCount = 50;

/// How many multiples of the target a median may reach before this fails.
const int ceilingFactor = 3;

/// How many puzzles to generate per combination before timing starts.
///
/// The VM compiles a method properly only once it has run a few times, so
/// without this the first puzzle of each combination is ten to twenty times its
/// own median and lands in the `max` column, which is the column somebody reads
/// to decide whether the tail moved.
const int warmUpCount = 3;

/// Where the warm-up takes its indices from.
///
/// Above anything the timed run or the goldens use, so warming up cannot be
/// confused with measuring a puzzle that was already generated.
const int warmUpFrom = 100000;

/// What `PLAN.md` §3.5 asks of one call to `generateSudoku`, in milliseconds.
///
/// A switch rather than a table, for the same reason `recipeFor` is one: a map
/// keyed by size and label is a map that can be missing a key, and this has to
/// answer for all seven combinations or the benchmark quietly measures six.
int targetMsFor(SudokuSpec spec, Difficulty difficulty) {
  if (spec == SudokuSpec.s6x6) return 30;
  return switch (difficulty) {
    Difficulty.easy || Difficulty.medium => 100,
    Difficulty.hard || Difficulty.expert => 400,
  };
}

void main(List<String> args) {
  if (args.isNotEmpty) {
    stderr.writeln('usage: dart run tool/benchmark.dart');
    exitCode = 64;
    return;
  }

  stdout.writeln(
    '$benchmarkCount puzzles per combination at generatorVersion '
    '$generatorVersion, on Dart ${Platform.version.split(' ').first}.',
  );
  stdout.writeln(
    'The ceiling is ${ceilingFactor}x the PLAN.md §3.5 target, applied to the '
    'median.\n',
  );
  stdout.writeln(
    '${'combination'.padRight(14)}${'p50'.padLeft(9)}${'p95'.padLeft(9)}'
    '${'max'.padLeft(9)}${'target'.padLeft(9)}${'ceiling'.padLeft(9)}  verdict',
  );

  final over = <String>[];
  for (final (spec, difficulty) in combinations) {
    final name = '${spec.label} ${difficulty.name}';
    final target = targetMsFor(spec, difficulty);
    final ceiling = target * ceilingFactor;

    for (var i = 0; i < warmUpCount; i++) {
      generateSudoku(PuzzleId(spec, difficulty, warmUpFrom + i));
    }

    final times = <int>[];
    for (var index = 0; index < benchmarkCount; index++) {
      final watch = Stopwatch()..start();
      generateSudoku(PuzzleId(spec, difficulty, index));
      watch.stop();
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();

    final p50 = _percentile(times, 50);
    final failed = p50 > ceiling * 1000;
    if (failed) {
      over.add('$name at ${_ms(p50)} against a $ceiling ms ceiling');
    }

    stdout.writeln(
      '${name.padRight(14)}${_ms(p50).padLeft(9)}'
      '${_ms(_percentile(times, 95)).padLeft(9)}${_ms(times.last).padLeft(9)}'
      '${'$target ms'.padLeft(9)}${'$ceiling ms'.padLeft(9)}'
      '  ${failed ? 'OVER' : 'ok'}',
    );
  }

  if (over.isEmpty) return;
  stderr.writeln(
    '\nGeneration is more than $ceilingFactor times slower than PLAN.md §3.5 '
    'asks for: ${over.join('; ')}.',
  );
  exitCode = 1;
}

/// The [percentile]th of [sorted], which must be sorted and non-empty.
///
/// Nearest-rank, so the answer is always a measurement that was taken rather
/// than an interpolation between two of them.
int _percentile(List<int> sorted, int percentile) =>
    sorted[((sorted.length * percentile) ~/ 100).clamp(0, sorted.length - 1)];

/// Microseconds as milliseconds, to one decimal place.
String _ms(int microseconds) => '${(microseconds / 1000).toStringAsFixed(1)}ms';
