// A Tracks ID is the whole of what a save file remembers about a puzzle, so
// these tests are about a stored format. Two spellings of one puzzle would be
// two `solved` keys for one board, which is why the rejects below are as much
// the point as the accepts.

import 'package:puzzle_engine/src/difficulty.dart';
import 'package:puzzle_engine/src/hash.dart';
import 'package:puzzle_engine/src/puzzle_id.dart';
import 'package:puzzle_engine/src/tracks/tracks_puzzle_id.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';
import 'package:test/test.dart';

const List<Difficulty> tiers = [
  Difficulty.easy,
  Difficulty.medium,
  Difficulty.hard,
];

void main() {
  group('the canonical string', () {
    test('reads the way the plan spells it', () {
      const id = TracksPuzzleId(TracksSpec.s7x7, Difficulty.medium, 412);
      expect(id.value, 'tracks:7x7:medium:412');
      expect(id.toString(), 'tracks:7x7:medium:412');
    });

    test('round-trips through the parser for every shape', () {
      for (final spec in TracksSpec.supported) {
        for (final difficulty in tiers) {
          // 5x5 Hard is not an ID; the test at the foot of the file says why.
          if (spec == TracksSpec.s5x5 && difficulty == Difficulty.hard) {
            continue;
          }
          for (final index in [0, 1, 9, 10, 412, 99999, 999999999]) {
            final id = TracksPuzzleId(spec, difficulty, index);
            expect(TracksPuzzleId.parse(id.value), id, reason: id.value);
            expect(TracksPuzzleId.parse(id.value).value, id.value);
          }
        }
      }
    });

    test('names one puzzle per size, difficulty and index', () {
      const first = TracksPuzzleId(TracksSpec.s7x7, Difficulty.hard, 1);
      expect(first, const TracksPuzzleId(TracksSpec.s7x7, Difficulty.hard, 1));
      expect(
        first.hashCode,
        const TracksPuzzleId(TracksSpec.s7x7, Difficulty.hard, 1).hashCode,
      );
      expect(
        first,
        isNot(const TracksPuzzleId(TracksSpec.s9x9, Difficulty.hard, 1)),
      );
      expect(
        first,
        isNot(const TracksPuzzleId(TracksSpec.s7x7, Difficulty.easy, 1)),
      );
      expect(
        first,
        isNot(const TracksPuzzleId(TracksSpec.s7x7, Difficulty.hard, 2)),
      );
    });

    test('the largest index is the one Sudoku draws', () {
      expect(TracksPuzzleId.maxPuzzleIndex, PuzzleId.maxPuzzleIndex);
    });
  });

  group('the seed', () {
    test('is the hash of the whole string, not of the index', () {
      const id = TracksPuzzleId(TracksSpec.s7x7, Difficulty.medium, 412);
      expect(id.seed, fnv1a32('tracks:7x7:medium:412'));
    });

    test('differs across every shape at one index', () {
      final seeds = <int>{};
      for (final spec in TracksSpec.supported) {
        for (final difficulty in tiers) {
          seeds.add(TracksPuzzleId(spec, difficulty, 1).seed);
        }
      }
      expect(seeds.length, 9);
    });

    test('is not the seed of the Sudoku puzzle with the same index', () {
      // The prefix is in the hash, so a Tracks puzzle is never a re-dig of a
      // Sudoku one.
      expect(
        const TracksPuzzleId(TracksSpec.s9x9, Difficulty.easy, 0).seed,
        isNot(fnv1a32('sudoku:9x9:easy:0')),
      );
    });
  });

  group('parse rejects', () {
    void rejects(String text, {int? offset}) {
      expect(
        () => TracksPuzzleId.parse(text),
        throwsA(
          isA<FormatException>().having(
            (e) => e.offset,
            'offset',
            offset ?? anything,
          ),
        ),
        reason: text,
      );
    }

    test('expert at every size, which Tracks does not have', () {
      rejects('tracks:7x7:expert:0', offset: 11);
      rejects('tracks:5x5:expert:0', offset: 11);
      rejects('tracks:9x9:expert:0', offset: 11);
      expect(
        () => TracksPuzzleId.parse('tracks:7x7:expert:0'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('no expert tier'),
          ),
        ),
      );
    });

    test('a leading zero, a sign and a plus in the index', () {
      rejects('tracks:7x7:easy:01', offset: 16);
      rejects('tracks:7x7:easy:-1', offset: 16);
      rejects('tracks:7x7:easy:+1', offset: 16);
      rejects('tracks:7x7:easy:', offset: 16);
      rejects('tracks:7x7:easy:1.0', offset: 16);
    });

    test('a size it does not build', () {
      rejects('tracks:8x8:easy:0', offset: 7);
      rejects('tracks:6x6:easy:0', offset: 7);
      rejects('tracks:7x9:easy:0', offset: 7);
    });

    test('the wrong prefix, including a Sudoku ID', () {
      rejects('sudoku:7x7:easy:0', offset: 0);
      rejects('Tracks:7x7:easy:0', offset: 0);
    });

    test('the wrong number of fields', () {
      rejects('tracks:7x7:easy');
      rejects('tracks:7x7:easy:0:0');
      rejects('');
    });

    test('an unknown or capitalised difficulty', () {
      rejects('tracks:7x7:Easy:0', offset: 11);
      rejects('tracks:7x7:impossible:0', offset: 11);
    });

    test('an index past maxPuzzleIndex', () {
      rejects('tracks:7x7:easy:1000000000', offset: 16);
      rejects('tracks:7x7:easy:99999999999999999999', offset: 16);
    });

    test('whitespace around the string', () {
      rejects(' tracks:7x7:easy:0');
      rejects('tracks:7x7:easy:0 ');
    });
  });

  test('a Sudoku ID is not a Tracks ID and the reverse', () {
    expect(
      () => TracksPuzzleId.parse('sudoku:9x9:easy:0'),
      throwsFormatException,
    );
    expect(() => PuzzleId.parse('tracks:9x9:easy:0'), throwsFormatException);
  });

  test('5x5 hard is refused, because a 5x5 cannot carry it', () {
    // PR 3 measured Hard on 5x5 reaching only one or two fixed pieces out of
    // fourteen (PLAN-phase-9-tracks.md §4.1), so it is not offered. The offset
    // is the difficulty field, as for expert.
    expect(
      () => TracksPuzzleId.parse('tracks:5x5:hard:0'),
      throwsA(
        isA<FormatException>()
            .having((e) => e.offset, 'offset', 11)
            .having((e) => e.message, 'message', contains('5x5 hard')),
      ),
    );
    expect(TracksPuzzleId.parse('tracks:7x7:hard:0').spec, TracksSpec.s7x7);
    expect(TracksPuzzleId.parse('tracks:9x9:hard:0').spec, TracksSpec.s9x9);
    expect(TracksPuzzleId.parse('tracks:5x5:medium:0').spec, TracksSpec.s5x5);
  });
}
