// Rewrites test/golden/*.golden from the generator as it is now.
//
//   cd packages/puzzle_engine && dart run tool/regen_goldens.dart
//
// Run it when a change to generation is meant to change output, never to make a
// red build green. There is no automated defence against the second — the
// control is that the diff names every puzzle that moved, and that the header
// line records which generatorVersion wrote them (`PLAN-phase-2.md` §4.8). A
// regeneration whose diff is not empty and whose header line is unchanged is
// exactly the change that needs `generator_version.dart` read before it is
// committed: after release, that means a version bump, the old generator kept
// reachable and a save migration in the same commit.
//
// It may use dart:io. The purity check reads lib/ only, and this is a
// development script rather than something the app ships.

import 'dart:io';

import 'package:puzzle_engine/src/generator_version.dart';

import '../test/combinations.dart';
import '../test/golden_format.dart';

void main(List<String> args) {
  if (args.isNotEmpty) {
    stderr.writeln('usage: dart run tool/regen_goldens.dart');
    exitCode = 64;
    return;
  }
  if (!Directory('test/golden').existsSync()) {
    stderr.writeln(
      'test/golden is not here: run this from packages/puzzle_engine.',
    );
    exitCode = 66;
    return;
  }

  stdout.writeln('Writing goldens at generatorVersion $generatorVersion.');
  var overWidened = false;

  for (final (spec, difficulty) in combinations) {
    final watch = Stopwatch()..start();
    final lines = goldenLinesFor(spec, difficulty);
    watch.stop();

    final path = goldenPathFor(spec, difficulty);
    File(path).writeAsStringSync('${lines.join('\n')}\n');

    final widened = widenedIn(lines);
    if (widened > maxWidenedPerGolden) overWidened = true;
    stdout.writeln(
      '  $path: ${lines.length - 1} puzzles, $widened widened, '
      '${watch.elapsed.inMilliseconds} ms',
    );
  }

  if (overWidened) {
    // Reported rather than thrown away: the files are still what the generator
    // produces, and the tests fail on them, which is the conversation this
    // number is meant to start.
    stderr.writeln(
      'More than $maxWidenedPerGolden puzzles in 100 were widened. The written '
      'files will fail determinism_test: a recipe that cannot be hit is a band '
      'to move with data (`PLAN.md` §3.4), not a limit to raise.',
    );
    exitCode = 1;
  }
}
