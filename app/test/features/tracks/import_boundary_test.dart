// The guard that keeps the Tracks model free of anything that draws.
//
// The load-bearing decision of `PLAN-phase-9-tracks.md` §3 is that the theme
// is a presentation skin over one puzzle: the engine, the puzzle ID,
// `TracksSession` and the solved-puzzle records are theme-free, so switching
// skins mid-puzzle is the same puzzle and a child's solved list is not split
// by skin. §4.7 puts the session in `features/tracks/model/` as pure Dart for
// that reason. What would break it is a model file that reaches into the
// skins, the widgets, or any Flutter library that knows about painting, and
// that import is easy to add "just for a colour" and hard to notice in review.
// So the boundary is a test, not a comment.
//
// What the model may import: `package:flutter/foundation.dart` (for
// `ChangeNotifier`), `package:puzzle_engine`, `core/storage/save_data.dart`,
// and its own siblings. Nothing else from Flutter, never `dart:ui`, and never
// the tracks feature's `skins/` or `ui/`.
//
// It is textual, so it can be evaded on purpose; the same shape of check in
// `generation_call_site_test.dart` has caught the same shape of mistake. Being
// a guard, it has its own tests, including one against a deliberately broken
// copy of the real directory: a scanner that silently found nothing would
// pass forever (`AGENTS.md`, "A guard needs its own test").

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The only Flutter library the model may import.
const String _allowedFlutterLibrary = 'package:flutter/foundation.dart';

/// The tracks feature as a package URI prefix.
const String _tracksPackagePrefix = 'package:zibo_games/features/tracks/';

/// Directories of the tracks feature that the model must not reach.
const Set<String> _forbiddenDirectories = {'skins', 'ui'};

