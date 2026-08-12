// The PRNG's output is the save format's foundation (`PLAN-phase-2.md` §4.1),
// so most of this file asserts against literal constants rather than against
// properties: a change to the algorithm has to show up here, as a diff of
// numbers, before it reaches a puzzle nobody can recognise as changed.
//
// The constants were produced by an independent implementation of Xoshiro128+
// and SplitMix32 written from the algorithm definitions, not copied out of
// `rng.dart`, so a transcription slip in either one fails this file.
//
// Runs under `dart test -p chrome` as well as natively — see the CI step. That
// is the only check that the 32-bit masking survives a platform where numbers
// are doubles.

import 'package:puzzle_engine/src/rng.dart';
import 'package:test/test.dart';

/// The first 20 `nextUint32()` values for the three frozen seeds.
const Map<int, List<int>> frozenOutputs = {
  0: [
    0xE40AD944, 0x098F15EF, 0x1AAF3CD9, 0xFC139A7E, //
    0x3DB50701, 0xFBE0DAA4, 0x797A8C06, 0x903B31F3,
    0xB232BDDB, 0x36F99FC3, 0x751FC703, 0xBCCDAF2E,
    0x1C3222B5, 0x81F0EA40, 0x45CC2F4E, 0x321B5E70,
    0xD0991C2F, 0xCDC57EDF, 0x3FF9E236, 0xBE50776A,
  ],
  1: [
    0x11B00AAB, 0x2CA9C9F6, 0x1DEC455B, 0xDE5EFE64, //
    0xE39F313E, 0xB0CC4F0F, 0x3254FF28, 0x7617B5CD,
    0x268144B1, 0x4DD50B07, 0x8BB2AC89, 0x8B58D0FD,
    0x078CDDB8, 0x6B7AFF50, 0xC4FDCD56, 0x06ECD15E,
    0x4BF3CB94, 0x6EB3118F, 0x4753ECF2, 0xE808651E,
  ],
  0xFFFFFFFF: [
    0x9017E90F, 0x1BCCF815, 0x2EA84026, 0x3786D8A0, //
    0x038A72E6, 0x2F85E9B6, 0x295903D3, 0xF8B4A2E5,
    0x4A37D051, 0x61448ED7, 0x72E95E34, 0x7B43B01C,
    0x5CC72663, 0x2CD65852, 0xEBDD80D5, 0x9406A8CB,
    0xE1D34A18, 0xB37FC5DA, 0xF1B2CEEC, 0x07830660,
  ],
};

