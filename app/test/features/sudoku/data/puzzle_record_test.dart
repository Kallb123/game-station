// The record codec's tests.
//
// Every rejection case is a save file that could exist: a truncated write, a
// hand edit, a record read back against the wrong size. The format is what the
// isolate and the cache both speak (`PLAN-phase-3.md` §4.1), so a value it
// accepts wrongly is a wrong board drawn in front of a child rather than an
// exception in a log.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/features/sudoku/data/puzzle_record.dart';

void main() {
  final small = PuzzleId.parse('sudoku:6x6:easy:0');
  final large = PuzzleId.parse('sudoku:9x9:easy:0');

  /// A real puzzle, so the round trip runs against what the engine writes
  /// rather than against a grid hand-made to suit the parser.
  PuzzleRecord recordFor(PuzzleId id) => PuzzleRecord.of(generateSudoku(id));

  group('encode and decode', () {
    for (final id in [small, large]) {
      test('${id.spec.label} round-trips through the encoded form', () {
        final record = recordFor(id);
        final encoded = record.encode();

        expect(encoded.length, 2 * id.spec.cells + 1);
        expect(encoded[id.spec.cells], PuzzleRecord.separator);
        expect(PuzzleRecord.decode(id.spec, encoded), record);
      });
    }

    test('the decoded halves are the generated puzzle, cell for cell', () {
      final puzzle = generateSudoku(large);

      final record = PuzzleRecord.decode(
        large.spec,
        PuzzleRecord.of(puzzle).encode(),
      );

      expect(record.clues, puzzle.clues);
      expect(record.solution, puzzle.solution);
    });

    test('a record is equal to another holding the same grids', () {
      expect(recordFor(small), recordFor(small));
      expect(recordFor(small).hashCode, recordFor(small).hashCode);
      expect(recordFor(small), isNot(recordFor(large)));
    });
  });

  group('decode rejects', () {
    late String valid;

    setUp(() => valid = recordFor(small).encode());

    void expectRejected(String encoded, {SudokuSpec? spec}) => expect(
      () => PuzzleRecord.decode(spec ?? small.spec, encoded),
      throwsFormatException,
    );

    test('a truncated record', () {
      expectRejected(valid.substring(0, valid.length - 1));
    });

    test('a record with anything appended', () => expectRejected('$valid.'));

    test('an empty string', () => expectRejected(''));

    test('a record read back against the wrong size', () {
      expectRejected(valid, spec: large.spec);
    });

    test('a record with no separator', () {
      expectRejected(valid.replaceFirst(PuzzleRecord.separator, '1'));
    });

    test('a record whose separator is in the wrong place', () {
      // Same characters, same length: only the position moves, which is what a
      // length check alone would let through.
      final at = small.spec.cells;
      expectRejected(
        valid.substring(0, at - 1) +
            PuzzleRecord.separator +
            valid[at - 1] +
            valid.substring(at + 1),
      );
    });

    test('a digit the size does not have', () {
      expectRejected('7${valid.substring(1)}');
    });

    test('a clue that is not a digit at all', () {
      expectRejected('x${valid.substring(1)}');
    });

    test('a solution with a hole in it', () {
      final at = small.spec.cells + 1;
      expectRejected(
        valid.substring(0, at) +
            PuzzleRecord.emptyCell +
            valid.substring(at + 1),
      );
    });

    test('a solution that repeats a digit in a row', () {
      // The two cells are in the same row, so swapping one for the other makes
      // a grid that is still the right length and the right alphabet.
      final solution = recordFor(small).solution;
      final broken = solution.replaceRange(1, 2, solution[0]);

      expectRejected('${recordFor(small).clues}|$broken');
    });

    test('a clue the solution contradicts', () {
      final record = recordFor(small);
      final at = record.clues.indexOf(PuzzleRecord.emptyCell);
      final wrong = record.solution[at] == '1' ? '2' : '1';

      expectRejected(
        '${record.clues.replaceRange(at, at + 1, wrong)}|${record.solution}',
      );
    });
  });
}