void main() {
  group('the scanner', () {
    test('finds a relative import of skins', () {
      expect(offendingUrisIn("import '../skins/track_skin.dart';"), [
        '../skins/track_skin.dart',
      ]);
      expect(offendingUrisIn("import 'skins/track_skin.dart';"), [
        'skins/track_skin.dart',
      ]);
    });

    test('finds a relative import of ui', () {
      expect(offendingUrisIn("import '../ui/play_screen.dart';"), [
        '../ui/play_screen.dart',
      ]);
    });

    test('finds a package import of the tracks skins and ui', () {
      expect(
        offendingUrisIn(
          "import 'package:zibo_games/features/tracks/skins/water.dart';\n"
          'import "package:zibo_games/features/tracks/ui/board.dart";',
        ),
        [
          'package:zibo_games/features/tracks/skins/water.dart',
          'package:zibo_games/features/tracks/ui/board.dart',
        ],
      );
    });

    test('finds dart:ui', () {
      expect(offendingUrisIn("import 'dart:ui';"), ['dart:ui']);
      expect(offendingUrisIn("import 'dart:ui' show Color;"), ['dart:ui']);
    });

    test('finds a Flutter library other than foundation', () {
      expect(
        offendingUrisIn(
          "import 'package:flutter/material.dart';\n"
          "import 'package:flutter/widgets.dart';\n"
          "import 'package:flutter/services.dart';",
        ),
        [
          'package:flutter/material.dart',
          'package:flutter/widgets.dart',
          'package:flutter/services.dart',
        ],
      );
    });

    test('finds export and part directives as well as import', () {
      expect(offendingUrisIn("export '../skins/track_skin.dart';"), [
        '../skins/track_skin.dart',
      ]);
      expect(offendingUrisIn("part '../ui/board.g.dart';"), [
        '../ui/board.g.dart',
      ]);
      expect(offendingUrisIn("export 'package:flutter/material.dart';"), [
        'package:flutter/material.dart',
      ]);
    });

    test('finds a directive with show, hide, as or deferred', () {
      expect(
        offendingUrisIn(
          "import '../skins/a.dart' show A;\n"
          "import '../skins/b.dart' hide B;\n"
          "import '../skins/c.dart' as c;\n"
          "import '../skins/d.dart' deferred as d;\n"
          "import 'package:flutter/material.dart' as m show Colors hide Icons;",
        ),
        [
          '../skins/a.dart',
          '../skins/b.dart',
          '../skins/c.dart',
          '../skins/d.dart',
          'package:flutter/material.dart',
        ],
      );
    });

    test('finds a forbidden URI on either side of a conditional import', () {
      // The condition picks the URI at build time, so both are reachable.
      expect(
        offendingUrisIn(
          "import 'stub.dart' if (dart.library.ui) '../skins/real.dart';",
        ),
        ['../skins/real.dart'],
      );
      expect(
        offendingUrisIn(
          "import '../skins/stub.dart' if (dart.library.io) 'real.dart';",
        ),
        ['../skins/stub.dart'],
      );
    });

    test('finds a directive written over several lines', () {
      expect(
        offendingUrisIn(
          'import\n'
          "    '../skins/track_skin.dart'\n"
          '    show TrackSkin,\n'
          '        SkinPalette;',
        ),
        ['../skins/track_skin.dart'],
      );
    });

    test('finds a directive that is not the first thing on its line', () {
      expect(offendingUrisIn("library a; import '../ui/x.dart';"), [
        '../ui/x.dart',
      ]);
    });

    test('allows what the model is meant to import', () {
      expect(
        offendingUrisIn(
          "import 'package:flutter/foundation.dart';\n"
          "import 'package:flutter/foundation.dart' show ChangeNotifier;\n"
          "import 'package:puzzle_engine/puzzle_engine.dart';\n"
          "import '../../../core/storage/save_data.dart';\n"
          "import 'package:zibo_games/core/storage/save_data.dart';\n"
          "import 'tracks_session_codec.dart';\n"
          "export 'tracks_session_codec.dart';\n"
          "import 'dart:math';\n"
          "import 'dart:async';",
        ),
        isEmpty,
      );
    });

    test('allows foundation but not the other Flutter libraries', () {
      expect(
        offendingUrisIn("import 'package:flutter/foundation.dart';"),
        isEmpty,
      );
      expect(
        offendingUrisIn("import 'package:flutter/material.dart';"),
        isNotEmpty,
      );
      expect(
        offendingUrisIn("import 'package:flutter/widgets.dart';"),
        isNotEmpty,
      );
    });

    test('ignores a directive in a line comment', () {
      expect(offendingUrisIn("// import '../skins/track_skin.dart';"), isEmpty);
      expect(
        offendingUrisIn("/// import 'package:flutter/material.dart';"),
        isEmpty,
      );
      expect(offendingUrisIn("final x = 1; // import 'dart:ui';"), isEmpty);
    });

    test('ignores a directive in a block comment', () {
      expect(
        offendingUrisIn(
          "/* import '../skins/track_skin.dart';\n"
          "   import 'dart:ui'; */",
        ),
        isEmpty,
      );
    });

    test('does not mistake a sibling path for skins or ui', () {
      // Only whole directory names count; a prefix or a file name does not.
      expect(
        offendingUrisIn(
          "import '../skinsy/x.dart';\n"
          "import 'ui_helpers.dart';\n"
          "import '../ui_helpers.dart';\n"
          "import 'skins.dart';\n"
          "import 'ui.dart';\n"
          "import '../myui/x.dart';\n"
          "import 'package:zibo_games/features/tracks/model/skins.dart';\n"
          "import 'package:zibo_games/features/tracks/skinsy/x.dart';\n"
          "import 'package:zibo_games/features/tracks/ui_helpers.dart';",
        ),
        isEmpty,
      );
    });

    test('forbids only the tracks feature in package form', () {
      // A model importing Sudoku's UI would be odd, but it is not what this
      // guard exists for: the theme-free promise is about Tracks skins, and a
      // second, broader rule would be a second thing to keep right.
      expect(
        offendingUrisIn(
          "import 'package:zibo_games/features/sudoku/ui/board.dart';\n"
          "import 'package:zibo_games/features/sudoku/skins/x.dart';",
        ),
        isEmpty,
      );
    });

    test('ignores a longer word that merely contains a keyword', () {
      expect(offendingUrisIn("final reimport = '../skins/x.dart';"), isEmpty);
      expect(offendingUrisIn("const exporter = 'dart:ui';"), isEmpty);
    });

    test('reports every offender, in source order', () {
      expect(
        offendingUrisIn(
          "import '../ui/a.dart';\n"
          "import 'package:puzzle_engine/puzzle_engine.dart';\n"
          "import 'dart:ui';",
        ),
        ['../ui/a.dart', 'dart:ui'],
      );
    });
  });

  group('the directory scan', () {
    test('reports offending files and ignores clean ones', () {
      final directory = _tempDirectory();
      File(
        '${directory.path}/clean.dart',
      ).writeAsStringSync("import 'package:flutter/foundation.dart';\n");
      Directory('${directory.path}/nested').createSync();
      File(
        '${directory.path}/nested/dirty.dart',
      ).writeAsStringSync("import 'dart:ui';\nimport '../skins/x.dart';\n");
      File(
        '${directory.path}/notes.txt',
      ).writeAsStringSync("import 'dart:ui';\n");

      expect(offendersIn(directory), {
        'nested/dirty.dart': ['dart:ui', '../skins/x.dart'],
      });
    });
  });

  group('lib/features/tracks', () {
    final model = Directory('lib/features/tracks/model');

    test('the model directory exists and holds Dart files', () {
      // Without this the scan below would pass on a path that matched
      // nothing, which is how a guard stops guarding.
      expect(model.existsSync(), isTrue, reason: '${model.path} is missing');
      expect(_dartFilesIn(model), isNotEmpty);
    });

    test('the model imports no skin, no ui and no Flutter but foundation', () {
      expect(offendersIn(model), isEmpty);
    });

    test('the data directory, once it exists, holds to the same rule', () {
      // `lib/features/tracks/data` arrives with PR 7. Until then there is
      // nothing to scan, and that is not a failure; from then on it is held
      // to the same boundary as the model.
      final data = Directory('lib/features/tracks/data');
      if (!data.existsSync()) return;
      expect(offendersIn(data), isEmpty);
    });

    test('fails against a model that imports a skin', () {
      // The broken version of the check above: the same files with one
      // forbidden import added. If the scan reported nothing here, the clean
      // result above would mean nothing.
      expect(model.existsSync(), isTrue, reason: '${model.path} is missing');
      final copy = _tempDirectory();
      _copyDartFiles(model, copy);
      final files = _dartFilesIn(copy)
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files, isNotEmpty);
      files.first.writeAsStringSync(
        "\nimport '../skins/track_skin.dart';\n",
        mode: FileMode.append,
      );

      expect(offendersIn(copy), {
        _relativeTo(copy, files.first): ['../skins/track_skin.dart'],
      });
      expect(offendersIn(model), isEmpty);
    });
  });
}

