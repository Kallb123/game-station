// A puzzle ID is the whole of what a save file remembers about a puzzle, so
// these tests are about a stored format rather than about a convenience type.
// Two spellings that name one puzzle would be two `solved` keys for one grid,
// which is why the parser is strict rather than forgiving, and why the rejects
// below are as much the point as the accepts.

import 'package:puzzle_engine/src/difficulty.dart';
import 'package:puzzle_engine/src/hash.dart';
import 'package:puzzle_engine/src/puzzle_id.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:test/test.dart';

/// Every size and difficulty a puzzle ID can name.
const List<(SudokuSpec, Difficulty)> supported = [
  (SudokuSpec.s9x9, Difficulty.easy),
  (SudokuSpec.s9x9, Difficulty.medium),
  (SudokuSpec.s9x9, Difficulty.hard),
  (SudokuSpec.s9x9, Difficulty.expert),
  (SudokuSpec.s6x6, Difficulty.easy),
  (SudokuSpec.s6x6, Difficulty.medium),
  (SudokuSpec.s6x6, Difficulty.hard),
];

void main() {
  group('the canonical string', () {
    test('reads the way the plan spells it', () {
      const id = PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 412);
      expect(id.value, 'sudoku:9x9:hard:412');
      expect(id.toString(), 'sudoku:9x9:hard:412');
    });

    test('round-trips through the parser for every shape', () {
      for (final (spec, difficulty) in supported) {
        for (final index in [0, 1, 9, 10, 412, 99999]) {
          final id = PuzzleId(spec, difficulty, index);
          expect(PuzzleId.parse(id.value), id, reason: id.value);
          expect(PuzzleId.parse(id.value).value, id.value);
        }
      }
    });

    test('names one puzzle per size, difficulty and index', () {
      const first = PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 1);
      expect(first, const PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 1));
      expect(
        first.hashCode,
        const PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 1).hashCode,
      );
      expect(first, isNot(const PuzzleId(SudokuSpec.s6x6, Difficulty.hard, 1)));
      expect(first, isNot(const PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 1)));
      expect(first, isNot(const PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 2)));
    });
  });

  group('the seed', () {
    test('is the hash of the whole string, not of the index', () {
      // Hashing the index alone would make `easy:1` and `hard:1` the same grid
      // dug two ways, which a child would notice before anyone else did.
      const id = PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 412);
      expect(id.seed, fnv1a32('sudoku:9x9:hard:412'));

      final seeds = <int>{};
      for (final (spec, difficulty) in supported) {
        seeds.add(PuzzleId(spec, difficulty, 1).seed);
      }
      expect(
        seeds,
        hasLength(supported.length),
        reason: 'index 1 of each shape must start from its own sequence',
      );
    });
  });

  group('the parser rejects', () {
    test('a leading zero, which would be a second name for one puzzle', () {
      expect(
        () => PuzzleId.parse('sudoku:9x9:hard:0412'),
        throwsFormatException,
      );
      expect(() => PuzzleId.parse('sudoku:9x9:hard:00'), throwsFormatException);
      expect(
        PuzzleId.parse('sudoku:9x9:hard:0').index,
        0,
        reason: 'zero itself is canonical; it is the padding that is not',
      );
    });

    test('6x6 Expert, which has no tier to generate', () {
      expect(
        () => PuzzleId.parse('sudoku:6x6:expert:1'),
        throwsFormatException,
      );
      expect(
        PuzzleId.parse('sudoku:9x9:expert:1').difficulty,
        Difficulty.expert,
        reason: '9x9 does have one',
      );
    });

    test('a size this engine does not build', () {
      for (final id in [
        'sudoku:4x4:easy:1',
        'sudoku:12x12:easy:1',
        'sudoku:9X9:easy:1',
        'sudoku::easy:1',
      ]) {
        expect(() => PuzzleId.parse(id), throwsFormatException, reason: id);
      }
    });

    test('anything but the four fields in the right order', () {
      for (final id in [
        '',
        'sudoku',
        'sudoku:9x9:hard',
        'sudoku:9x9:hard:1:2',
        'sudoku:hard:9x9:1',
        'puzzle:9x9:hard:1',
        'Sudoku:9x9:hard:1',
        ':9x9:hard:1',
      ]) {
        expect(() => PuzzleId.parse(id), throwsFormatException, reason: id);
      }
    });

    test('an index that is not a plain decimal count', () {
      for (final id in [
        'sudoku:9x9:hard:',
        'sudoku:9x9:hard:-1',
        'sudoku:9x9:hard:+1',
        'sudoku:9x9:hard: 1',
        'sudoku:9x9:hard:1 ',
        'sudoku:9x9:hard:1.0',
        'sudoku:9x9:hard:0x10',
        'sudoku:9x9:hard:four',
        'sudoku:9x9:hard:1e3',
      ]) {
        expect(() => PuzzleId.parse(id), throwsFormatException, reason: id);
      }
    });

    test('an index past the limit both platforms agree about', () {
      // An int is a double on the web, exact only to 2^53, so an index beyond
      // that would name one puzzle on a tablet and another in a browser. The
      // limit is drawn well inside what both agree about rather than at the
      // edge, and it is the same limit everywhere — a test that only failed on
      // the web would be a test nobody ran.
      expect(
        PuzzleId.parse('sudoku:9x9:hard:${PuzzleId.maxPuzzleIndex}').index,
        PuzzleId.maxPuzzleIndex,
      );
      for (final index in [
        '${PuzzleId.maxPuzzleIndex + 1}',
        '9007199254740993',
        '9' * 40,
      ]) {
        expect(
          () => PuzzleId.parse('sudoku:9x9:hard:\$index'),
          throwsFormatException,
          reason: index,
        );
      }
    });

    test('a difficulty that is not one of the four', () {
      for (final id in [
        'sudoku:9x9:HARD:1',
        'sudoku:9x9:tricky:1',
        'sudoku:9x9::1',
      ]) {
        expect(() => PuzzleId.parse(id), throwsFormatException, reason: id);
      }
    });

    test('with the offending position in the exception', () {
      // Phase 3 logs this when a cached puzzle fails to load, and "expected a
      // decimal index" beside the character it means is the difference between
      // a report someone can act on and one they cannot.
      try {
        PuzzleId.parse('sudoku:9x9:hard:0412');
        fail('expected a FormatException');
      } on FormatException catch (error) {
        expect(error.offset, 'sudoku:9x9:hard:'.length);
        expect(error.source, 'sudoku:9x9:hard:0412');
      }
    });
  });

  group('the daily index', () {
    test('starts at the epoch', () {
      expect(puzzleEpoch, DateTime.utc(2026, 1, 1));
      expect(dayIndexFor(DateTime.utc(2026, 1, 1)), 0);
      expect(dayIndexFor(DateTime.utc(2026, 1, 2)), 1);
      expect(dayIndexFor(DateTime.utc(2026, 12, 31)), 364);
      expect(dayIndexFor(DateTime.utc(2027, 1, 1)), 365);
    });

    test('counts leap days like the calendar does', () {
      // 2028 is a leap year, so a naive 365-day step would be a day out from
      // here on — and every daily puzzle after it would be yesterday's.
      expect(dayIndexFor(DateTime.utc(2028, 1, 1)), 730);
      expect(dayIndexFor(DateTime.utc(2028, 3, 1)), 790);
    });

    test('clamps below the epoch rather than throwing', () {
      // A tablet with its clock set wrong is a support question, not a crash:
      // `AGENTS.md` forbids showing a child an internal error, and day 0's
      // puzzle is wrong in a way nobody can see.
      expect(dayIndexFor(DateTime.utc(2019, 6, 1)), 0);
      expect(dayIndexFor(DateTime.utc(1970, 1, 1)), 0);
      expect(dayIndexFor(DateTime.utc(2025, 12, 31, 23, 59, 59)), 0);
    });

    test('holds the same day for a whole UTC day', () {
      expect(dayIndexFor(DateTime.utc(2026, 6, 1)), 151);
      expect(dayIndexFor(DateTime.utc(2026, 6, 1, 12)), 151);
      expect(dayIndexFor(DateTime.utc(2026, 6, 1, 23, 59, 59, 999)), 151);
      expect(dayIndexFor(DateTime.utc(2026, 6, 2)), 152);
    });

    test('agrees across timezones, either side of midnight', () {
      // The same instant told in local time and in UTC has to be the same
      // puzzle: a child on a plane must not get today's twice or skip one.
      // Building the local value from an instant is what makes this hold
      // wherever the test runs, rather than only in UTC+0.
      for (final utc in [
        DateTime.utc(2026, 6, 1, 23, 30),
        DateTime.utc(2026, 6, 2, 0, 30),
        DateTime.utc(2026, 6, 2, 12),
      ]) {
        final local = DateTime.fromMillisecondsSinceEpoch(
          utc.millisecondsSinceEpoch,
        );
        expect(local.isUtc, isFalse);
        expect(dayIndexFor(local), dayIndexFor(utc), reason: '$utc');
      }
    });

    test('is a plain index, so it names a puzzle like any other', () {
      final id = PuzzleId(
        SudokuSpec.s9x9,
        Difficulty.easy,
        dayIndexFor(DateTime.utc(2026, 6, 1)),
      );
      expect(id.value, 'sudoku:9x9:easy:151');
      expect(PuzzleId.parse(id.value), id);
    });
  });
}
