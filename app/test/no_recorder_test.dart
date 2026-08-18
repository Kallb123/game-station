// The guard that keeps `minisound`'s recorder out of the app.
//
// `PLAN-phase-5.md` §1: nothing in the app can record. The manifest removal
// in `AndroidManifest.xml` is the platform half of that promise; this is the
// source half, so reaching for the recorder API fails a test before it ever
// reaches the manifest. Modelled on `no_random_test.dart`, including its own
// self-tests: a scanner that silently found nothing would pass forever.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the scanner', () {
    test('finds an import of the recorder', () {
      expect(
        recorderImportsIn("import 'package:minisound/recorder_flutter.dart';"),
        1,
      );
    });

    test('finds an import of a rec.dart file', () {
      expect(
        recorderImportsIn(
          "import 'package:minisound_platform_interface/src/rec.dart';",
        ),
        1,
      );
    });

    test('ignores the player import', () {
      expect(
        recorderImportsIn("import 'package:minisound/player_flutter.dart';"),
        0,
      );
    });

    test('ignores a mention in a comment', () {
      expect(
        recorderImportsIn(
          "// import 'package:minisound/recorder_flutter.dart';",
        ),
        0,
      );
    });

    test('ignores an unrelated package', () {
      expect(recorderImportsIn("import 'package:path/path.dart';"), 0);
    });

    test('counts every match, not just the first', () {
      expect(
        recorderImportsIn(
          "import 'package:minisound/recorder_flutter.dart';\n"
          "import 'package:minisound_platform_interface/src/rec.dart';",
        ),
        2,
      );
    });
  });

  group('app/lib', () {
    test('never imports the recorder', () {
      final hits = <String, int>{};
      for (final file in _dartFilesIn(Directory('lib'))) {
        final found = recorderImportsIn(file.readAsStringSync());
        if (found > 0) hits[_relativePath(file)] = found;
      }

      expect(hits, isEmpty);
    });
  });
}

/// How many import directives in [source] name `minisound`'s recorder,
/// ignoring comments.
///
/// Matched on the import URI containing `recorder` or ending in `rec.dart`,
/// rather than a fixed path: the platform-interface and per-platform
/// implementation packages each carry their own copy of the recorder under a
/// different path, and the point is banning the API, not one file that
/// exposes it.
int recorderImportsIn(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');

  var count = 0;
  for (final match in RegExp(
    r'''import\s+['"]([^'"]+)['"]''',
  ).allMatches(code)) {
    final uri = match.group(1)!;
    if (!uri.contains('minisound')) continue;
    if (uri.contains('recorder') || uri.endsWith('rec.dart')) count++;
  }
  return count;
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
