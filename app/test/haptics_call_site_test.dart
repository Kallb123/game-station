// The guard that keeps `HapticFeedback` behind `AppHaptics`.
//
// PR 5 first shipped a narrower scanner banning `HapticFeedback.vibrate(` and
// `.heavyImpact(` alone, on the belief that those two needed
// `android.permission.VIBRATE`. They do not — every one of `HapticFeedback`'s
// six methods routes through `View.performHapticFeedback`
// (`core/haptics.dart`'s header names the engine source that settled it) —
// so that ban protected nothing real. The guard that does: a call to
// `HapticFeedback` from anywhere but `core/haptics.dart` skips both the
// `AppSettings.hapticsLevel` mute and the [deviceCanVibrate] platform gate,
// which is what actually matters. Modelled on
// `features/sudoku/data/generation_call_site_test.dart`, including its own
// self-tests: a scanner that silently found nothing would pass forever.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to name `HapticFeedback`.
const String hapticsWrapper = 'lib/core/haptics.dart';

void main() {
  group('the scanner', () {
    test('finds a call', () {
      expect(referencesIn('HapticFeedback.selectionClick();'), 1);
    });

    test('finds a tear-off with no call at all', () {
      // `SystemHaptics._ladder` stores these as values, not calls — the
      // reference itself is the thing this guard cares about.
      expect(referencesIn('const f = HapticFeedback.selectionClick;'), 1);
    });

    test('ignores a mention in a line comment', () {
      expect(referencesIn('// HapticFeedback.vibrate() is banned here.'), 0);
      expect(referencesIn('/// See HapticFeedback.heavyImpact().'), 0);
    });

    test('ignores a mention in a block comment', () {
      expect(
        referencesIn('/* HapticFeedback.vibrate()\n   over two lines */'),
        0,
      );
    });

    test('ignores a longer identifier that contains it', () {
      expect(referencesIn('MyHapticFeedback.selectionClick();'), 0);
    });

    test('counts every match, not just the first', () {
      expect(
        referencesIn(
          'HapticFeedback.lightImpact();\nHapticFeedback.heavyImpact();',
        ),
        2,
      );
    });
  });

  group('app/lib', () {
    test('names HapticFeedback only from core/haptics.dart', () {
      final references = <String, int>{};
      for (final file in _dartFilesIn(Directory('lib'))) {
        final found = referencesIn(file.readAsStringSync());
        if (found > 0) references[_relativePath(file)] = found;
      }

      // Four: one per rung of the ladder — selectionClick, lightImpact,
      // mediumImpact, heavyImpact.
      expect(references, {hapticsWrapper: 4});
    });
  });
}

/// How many times [source] names a `HapticFeedback` member, called or torn
/// off, ignoring comments.
int referencesIn(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  return RegExp(r'(?<![\w$])HapticFeedback\.\w+').allMatches(code).length;
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
