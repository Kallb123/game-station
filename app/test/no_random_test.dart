// The guard that keeps `dart:math`'s `Random` out of the app.
//
// `PLAN-phase-1.md` §1 already asked for this — no ambient randomness in
// `lib/`, so a run replays from its seed — but until `PLAN-phase-4.md` §4.3
// nothing enforced it beyond a sentence nobody could fail a build against.
// Invaders is the first place a `Random()` would even compile: `GameRng`
// exists precisely so nothing needs one (`game_rng.dart`), and this scanner is
// what turns "please don't" into a red build if someone reaches for the
// built-in instead.
//
// Modelled on `features/sudoku/data/generation_call_site_test.dart`, including
// its own self-tests: a scanner that silently found nothing would pass
// forever, so it is exercised against sources that do and do not match before
// it is trusted against `app/lib`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the scanner', () {
    test('finds a bare call', () {
      expect(randomCallsIn('final r = Random();'), 1);
    });

    test('finds a seeded call', () {
      expect(randomCallsIn('final r = Random(seed);'), 1);
    });

    test('finds a call that is not the first thing on its line', () {
      expect(randomCallsIn('  final x = 1 + Random().nextInt(6);'), 1);
    });

    test('ignores a mention in a line comment', () {
      expect(randomCallsIn('// do not use Random() here.'), 0);
      expect(randomCallsIn('/// See Random() for why this exists.'), 0);
      expect(randomCallsIn('final x = 1; // Random()'), 0);
    });

    test('ignores a mention in a block comment', () {
      expect(randomCallsIn('/* Random()\n   over two lines */'), 0);
    });

    test('ignores a longer identifier that contains it', () {
      expect(randomCallsIn('SecureRandom();'), 0);
      expect(randomCallsIn('_RandomThing();'), 0);
      expect(randomCallsIn('GameRng(seed);'), 0);
    });

    test('counts every call, not just the first', () {
      expect(randomCallsIn('Random();\nRandom();'), 2);
    });
  });

  group('app/lib', () {
    test('never calls Random(', () {
      final calls = <String, int>{};
      for (final file in _dartFilesIn(Directory('lib'))) {
        final found = randomCallsIn(file.readAsStringSync());
        if (found > 0) calls[_relativePath(file)] = found;
      }

      expect(calls, isEmpty);
    });
  });
}

/// How many times [source] calls `Random(`, ignoring comments.
///
/// Comments are stripped rather than parsed, as the generation scanner strips
/// them: the file that would call `Random` is also the file that would explain
/// why, and prose is not a call site.
int randomCallsIn(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  return RegExp(r'(?<![\w$])Random\s*\(').allMatches(code).length;
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