void main() {
  group('nextUint32', () {
    for (final entry in frozenOutputs.entries) {
      test(
        'replays the frozen sequence for seed 0x${entry.key.toRadixString(16)}',
        () {
          final rng = Rng(entry.key);
          final actual = [
            for (var i = 0; i < entry.value.length; i++) rng.nextUint32(),
          ];
          expect(actual, entry.value);
        },
      );
    }

    test('stays inside 32 bits over a long run', () {
      final rng = Rng(12345);
      for (var i = 0; i < 100000; i++) {
        final value = rng.nextUint32();
        expect(value, greaterThanOrEqualTo(0));
        expect(value, lessThanOrEqualTo(0xFFFFFFFF));
      }
    });

    test('uses only the low 32 bits of the seed', () {
      // Documented behaviour, so callers can pass a hash unmasked. 2^32 + 1 is
      // exactly representable as a double, so this holds on the web too.
      final low = Rng(1);
      final wide = Rng(4294967297);
      expect(
        [for (var i = 0; i < 8; i++) wide.nextUint32()],
        [for (var i = 0; i < 8; i++) low.nextUint32()],
      );
    });

    test('gives adjacent seeds unrelated streams', () {
      // SplitMix32 seeding exists so that seed 100 and seed 101 do not start
      // near each other; consecutive puzzle indices hash to unrelated seeds
      // anyway, but this is the property that makes that true rather than
      // lucky.
      expect(draws(Rng(100), 8), isNot(draws(Rng(101), 8)));
      expect(
        draws(Rng(100), 8).toSet().intersection(draws(Rng(101), 8).toSet()),
        isEmpty,
      );
    });
  });

  group('nextInt', () {
    test('is unbiased over a million draws of nextInt(3)', () {
      // 0.5% of a third, per `PLAN-phase-2.md` §6's done-criteria. The result is
      // deterministic, so this is an assertion about this sequence rather than
      // a statistical test that might flake.
      final rng = Rng(2026);
      final counts = [0, 0, 0];
      for (var i = 0; i < 1000000; i++) {
        counts[rng.nextInt(3)]++;
      }

      const expected = 1000000 / 3;
      for (final count in counts) {
        expect(
          (count - expected).abs() / expected,
          lessThan(0.005),
          reason: 'counts were $counts',
        );
      }
    });

    test('stays inside the bound', () {
      final rng = Rng(9);
      for (final bound in [2, 3, 6, 9, 36, 81, 1000, 0xFFFFFFFF]) {
        for (var i = 0; i < 1000; i++) {
          final value = rng.nextInt(bound);
          expect(value, inInclusiveRange(0, bound - 1));
        }
      }
    });

    test('accepts the whole 32-bit range as a bound', () {
      final rng = Rng(3);
      expect(rng.nextInt(4294967296), inInclusiveRange(0, 4294967295));
    });

    test('rejects a bound outside 1..2^32', () {
      final rng = Rng(3);
      expect(() => rng.nextInt(0), throwsRangeError);
      expect(() => rng.nextInt(-1), throwsRangeError);
      expect(() => rng.nextInt(4294967297), throwsRangeError);
    });

    test('a bound of 1 consumes nothing', () {
      // Load-bearing: a Fisher-Yates pass over a one-element list must leave
      // the stream where it found it, or every puzzle after it shifts.
      final drawn = Rng(42);
      expect(drawn.nextInt(1), 0);
      expect(drawn.nextInt(1), 0);
      expect(drawn.nextUint32(), Rng(42).nextUint32());
    });
  });

  group('shuffle', () {
    test('replays a frozen permutation', () {
      // The constants come from the same independent implementation. They pin
      // the direction of the pass: the ascending variant of Fisher-Yates
      // consumes the same stream and produces a different order.
      expect(shuffled(Rng(7), 9), [6, 2, 5, 0, 4, 7, 3, 1, 8]);
      expect(shuffled(Rng(8), 9), [2, 1, 5, 0, 3, 7, 8, 4, 6]);
    });

    test('permutes rather than losing or duplicating elements', () {
      final rng = Rng(11);
      for (var length = 0; length < 40; length++) {
        final list = [for (var i = 0; i < length; i++) i];
        rng.shuffle(list);
        expect(list..sort(), [for (var i = 0; i < length; i++) i]);
      }
    });

    test('consumes nothing for an empty or single-element list', () {
      final rng = Rng(5);
      rng.shuffle(<int>[]);
      rng.shuffle(<int>[1]);
      expect(rng.nextUint32(), Rng(5).nextUint32());
    });
  });

  test('two generators on the same seed stay in step', () {
    // The property the golden files will rest on, checked here where a failure
    // names the PRNG rather than a puzzle.
    final a = Rng(777);
    final b = Rng(777);
    for (var i = 0; i < 500; i++) {
      expect(a.nextUint32(), b.nextUint32(), reason: 'diverged at draw $i');
    }
  });
}

/// The next [count] raw draws from [rng].
List<int> draws(Rng rng, int count) => [
  for (var i = 0; i < count; i++) rng.nextUint32(),
];

/// `0..length-1`, shuffled by [rng].
List<int> shuffled(Rng rng, int length) {
  final list = [for (var i = 0; i < length; i++) i];
  rng.shuffle(list);
  return list;
}
