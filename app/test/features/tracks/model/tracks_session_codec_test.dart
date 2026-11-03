// The stored format's tests.
//
// These strings are the frozen half of the session (`PLAN-phase-9-tracks.md`
// §4.11): once a child's `save.json` holds them, a change here is a schema
// migration. The exact-spelling assertions exist for that reason — a round trip
// alone would still pass if both halves of the codec moved together, which is
// exactly the change that breaks every file already written.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/features/tracks/model/tracks_session_codec.dart';

void main() {
  const small = TracksSpec.s5x5;
  const large = TracksSpec.s9x9;

  group('the cells string', () {
    test('is one lowercase hex character per cell', () {
      final masks = List<int>.filled(small.cells, 0);
      masks[0] = 5;
      masks[1] = 10;
      masks[2] = 15;
      masks[3] = 9;

      final encoded = encodeTracksCells(small, masks);

      expect(encoded.length, small.cells);
      expect(encoded.substring(0, 5), '5af90');
    });

    test('round-trips every mask value on both sizes', () {
      for (final spec in [small, large]) {
        final masks = [for (var i = 0; i < spec.cells; i++) i % 16];
        expect(decodeTracksCells(spec, encodeTracksCells(spec, masks)), masks);
      }
    });

    test('refuses the wrong number of masks', () {
      expect(
        () => encodeTracksCells(small, List<int>.filled(small.cells - 1, 0)),
        throwsArgumentError,
      );
    });

    test('refuses a mask outside 0..15', () {
      for (final bad in [-1, 16]) {
        final masks = List<int>.filled(small.cells, 0)..[3] = bad;
        expect(() => encodeTracksCells(small, masks), throwsRangeError);
      }
    });

    test('refuses the wrong length when decoding', () {
      expect(
        () => decodeTracksCells(small, '0' * (small.cells - 1)),
        throwsFormatException,
      );
      expect(
        () => decodeTracksCells(small, '0' * (small.cells + 1)),
        throwsFormatException,
      );
    });

    test('refuses uppercase hex and other characters', () {
      final upper = 'A${'0' * (small.cells - 1)}';
      final other = 'g${'0' * (small.cells - 1)}';
      expect(() => decodeTracksCells(small, upper), throwsFormatException);
      expect(() => decodeTracksCells(small, other), throwsFormatException);
    });
  });

  group('the marks string', () {
    test('is empty when nothing is marked', () {
      expect(
        encodeTracksMarks(small, List<bool>.filled(small.cells, false)),
        '',
      );
      expect(
        decodeTracksMarks(small, ''),
        List<bool>.filled(small.cells, false),
      );
    });

    test('is one 0 or 1 per cell otherwise, and round-trips', () {
      final marks = List<bool>.filled(small.cells, false)
        ..[0] = true
        ..[7] = true;

      final encoded = encodeTracksMarks(small, marks);

      expect(encoded, '1000000100000000000000000');
      expect(decodeTracksMarks(small, encoded), marks);
    });

    test('refuses the wrong number of marks', () {
      expect(() => encodeTracksMarks(small, [true]), throwsArgumentError);
    });

    test('refuses the wrong length and other characters when decoding', () {
      expect(() => decodeTracksMarks(small, '1'), throwsFormatException);
      expect(
        () => decodeTracksMarks(small, '2${'0' * (small.cells - 1)}'),
        throwsFormatException,
      );
    });
  });

  group('a move', () {
    const move = TracksCellState(index: 12, mask: 5, marked: false);

    test('encodes as comma-joined index.mask.mark decimals', () {
      final encoded = TracksMove(const [
        move,
        TracksCellState(index: 13, mask: 8, marked: true),
      ]).encode();

      expect(encoded, '12.5.0,13.8.1');
    });

    test('round-trips', () {
      final original = TracksMove(const [
        TracksCellState(index: 0, mask: 0, marked: true),
        move,
        TracksCellState(index: 24, mask: 15 & 12, marked: false),
      ]);

      final decoded = TracksMove.decode(small, original.encode());

      expect(decoded, original);
      expect(decoded.hashCode, original.hashCode);
    });

    test('refuses an empty move', () {
      expect(() => TracksMove(const []), throwsArgumentError);
      expect(() => TracksMove.decode(small, ''), throwsFormatException);
    });

    test('refuses entries out of order or repeated', () {
      expect(
        () => TracksMove.decode(small, '13.5.0,12.5.0'),
        throwsFormatException,
      );
      expect(
        () => TracksMove.decode(small, '12.5.0,12.5.0'),
        throwsFormatException,
      );
      expect(
        () => TracksMove(const [
          TracksCellState(index: 3, mask: 0, marked: false),
          TracksCellState(index: 2, mask: 0, marked: false),
        ]),
        throwsArgumentError,
      );
    });

    test('refuses the wrong field count', () {
      for (final bad in ['12.5', '12.5.0.1', '12', '12.5.0,', ',12.5.0']) {
        expect(
          () => TracksMove.decode(small, bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('refuses a non-canonical decimal', () {
      for (final bad in ['012.5.0', '12.05.0', '+12.5.0', '12.-5.0', 'a.5.0']) {
        expect(
          () => TracksMove.decode(small, bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('refuses an index outside the grid', () {
      expect(() => TracksMove.decode(small, '25.5.0'), throwsFormatException);
      expect(() => TracksMove.decode(small, '24.5.0'), returnsNormally);
    });

    test('refuses a mask above 15 or with more than two bits', () {
      for (final bad in ['3.16.0', '3.7.0', '3.15.0', '3.11.0']) {
        expect(
          () => TracksMove.decode(small, bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });

    test('refuses a mark that is not 0 or 1', () {
      expect(() => TracksMove.decode(small, '3.5.2'), throwsFormatException);
    });
  });
}
