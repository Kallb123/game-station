// The guard that keeps generation off the isolate that draws.
//
// A 9x9 Hard is 65 ms at the median and about half a second at the tail
// (`PLAN.md` §3.5). Called on the UI isolate, that is a visible freeze, and it
// is the kind of call that gets added later by someone who only needs a puzzle
// "just here" — so `PLAN-phase-3.md` §1 asks for a test rather than a comment.
// `generateTracks` is held to the same rule (`PLAN-phase-9-tracks.md` §4.9).
//
// It is textual, so it can be evaded on purpose; the same shape of check in
// `tool/check_offline.dart` has caught the same shape of mistake. Being a guard,
// it has its own tests: the scanner is exercised against sources that do and do
// not call, because a scanner that silently found nothing would pass forever.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where `generateSudoku` may be called, relative to the app package root.
const String sudokuEntryPoint = 'lib/features/sudoku/data/puzzle_source.dart';

/// Where `generateTracks` may be called.
const String tracksEntryPoint =
    'lib/features/tracks/data/tracks_puzzle_source.dart';

void main() {
  for (final function in ['generateSudoku', 'generateTracks']) {
    group('the scanner for $function', () {
      test('finds a call', () {
        expect(callsIn('final puzzle = $function(id);', function), 1);
      });

      test('finds a call that is not the first thing on its line', () {
        expect(
          callsIn('  return Record.of($function(id)).encode();', function),
          1,
        );
      });

      test('ignores a mention in a line comment', () {
        expect(callsIn('// $function(id) runs on the isolate.', function), 0);
        expect(callsIn('/// Never calls $function(id) directly.', function), 0);
        expect(callsIn('final x = 1; // $function(id)', function), 0);
      });

      test('ignores a mention in a block comment', () {
        expect(callsIn('/* $function(id)\n   over two lines */', function), 0);
      });

      test('ignores a longer name that contains it', () {
        expect(callsIn('${function}Batch(id);', function), 0);
        expect(callsIn('_$function(id);', function), 0);
      });

      test('counts every call, not just the first', () {
        expect(callsIn('$function(a);\n$function(b);', function), 2);
      });
    });
  }

  group('the scanner keeps the two functions apart', () {
    test('a call to one is not a call to the other', () {
      expect(callsIn('generateTracks(id);', 'generateSudoku'), 0);
      expect(callsIn('generateSudoku(id);', 'generateTracks'), 0);
    });
  });

  group('app/lib', () {
    final entryPoints = {
      'generateSudoku': sudokuEntryPoint,
      'generateTracks': tracksEntryPoint,
    };

    for (final MapEntry(key: function, value: entryPoint)
        in entryPoints.entries) {
      test('calls $function exactly once, at its isolate entry point', () {
        final calls = <String, int>{};
        for (final file in _dartFilesIn(Directory('lib'))) {
          final found = callsIn(file.readAsStringSync(), function);
          if (found > 0) calls[_relativePath(file)] = found;
        }

        expect(calls, {entryPoint: 1});
      });

      test('that call goes through compute', () {
        // The count above says where generation is written; this says it is
        // handed to another isolate rather than run where it stands.
        expect(File(entryPoint).readAsStringSync(), contains('compute('));
      });
    }
  });
}

/// How many times [source] calls [function], ignoring comments.
///
/// Comments are stripped rather than counted, because the file that makes the
/// call is also the file that explains it, and prose is not a call site. The
/// stripping is not a Dart parser: a `//` inside a string literal ends the line
/// early, which can only hide a call, and hiding one that way takes more effort
/// than adding it honestly.
int callsIn(String source, String function) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  return RegExp('(?<![\\w\$])$function\\s*\\(').allMatches(code).length;
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
