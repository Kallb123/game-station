// The stored format's tests.
//
// These strings are the frozen half of the session (`PLAN-phase-3.md` §3): once
// a child's `save.json` holds them, a change here is a schema migration. The
// exact-spelling assertions below exist for that reason — a round trip alone
// would still pass if both halves of the codec moved together, which is exactly
// the change that breaks every file already written.

import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/features/sudoku/model/session_codec.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

void main() {
  const small = SudokuSpec.s6x6;
  const large = SudokuSpec.s9x9;

  group('the grid string', () {
    test('is one character per cell, "." for an empty one', () {
      final digits = List<int>.filled(small.cells, 0);
      digits[0] = 4;
      digits[small.cells - 1] = 6;

      final encoded = encodeGrid(small, digits);

      expect(encoded.length, small.cells);
      expect(encoded[0], '4');
      expect(encoded[1], '.');
      expect(encoded[small.cells - 1], '6');
    });

    test('round-trips a board of both sizes', () {
      for (final spec in [small, large]) {
        final digits = [
          for (var index = 0; index < spec.cells; index++)
            index % 3 == 0 ? 0 : index % spec.digits + 1,
        ];

        expect(decodeGrid(spec, encodeGrid(spec, digits)), digits);
      }
    });

    test('takes a grid that breaks the rules of Sudoku', () {
      // A child's wrong digit repeats one in its row, and `SudokuBoard` would
      // refuse to hold it (`PLAN-phase-3.md` §4.3). This is a board, not a
      // board that has to be solvable.
      final digits = List<int>.filled(large.cells, 0);
      digits[0] = 5;
      digits[1] = 5;

      expect(decodeGrid(large, encodeGrid(large, digits)), digits);
    });

    test('rejects a truncated string rather than decoding it', () {
      final valid = encodeGrid(large, List<int>.filled(large.cells, 0));

      expect(
        () => decodeGrid(large, valid.substring(0, valid.length - 1)),
        throwsFormatException,
      );
    });

    test('rejects a string read back against the wrong size', () {
      final valid = encodeGrid(small, List<int>.filled(small.cells, 0));

      expect(() => decodeGrid(large, valid), throwsFormatException);
    });

    test('rejects a digit the size does not have', () {
      final valid = encodeGrid(small, List<int>.filled(small.cells, 0));

      expect(
        () => decodeGrid(small, '7${valid.substring(1)}'),
        throwsFormatException,
      );
    });

    test('rejects a character that is not a digit at all', () {
      final valid = encodeGrid(small, List<int>.filled(small.cells, 0));

      expect(
        () => decodeGrid(small, 'x${valid.substring(1)}'),
        throwsFormatException,
      );
      expect(
        () => decodeGrid(small, '0${valid.substring(1)}'),
        throwsFormatException,
      );
    });

    test('refuses to encode a list that is not one entry per cell', () {
      expect(
        () => encodeGrid(large, List<int>.filled(small.cells, 0)),
        throwsArgumentError,
      );
    });

    test('refuses to encode a digit the size does not have', () {
      // Unchecked, a 7 in a 6x6 would encode fine and a 10 in a 9x9 would
      // encode to ":" — a save this same file then refuses to read back.
      final digits = List<int>.filled(small.cells, 0);
      digits[0] = small.digits + 1;

      expect(() => encodeGrid(small, digits), throwsRangeError);
    });
  });

  group('the notes string', () {
    test('is empty when no cell has a note', () {
      expect(encodeNotes(large, List<int>.filled(large.cells, 0)), '');
    });

    test('decodes the empty string to a note-free board', () {
      expect(decodeNotes(large, ''), List<int>.filled(large.cells, 0));
    });

    test('is two base-36 characters per cell, zero-padded', () {
      final notes = List<int>.filled(large.cells, 0);
      notes[0] = 0;
      notes[1] = 35;
      notes[2] = 36;
      notes[3] = large.fullMask; // 511 = 14 * 36 + 7

      final encoded = encodeNotes(large, notes);

      expect(encoded.length, 2 * large.cells);
      expect(encoded.substring(0, 8), '000z10e7');
    });

    test('round-trips every mask a cell can hold, at both sizes', () {
      for (final spec in [small, large]) {
        final notes = [
          for (var index = 0; index < spec.cells; index++)
            index % (spec.fullMask + 1),
        ];

        expect(decodeNotes(spec, encodeNotes(spec, notes)), notes);
      }
    });

    test('rejects a truncated string rather than decoding it', () {
      final valid = encodeNotes(large, [
        for (var index = 0; index < large.cells; index++) 1,
      ]);

      expect(
        () => decodeNotes(large, valid.substring(0, valid.length - 2)),
        throwsFormatException,
      );
    });

    test('rejects a character outside 0-9a-z, uppercase included', () {
      final valid = encodeNotes(large, [
        for (var index = 0; index < large.cells; index++) 1,
      ]);

      expect(
        () => decodeNotes(large, 'A${valid.substring(1)}'),
        throwsFormatException,
      );
      expect(
        () => decodeNotes(large, '-${valid.substring(1)}'),
        throwsFormatException,
      );
    });

    test('rejects a mask holding a digit the size does not have', () {
      final notes = List<int>.filled(small.cells, 0);
      notes[0] = small.fullMask;
      final valid = encodeNotes(small, notes);

      // The same string read back as a 6x6 is fine; the mask below has a bit
      // for digit 7, which a 6x6 does not have.
      expect(decodeNotes(small, valid)[0], small.fullMask);
      expect(
        () => decodeNotes(small, '20${valid.substring(2)}'),
        throwsFormatException,
      );
    });

    test('refuses to encode a mask the size does not have', () {
      final notes = List<int>.filled(small.cells, 0);
      notes[0] = small.fullMask + 1;

      expect(() => encodeNotes(small, notes), throwsRangeError);
    });
  });

  group('an undo entry', () {
    test('is "<index>.<digit>.<mask>"', () {
      const move = SudokuMove(index: 42, digit: 7, notes: 260);

      expect(move.encode(), '42.7.260');
    });

    test('round-trips through its encoded form', () {
      const moves = [
        SudokuMove(index: 0, digit: 0, notes: 0),
        SudokuMove(index: 80, digit: 9, notes: 511),
      ];

      for (final move in moves) {
        expect(SudokuMove.decode(large, move.encode()), move);
      }
    });

    test('compares by value', () {
      const move = SudokuMove(index: 1, digit: 2, notes: 3);

      expect(move, const SudokuMove(index: 1, digit: 2, notes: 3));
      expect(
        move.hashCode,
        const SudokuMove(index: 1, digit: 2, notes: 3).hashCode,
      );
      expect(move, isNot(const SudokuMove(index: 1, digit: 2, notes: 4)));
    });

    test('rejects the wrong number of fields', () {
      expect(() => SudokuMove.decode(large, '1.2'), throwsFormatException);
      expect(() => SudokuMove.decode(large, '1.2.3.4'), throwsFormatException);
      expect(() => SudokuMove.decode(large, ''), throwsFormatException);
    });

    test('rejects a field that is not an unsigned decimal', () {
      expect(() => SudokuMove.decode(large, '-1.2.3'), throwsFormatException);
      expect(() => SudokuMove.decode(large, '1.+2.3'), throwsFormatException);
      expect(() => SudokuMove.decode(large, '01.2.3'), throwsFormatException);
      expect(() => SudokuMove.decode(large, '1..3'), throwsFormatException);
      expect(() => SudokuMove.decode(large, 'x.2.3'), throwsFormatException);
    });

    test('rejects a cell, digit or mask outside the grid', () {
      expect(() => SudokuMove.decode(small, '36.1.0'), throwsFormatException);
      expect(() => SudokuMove.decode(small, '0.7.0'), throwsFormatException);
      expect(() => SudokuMove.decode(small, '0.1.64'), throwsFormatException);
    });
  });
}
