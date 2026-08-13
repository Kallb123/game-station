// The goldens: indices 0-99 of every size and label, frozen as text and
// compared against what the generator produces now.
//
// A save file stores a puzzle ID and throws the grid away (`PLAN.md` §5.2), so
// "the same ID gives the same grid" is a promise made to files written months
// ago on someone else's tablet. Two halves check it, and this file is the
// second:
//
// - Same ID, twice in one process — `generator_test.dart`'s "the same ID
//   produces the same puzzle, down to the attempt count". That catches state
//   left behind between calls.
// - Same ID, across processes and across releases — here. The expected output
//   was written by a different run of a different build, so anything that makes
//   generation depend on the toolchain, the platform or the day shows up as a
//   changed line.
//
// This is the slowest file in the suite: comparing means generating all 700
// puzzles. That is the cost of the promise, and `dart test test/<file>` still
// narrows to one file while iterating.
@Timeout(Duration(minutes: 10))
library;

import 'dart:io';

import 'package:puzzle_engine/src/generator_version.dart';
import 'package:test/test.dart';

import 'combinations.dart';
import 'golden_format.dart';

void main() {
  group('the golden files', () {
    for (final (spec, difficulty) in combinations) {
      test('${spec.label} ${difficulty.name} is unchanged', () {
        final path = goldenPathFor(spec, difficulty);
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: '$path is missing — $regenerateHint',
        );

        final stored = file.readAsLinesSync();
        final fresh = goldenLinesFor(spec, difficulty);

        // The header first, and on its own: a file written by another version
        // of the generator disagrees on every line, and "600 puzzles changed"
        // is a worse thing to read than the one sentence that explains it.
        expect(
          stored.first,
          goldenHeader,
          reason:
              '$path was written by a different generator version, and the '
              'engine is at $generatorVersion. Regenerating means deciding '
              'about the version — see lib/src/generator_version.dart.',
        );

        expect(
          stored.length,
          fresh.length,
          reason:
              '$path has ${stored.length - 1} puzzles, not '
              '${fresh.length - 1} — $regenerateHint',
        );

        // Named line by line rather than compared as a whole. `expect(stored,
        // fresh)` on 101 strings of 80-odd characters prints a wall nobody
        // reads, and which puzzles changed is the question a reviewer has.
        final changed = <int>[];
        for (
          var line = 1;
          line < stored.length && line < fresh.length;
          line++
        ) {
          if (stored[line] != fresh[line]) changed.add(line);
        }
        if (changed.isNotEmpty) {
          final listed = changed.take(10).map((line) => line - 1).join(', ');
          final rest = changed.length > 10
              ? ' and ${changed.length - 10} more'
              : '';
          fail(
            'the generator no longer produces $path.\n'
            '${changed.length} of $goldenIndices puzzles changed: $listed$rest.'
            '\nThe first of them:\n'
            '  golden: ${stored[changed.first]}\n'
            '  now:    ${fresh[changed.first]}\n'
            'If that is deliberate, $regenerateHint.',
          );
        }
      });
    }

    for (final (spec, difficulty) in combinations) {
      test('${spec.label} ${difficulty.name} is mostly what was asked for', () {
        // Read from the file rather than regenerated: the test above has
        // already established the two agree, and this way the check is on the
        // committed bytes a reviewer can count for themselves.
        final path = goldenPathFor(spec, difficulty);
        final widened = widenedIn(File(path).readAsLinesSync());
        expect(
          widened,
          lessThanOrEqualTo(maxWidenedPerGolden),
          reason:
              '$widened of $goldenIndices puzzles in $path were widened. The '
              'recipe for ${spec.label} ${difficulty.name} is not reachable '
              'often enough, so the fix is its band in generator.dart, decided '
              'with data (`PLAN.md` §3.4) — not this limit.',
        );
      });
    }
  });
}
