// The spec is three numbers and some arithmetic, but the arithmetic is what
// every later Tracks file indexes the grid with, so a transposed row and
// column here would be wrong everywhere at once and plausibly so.

import 'package:puzzle_engine/src/tracks/tracks_spec.dart';
import 'package:test/test.dart';

void main() {
  test('the named sizes are square and labelled the way an ID spells them', () {
    expect(TracksSpec.s5x5.label, '5x5');
    expect(TracksSpec.s7x7.label, '7x7');
    expect(TracksSpec.s9x9.label, '9x9');
    expect(TracksSpec.s5x5.cells, 25);
    expect(TracksSpec.s7x7.cells, 49);
    expect(TracksSpec.s9x9.cells, 81);
  });

  test('supported lists exactly the three sizes, smallest first', () {
    expect(TracksSpec.supported, [
      TracksSpec.s5x5,
      TracksSpec.s7x7,
      TracksSpec.s9x9,
    ]);
  });

  test('row, column and index agree for every cell', () {
    for (final spec in TracksSpec.supported) {
      for (var i = 0; i < spec.cells; i++) {
        expect(spec.indexAt(spec.rowOf(i), spec.columnOf(i)), i);
      }
      for (var r = 0; r < spec.side; r++) {
        for (var c = 0; c < spec.side; c++) {
          final i = spec.indexAt(r, c);
          expect(spec.rowOf(i), r);
          expect(spec.columnOf(i), c);
        }
      }
    }
  });

  test('index arithmetic is row-major', () {
    // Row-major, not column-major: (1, 0) on a 5-wide grid is index 5.
    expect(TracksSpec.s5x5.indexAt(1, 0), 5);
    expect(TracksSpec.s5x5.indexAt(0, 1), 1);
    expect(TracksSpec.s7x7.rowOf(24), 3);
    expect(TracksSpec.s7x7.columnOf(24), 3);
  });

  test('equality is by side', () {
    expect(const TracksSpec(7), TracksSpec.s7x7);
    expect(const TracksSpec(7).hashCode, TracksSpec.s7x7.hashCode);
    expect(TracksSpec.s7x7, isNot(TracksSpec.s9x9));
    expect(TracksSpec.s7x7.toString(), contains('7x7'));
  });
}
