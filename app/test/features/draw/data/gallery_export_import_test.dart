// The guard that keeps `package:gal` inside its own wrapper.
//
// `GalGalleryExport` in `gallery_export.dart` is the only place
// `PLAN-phase-8.md` §4.6 allows `package:gal` to be imported from: a plugin
// call that leaked into a widget is a call `flutter test` cannot run, the
// same reason `MinisoundAudio` is the only importer of `package:minisound`
// (`core/audio/app_audio.dart`'s own header).
//
// Modelled on `no_random_test.dart`, including its own self-tests: a scanner
// that silently found nothing would pass forever, so it is exercised against
// sources that do and do not match before it is trusted against `app/lib`.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The one file allowed to import `package:gal`.
const String _allowedImporter = 'lib/features/draw/data/gallery_export.dart';

void main() {
  group('the scanner', () {
    test('finds a plain import', () {
      expect(importsGal("import 'package:gal/gal.dart';"), true);
    });

    test('finds an import with a show clause', () {
      expect(importsGal("import 'package:gal/gal.dart' show Gal;"), true);
    });

    test('finds an import that is not the first thing on its line', () {
      expect(importsGal("  import 'package:gal/gal.dart';"), true);
    });

    test('ignores a mention in a line comment', () {
      expect(importsGal("// import 'package:gal/gal.dart';"), false);
      expect(importsGal('/// see package:gal/gal.dart for the API'), false);
    });

    test('ignores a mention in a block comment', () {
      expect(
        importsGal("/* import 'package:gal/gal.dart';\n over two lines */"),
        false,
      );
    });

    test('ignores an unrelated package whose name contains gal', () {
      expect(importsGal("import 'package:frugal/frugal.dart';"), false);
    });
  });

  group('app/lib', () {
    test('imports package:gal from gallery_export.dart alone', () {
      final offenders = <String>[];
      for (final file in _dartFilesIn(Directory('lib'))) {
        final path = _relativePath(file);
        if (path == _allowedImporter) continue;
        if (importsGal(file.readAsStringSync())) offenders.add(path);
      }

      expect(offenders, isEmpty);
    });

    test('gallery_export.dart does import it', () {
      final file = File(_allowedImporter);
      expect(file.existsSync(), isTrue, reason: '$_allowedImporter is missing');
      expect(importsGal(file.readAsStringSync()), isTrue);
    });
  });
}

/// Whether [source] imports `package:gal`, ignoring comments.
///
/// Comments are stripped rather than parsed, as the offline check's own
/// scanner does: the file explaining why `package:gal` stays out is not
/// itself an import of it.
bool importsGal(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  return RegExp(r'''import\s+['"]package:gal/''').hasMatch(code);
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
