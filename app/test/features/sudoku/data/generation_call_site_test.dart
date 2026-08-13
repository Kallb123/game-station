// The guard that keeps generation off the isolate that draws.
//
// A 9x9 Hard is 65 ms at the median and about half a second at the tail
// (`PLAN.md` §3.5). Called on the UI isolate, that is a visible freeze, and it
// is the kind of call that gets added later by someone who only needs a puzzle
// "just here" — so `PLAN-phase-3.md` §1 asks for a test rather than a comment.
//
// It is textual, so it can be evaded on purpose; the same shape of check in
// `tool/check_offline.dart` has caught the same shape of mistake. Being a guard,
// it has its own tests: the scanner is exercised against sources that do and do
// not call, because a scanner that silently found nothing would pass forever.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Where `generateSudoku` may be called, relative to the app package root.
const String isolateEntryPoint = 'lib/features/sudoku/data/puzzle_source.dart';

void main() {
  group('the scanner', () {
    test('finds a call', () {
      expect(callsIn('final puzzle = generateSudoku(id);'), 1);
    });

    test('finds a call that is not the first thing on its line', () {
      expect(
        callsIn('  return PuzzleRecord.of(generateSudoku(id)).encode();'),
        1,
      );
    });

    test('ignores a mention in a line comment', () {
      expect(callsIn('// generateSudoku(id) runs on the isolate.'), 0);
      expect(callsIn('/// Never calls generateSudoku(id) directly.'), 0);
      expect(callsIn('final x = 1; // generateSudoku(id)'), 0);
    });

    test('ignores a mention in a block comment', () {
      expect(callsIn('/* generateSudoku(id)\n   over two lines */'), 0);
    });

    test('ignores a longer name that contains it', () {
      expect(callsIn('generateSudokuBatch(id);'), 0);
      expect(callsIn('_generateSudoku(id);'), 0);
    });

    test('counts every call, not just the first', () {
      expect(callsIn('generateSudoku(a);\ngenerateSudoku(b);'), 2);
    });
  });

  group('app/lib', () {
    test('calls generateSudoku exactly once, at the isolate entry point', () {
      final calls = <String, int>{};
      for (final file in _dartFilesIn(Directory('lib'))) {
        final found = callsIn(file.readAsStringSync());
        if (found > 0) calls[_relativePath(file)] = found;
      }

      expect(calls, {isolateEntryPoint: 1});
    });

    test('that call goes through compute', () {
      // The count above says where generation is written; this says it is
      // handed to another isolate rather than run where it stands.
      expect(File(isolateEntryPoint).readAsStringSync(), contains('compute('));
    });
  });
}

/// How many times [source] calls `generateSudoku`, ignoring comments.
///
/// Comments are stripped rather than counted, because the file that makes the
/// call is also the file that explains it, and prose is not a call site. The
/// stripping is not a Dart parser: a `//` inside a string literal ends the line
/// early, which can only hide a call, and hiding one that way takes more effort
/// than adding it honestly.
int callsIn(String source) {
  final code = source
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
      .replaceAll(RegExp('//.*'), '');
  return RegExp(r'(?<![\w$])generateSudoku\s*\(').allMatches(code).length;
}

Iterable<File> _dartFilesIn(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'));

/// The path as this test names it, with the separators the repository uses.
String _relativePath(File file) => file.path.replaceAll(r'\', '/');
