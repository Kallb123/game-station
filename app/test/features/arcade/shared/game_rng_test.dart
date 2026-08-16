// `GameRng`'s tests (`PLAN-phase-4.md` §4.3, PR 2).
//
// Unlike the engine's `Rng`, this sequence is not frozen — nothing persists a
// run, so a changed sequence breaks no save. The literals below still pin the
// current output, captured from this implementation rather than an
// independent one: an unintended change to the algorithm then shows up here
// as a diff of numbers instead of a game that plays differently for no
// visible reason.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/shared/game_rng.dart';

/// The first five `nextUint32()` draws for three seeds, captured from this
/// implementation.
const Map<int, List<int>> capturedOutputs = {
  1: [1688603507, 483330935, 1234379079, 2596349146, 1964852503],
  42: [2500100491, 2743697713, 3864196134, 2719703533, 183662910],
  12345: [3570713409, 3676595967, 2827881794, 1307132913, 3615323770],
};

void main() {
  group('nextUint32', () {
    for (final entry in capturedOutputs.entries) {
      test('replays the same sequence for seed ${entry.key}', () {
        final rng = GameRng(entry.key);
        final actual = [
          for (var i = 0; i < entry.value.length; i++) rng.nextUint32(),
        ];
        expect(actual, entry.value);
      });
    }

    test('a fresh generator on the same seed replays it again', () {
      expect(draws(GameRng(2026), 20), draws(GameRng(2026), 20));
    });

    test('stays inside 32 bits over a long run', () {
      final rng = GameRng(9);
      for (var i = 0; i < 100000; i++) {
        final value = rng.nextUint32();
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThanOrEqualTo(0xFFFFFFFF));
      }
    });

    test('gives adjacent seeds unrelated streams', () {
      expect(draws(GameRng(100), 8), isNot(draws(GameRng(101), 8)));
    });

    test('the one seed that would zero the xorshift state still advances', () {
      // SplitMix32 is a bijection on 32 bits, so exactly one seed reaches the
      // mix's only fixed point; unguarded, every later draw would be zero.
      // `game_rng.dart`'s `_seedFrom` derives it algebraically as the negation
      // of the golden-ratio constant it adds first.
      const zeroReachingSeed = 0x61C88647;
      final rng = GameRng(zeroReachingSeed);
      final values = [for (var i = 0; i < 5; i++) rng.nextUint32()];
      expect(values.every((v) => v == 0), isFalse);
    });
  });

  group('nextInt', () {
    test('is unbiased over a million draws at a bound that does not divide '
        '2^32', () {
      // 7 does not divide 2^32 — the case `% bound` would be biased for.
      final rng = GameRng(2026);
      final counts = List.filled(7, 0);
      for (var i = 0; i < 1000000; i++) {
        counts[rng.nextInt(7)]++;
      }

      const expected = 1000000 / 7;
      for (final count in counts) {
        expect(
          (count - expected).abs() / expected,
          lessThan(0.01),
          reason: 'counts were $counts',
        );
      }
    });

    test('stays inside the bound', () {
      final rng = GameRng(9);
      for (final bound in [2, 3, 6, 9, 36, 81, 1000, 0xFFFFFFFF]) {
        for (var i = 0; i < 1000; i++) {
          expect(rng.nextInt(bound), inInclusiveRange(0, bound - 1));
        }
      }
    });

    test('accepts the whole 32-bit range as a bound', () {
      final rng = GameRng(3);
      expect(rng.nextInt(4294967296), inInclusiveRange(0, 4294967295));
    });

    test('rejects a bound outside 1..2^32', () {
      final rng = GameRng(3);
      expect(() => rng.nextInt(0), throwsRangeError);
      expect(() => rng.nextInt(-1), throwsRangeError);
      expect(() => rng.nextInt(4294967297), throwsRangeError);
    });

    test('a bound of 1 consumes nothing', () {
      final rng = GameRng(42);
      expect(rng.nextInt(1), 0);
      expect(rng.nextInt(1), 0);
      expect(rng.nextUint32(), GameRng(42).nextUint32());
    });
  });

  group('nextDouble', () {
    test('stays inside [0, 1) over a long run', () {
      final rng = GameRng(7);
      for (var i = 0; i < 100000; i++) {
        final value = rng.nextDouble();
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThan(1));
      }
    });
  });

  group('pick', () {
    test('only ever returns an element of the list', () {
      final rng = GameRng(5);
      const candidates = [50, 100, 150, 200, 250, 300];
      for (var i = 0; i < 200; i++) {
        expect(candidates, contains(rng.pick(candidates)));
      }
    });

    test('draws its index the same way nextInt does', () {
      final forPick = GameRng(5);
      final forIndex = GameRng(5);
      const candidates = [10, 20, 30];
      expect(
        forPick.pick(candidates),
        candidates[forIndex.nextInt(candidates.length)],
      );
    });
  });

  test('two generators on the same seed stay in step', () {
    final a = GameRng(777);
    final b = GameRng(777);
    for (var i = 0; i < 500; i++) {
      expect(a.nextUint32(), b.nextUint32(), reason: 'diverged at draw $i');
    }
  });
}

/// The next [count] raw draws from [rng].
List<int> draws(GameRng rng, int count) => [
  for (var i = 0; i < count; i++) rng.nextUint32(),
];