/// The URIs in [source]'s `import`, `export` and `part` directives that the
/// Tracks model must not use, in source order, ignoring comments.
///
/// Comments are stripped rather than skipped, because the files that matter
/// also explain themselves, and a directive in prose is not an import. The
/// stripping is not a Dart parser: a `//` inside a string literal ends the line
/// early, which can only hide an import, and hiding one that way takes more
/// effort than adding it honestly.
///
/// A relative URI is judged by its directory segments alone, so a model file
/// reaching `../../sudoku/ui/x.dart` is flagged too. That is stricter than the
/// package form, which forbids only `features/tracks/skins` and
/// `features/tracks/ui`; a relative path from the model has no honest reason
/// to name a `ui` or `skins` directory anywhere.
List<String> offendingUrisIn(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  final offenders = <String>[];
  for (final directive in _directive.allMatches(code)) {
    for (final uri in _quoted.allMatches(directive.group(0)!)) {
      final value = uri.group(1) ?? uri.group(2)!;
      if (_isForbidden(value)) offenders.add(value);
    }
  }
  return offenders;
}

/// A whole directive, up to its semicolon, so that every URI of a conditional
/// import is seen and a directive may span lines.
final RegExp _directive = RegExp(
  r'''(?<![\w$])(?:import|export|part)\s+['"][^;]*;''',
);

/// A string literal inside a directive, single- or double-quoted.
final RegExp _quoted = RegExp(r'''\'([^\']*)\'|"([^"]*)"''');

bool _isForbidden(String uri) {
  if (uri == 'dart:ui') return true;
  if (uri.startsWith('package:flutter/')) return uri != _allowedFlutterLibrary;
  if (uri.startsWith('package:')) {
    if (!uri.startsWith(_tracksPackagePrefix)) return false;
    return _reachesForbiddenDirectory(
      uri.substring(_tracksPackagePrefix.length),
    );
  }
  if (uri.contains(':')) return false; // dart:core, dart:math, ...
  return _reachesForbiddenDirectory(uri);
}

/// Whether any directory segment of [path] (every segment but the file name)
/// is exactly `skins` or `ui`.
bool _reachesForbiddenDirectory(String path) {
  final segments = path.split('/');
  return segments.take(segments.length - 1).any(_forbiddenDirectories.contains);
}

/// Every `.dart` file under [directory] that has offending directives, mapped
/// to those URIs. Keys are paths relative to [directory], with `/` separators.
Map<String, List<String>> offendersIn(Directory directory) {
  final offenders = <String, List<String>>{};
  for (final file in _dartFilesIn(directory)) {
    final found = offendingUrisIn(file.readAsStringSync());
    if (found.isNotEmpty) offenders[_relativeTo(directory, file)] = found;
  }
  return offenders;
}

List<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList();

/// The path of [file] inside [directory], with the separators the repository
/// uses.
String _relativeTo(Directory directory, File file) {
  final root = directory.path.replaceAll(r'\', '/');
  final path = file.path.replaceAll(r'\', '/');
  return path.substring(root.length).replaceFirst(RegExp('^/'), '');
}

void _copyDartFiles(Directory from, Directory to) {
  for (final file in _dartFilesIn(from)) {
    final target = File('${to.path}/${_relativeTo(from, file)}');
    target.parent.createSync(recursive: true);
    file.copySync(target.path);
  }
}

Directory _tempDirectory() {
  final directory = Directory.systemTemp.createTempSync('tracks_boundary_');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
