// The guard that keeps `HapticFeedback`'s permission-needing calls out of the
// app.
//
// `PLAN-phase-5.md` §3.5: `HapticFeedback.vibrate()` and `.heavyImpact()`
// reach Android's `Vibrator`, which needs `android.permission.VIBRATE` —
// adding a permission this app has never asked for. `core/haptics.dart`
// calls only `selectionClick`, `lightImpact` and `mediumImpact`, which route
// through `View.performHapticFeedback` and need none. Modelled on
// `no_recorder_test.dart` and `no_random_test.dart`, including their own
// self-tests: a scanner that silently found nothing would pass forever.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the scanner', () {
    test('finds a call to vibrate', () {
      expect(vibrateCallsIn('HapticFeedback.vibrate();'), 1);
    });

    test('finds a call to heavyImpact', () {
      expect(vibrateCallsIn('HapticFeedback.heavyImpact();'), 1);
    });

    test('ignores the three allowed calls', () {
      expect(vibrateCallsIn('HapticFeedback.selectionClick();'), 0);
      expect(vibrateCallsIn('HapticFeedback.lightImpact();'), 0);
      expect(vibrateCallsIn('HapticFeedback.mediumImpact();'), 0);
    });

    test('ignores a mention in a line comment', () {
      expect(vibrateCallsIn('// HapticFeedback.vibrate() is banned here.'), 0);
      expect(vibrateCallsIn('/// See HapticFeedback.heavyImpact().'), 0);
    });

    test('ignores a mention in a block comment', () {
      expect(
        vibrateCallsIn('/* HapticFeedback.vibrate()\n   over two lines */'),
        0,
      );
    });

    test('ignores a longer identifier that contains it', () {
      expect(vibrateCallsIn('MyHapticFeedback.vibrate();'), 0);
    });

    test('counts every match, not just the first', () {
      expect(
        vibrateCallsIn(
          'HapticFeedback.vibrate();\nHapticFeedback.heavyImpact();',
        ),
        2,
      );
    });
  });

  group('app/lib', () {
    test('never calls HapticFeedback.vibrate or .heavyImpact', () {
      final calls = <String, int>{};
      for (final file in _dartFilesIn(Directory('lib'))) {
        final found = vibrateCallsIn(file.readAsStringSync());
        if (found > 0) calls[_relativePath(file)] = found;
      }

      expect(calls, isEmpty);
    });
  });
}

/// How many times [source] calls `HapticFeedback.vibrate(` or
/// `HapticFeedback.heavyImpact(`, ignoring comments.
int vibrateCallsIn(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  return RegExp(
    r'(?<![\w$])HapticFeedback\.(vibrate|heavyImpact)\s*\(',
  ).allMatches(code).length;
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
