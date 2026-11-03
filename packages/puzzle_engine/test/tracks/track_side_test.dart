// The bits and the six pieces are the vocabulary of every Tracks file, and the
// order of `pieces` is frozen because a search tries them in it.

import 'package:puzzle_engine/src/tracks/track_side.dart';
import 'package:test/test.dart';

int bitCount(int mask) {
  var n = 0;
  for (final side in TrackSide.all) {
    if (mask & side != 0) n++;
  }
  return n;
}

void main() {
  test('the four sides are distinct single bits, in a fixed order', () {
    expect(TrackSide.all, [
      TrackSide.north,
      TrackSide.east,
      TrackSide.south,
      TrackSide.west,
    ]);
    expect(
      [TrackSide.north, TrackSide.east, TrackSide.south, TrackSide.west],
      [1, 2, 4, 8],
    );
  });

  test('opposite swaps north with south and east with west', () {
    expect(TrackSide.opposite(TrackSide.north), TrackSide.south);
    expect(TrackSide.opposite(TrackSide.south), TrackSide.north);
    expect(TrackSide.opposite(TrackSide.east), TrackSide.west);
    expect(TrackSide.opposite(TrackSide.west), TrackSide.east);
    for (final side in TrackSide.all) {
      expect(TrackSide.opposite(TrackSide.opposite(side)), side);
    }
  });

  test('opposite throws for anything but a single side', () {
    for (final bad in [0, 3, 5, 15, 16, -1]) {
      expect(
        () => TrackSide.opposite(bad),
        throwsArgumentError,
        reason: '$bad',
      );
    }
  });

  test('the six pieces are in the frozen order', () {
    // NS, EW, NE, ES, SW, NW.
    expect(TrackSide.pieces, [5, 10, 3, 6, 12, 9]);
  });

  test('the pieces are exactly the masks with two bits set', () {
    expect(TrackSide.pieces.toSet().length, 6);
    for (final piece in TrackSide.pieces) {
      expect(bitCount(piece), 2, reason: '$piece');
    }
    final twoBit = [
      for (var mask = 0; mask < 16; mask++)
        if (bitCount(mask) == 2) mask,
    ];
    expect([...TrackSide.pieces]..sort(), twoBit);
  });

  test('isPiece accepts the six and nothing else', () {
    for (var mask = -1; mask <= 16; mask++) {
      expect(
        TrackSide.isPiece(mask),
        TrackSide.pieces.contains(mask),
        reason: '$mask',
      );
    }
    expect(TrackSide.isPiece(0), isFalse);
    expect(TrackSide.isPiece(TrackSide.north), isFalse);
    expect(TrackSide.isPiece(7), isFalse);
    expect(TrackSide.isPiece(15), isFalse);
    expect(TrackSide.isPiece(TrackSide.north | TrackSide.south), isTrue);
  });
}
