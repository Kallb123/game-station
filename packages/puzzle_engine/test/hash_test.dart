// `fnv1a32` turns a puzzle ID into a seed, so it is frozen for the same reason
// the PRNG is (`PLAN-phase-2.md` §4.2). The single-character and `foobar`
// vectors are the published FNV-1a 32-bit ones, which check the implementation
// against the algorithm rather than against itself; the ID vectors freeze the
// values this project actually depends on.
//
// Runs under `dart test -p chrome` as well as natively: the split multiply
// exists for the web, so a version of it that is only ever run on a 64-bit VM
// proves nothing.

import 'dart:convert';

import 'package:puzzle_engine/src/hash.dart';
import 'package:test/test.dart';

/// Puzzle ID shapes the parser will accept in PR 5, plus the `#n` retry-seed
/// form the generator derives from them (`PLAN-phase-2.md` §4.7).
const List<String> idShapes = [
  'sudoku:9x9:easy:0',
  'sudoku:9x9:hard:412',
  'sudoku:9x9:expert:99',
  'sudoku:6x6:medium:1',
  'sudoku:9x9:hard:412#1',
  'sudoku:9x9:hard:412#39',
];

void main() {
  test('matches the published FNV-1a 32-bit vectors', () {
    expect(fnv1a32(''), 0x811C9DC5);
    expect(fnv1a32('a'), 0xE40C292C);
    expect(fnv1a32('b'), 0xE70C2DE5);
    expect(fnv1a32('c'), 0xE60C2C52);
    expect(fnv1a32('foobar'), 0xBF9CF968);
  });

  test('replays the frozen values for puzzle IDs', () {
    expect(fnv1a32('sudoku:9x9:easy:0'), 0x05681AE4);
    expect(fnv1a32('sudoku:9x9:hard:412'), 0x2A45BF74);
    expect(fnv1a32('sudoku:9x9:expert:99'), 0xC269542C);
    expect(fnv1a32('sudoku:6x6:medium:1'), 0x22C1EDFA);
    expect(fnv1a32('sudoku:9x9:hard:412#1'), 0xCB78A38C);
    expect(fnv1a32('sudoku:9x9:hard:412#39'), 0xFFEE2CD1);
  });

  test('stays inside 32 bits', () {
    for (var i = 0; i < 5000; i++) {
      final hash = fnv1a32('sudoku:9x9:hard:$i');
      expect(hash, inInclusiveRange(0, 0xFFFFFFFF));
    }
  });

  test('every ID shape is ASCII, so UTF-8 and the code units agree', () {
    // The hash is defined over UTF-8 bytes. IDs are ASCII by construction, so
    // the two coincide today; this fails if an ID shape ever stops being ASCII,
    // rather than letting the definition quietly start mattering.
    for (final id in idShapes) {
      expect(utf8.encode(id), id.codeUnits, reason: id);
    }
  });

  test('hashes the UTF-8 bytes, not the code units', () {
    // Guards the definition itself: 'café' is one code unit but two bytes at
    // the end, so an implementation over `codeUnits` gives a different answer.
    expect(fnv1a32('café'), 0xA82B5049);
    expect(utf8.encode('café').length, isNot('café'.codeUnits.length));
  });

  test('separates IDs that differ by one character', () {
    final hashes = {
      for (var i = 0; i < 1000; i++) fnv1a32('sudoku:9x9:hard:$i'),
    };
    expect(hashes, hasLength(1000));
  });
}
