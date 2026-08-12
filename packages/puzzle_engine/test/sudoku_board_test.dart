// The board is checked against a second implementation rather than against
// itself. `SudokuBoard` keeps three bitmasks in step across every `place` and
// `remove`, which is fast and is exactly the kind of bookkeeping that stays
// wrong quietly: a mask that is not cleared on `remove` makes a digit look
// illegal, the generator digs a different hole, and the puzzle comes out merely
// different rather than obviously broken.
//
// `NaiveBoard` answers the same questions by rescanning the grid, so it has no
// bookkeeping to get wrong. It is deliberately the slow, obvious version — its
// job is to disagree.

import 'package:puzzle_engine/src/rng.dart';
import 'package:puzzle_engine/src/sudoku_board.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:test/test.dart';

/// Every spec the engine names, so each property is checked on both shapes.
const List<SudokuSpec> specs = [SudokuSpec.s9x9, SudokuSpec.s6x6];

void main() {
  group('SudokuSpec', () {
    test('derives its shape from the box', () {
      expect(SudokuSpec.s9x9.digits, 9);
      expect(SudokuSpec.s9x9.cells, 81);
      expect(SudokuSpec.s9x9.label, '9x9');
      expect(SudokuSpec.s9x9.fullMask, 0x1FF);

      expect(SudokuSpec.s6x6.digits, 6);
      expect(SudokuSpec.s6x6.cells, 36);
      expect(SudokuSpec.s6x6.label, '6x6');
      expect(SudokuSpec.s6x6.fullMask, 0x3F);
    });

    test('numbers 9x9 boxes in reading order', () {
      const spec = SudokuSpec.s9x9;
      expect(spec.boxOf(spec.indexAt(0, 0)), 0);
      expect(spec.boxOf(spec.indexAt(0, 8)), 2);
      expect(spec.boxOf(spec.indexAt(4, 4)), 4);
      expect(spec.boxOf(spec.indexAt(8, 8)), 8);
    });

    test('6x6 boxes are 2 rows by 3 columns, not 3 by 2', () {
      // The 6x6 box is the one shape in the engine that is not square, so it is
      // the one a reader can get backwards. Rows 0-1 by columns 0-2 is one box;
      // row 2 and column 3 are outside it.
      const spec = SudokuSpec.s6x6;
      expect(spec.boxOf(spec.indexAt(0, 0)), 0);
      expect(spec.boxOf(spec.indexAt(1, 2)), 0);
      expect(spec.boxOf(spec.indexAt(0, 3)), 1);
      expect(spec.boxOf(spec.indexAt(2, 0)), 2);
      expect(spec.boxOf(spec.indexAt(5, 5)), 5);
    });

    test('row, column and index agree with each other', () {
      for (final spec in specs) {
        for (var index = 0; index < spec.cells; index++) {
          expect(spec.indexAt(spec.rowOf(index), spec.colOf(index)), index);
        }
      }
    });

    test('two specs of the same shape are the same spec', () {
      expect(const SudokuSpec(boxRows: 3, boxCols: 3), SudokuSpec.s9x9);
      expect(
        const SudokuSpec(boxRows: 3, boxCols: 3).hashCode,
        SudokuSpec.s9x9.hashCode,
      );
      expect(const SudokuSpec(boxRows: 3, boxCols: 2), isNot(SudokuSpec.s6x6));
    });
  });

  group('placement', () {
    test('a placed digit is visible and counted', () {
      final board = SudokuBoard(SudokuSpec.s9x9);
      expect(board.place(0, 5), isTrue);
      expect(board.digitAt(0), 5);
      expect(board.filledCount, 1);
      expect(board.isFull, isFalse);
    });

    test('a digit blocks its own row, column and box', () {
      const spec = SudokuSpec.s9x9;
      final board = SudokuBoard(spec)..place(spec.indexAt(4, 4), 7);

      expect(board.place(spec.indexAt(4, 0), 7), isFalse); // same row
      expect(board.place(spec.indexAt(0, 4), 7), isFalse); // same column
      expect(board.place(spec.indexAt(3, 3), 7), isFalse); // same box
      expect(board.place(spec.indexAt(0, 0), 7), isTrue); // none of the three
    });

    test('6x6: a box covers two rows and three columns', () {
      const spec = SudokuSpec.s6x6;
      final board = SudokuBoard(spec)..place(spec.indexAt(0, 0), 4);

      // Inside the box: rows 0-1 by columns 0-2.
      expect(board.candidateMask(spec.indexAt(1, 2)) & bitFor(4), 0);
      // Row 2 is the next box down. Columns 1 and 2 still lose the 4 to the
      // column rule, but column 3 keeps it — which is what tells a 2x3 box
      // from a 3x2 one.
      expect(board.candidateMask(spec.indexAt(2, 0)) & bitFor(4), 0);
      expect(board.candidateMask(spec.indexAt(2, 1)) & bitFor(4), bitFor(4));
      expect(board.candidateMask(spec.indexAt(2, 3)) & bitFor(4), bitFor(4));
    });

    test('a rejected placement changes nothing', () {
      const spec = SudokuSpec.s9x9;
      final board = SudokuBoard(spec)..place(0, 3);
      final before = board.toClueString();

      expect(board.place(1, 3), isFalse);
      expect(board.place(0, 4), isFalse, reason: 'the cell is occupied');
      expect(board.toClueString(), before);
      expect(board.filledCount, 1);
      expect(board.candidateMask(1), spec.fullMask & ~bitFor(3));
    });

    test('an index or digit outside the grid is an error, not a refusal', () {
      // The rules can refuse a move. An index of 81 is not a move.
      final board = SudokuBoard(SudokuSpec.s9x9);
      expect(() => board.place(81, 1), throwsRangeError);
      expect(() => board.place(-1, 1), throwsRangeError);
      expect(() => board.place(0, 0), throwsRangeError);
      expect(() => board.place(0, 10), throwsRangeError);
      expect(() => board.remove(81), throwsRangeError);

      final small = SudokuBoard(SudokuSpec.s6x6);
      expect(() => small.place(0, 7), throwsRangeError);
      expect(() => small.place(36, 1), throwsRangeError);
    });

    test('remove puts the digit back in circulation', () {
      const spec = SudokuSpec.s9x9;
      final board = SudokuBoard(spec)..place(spec.indexAt(4, 4), 7);
      board.remove(spec.indexAt(4, 4));

      expect(board.digitAt(spec.indexAt(4, 4)), 0);
      expect(board.filledCount, 0);
      expect(board.place(spec.indexAt(4, 0), 7), isTrue);
    });

    test('removing an empty cell is allowed and counts for nothing', () {
      final board = SudokuBoard(SudokuSpec.s9x9)..place(0, 1);
      board
        ..remove(5)
        ..remove(5);
      expect(board.filledCount, 1);
    });

    test('a filled cell has no candidates', () {
      final board = SudokuBoard(SudokuSpec.s9x9)..place(0, 1);
      expect(board.candidateMask(0), 0);
      board.remove(0);
      expect(board.candidateMask(0), SudokuSpec.s9x9.fullMask);
    });

    test('a full board reports itself full', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s6x6, solved6x6);
      expect(board.isFull, isTrue);
      expect(board.filledCount, 36);
      for (var index = 0; index < 36; index++) {
        expect(board.candidateMask(index), 0);
      }
    });
  });

  group('candidateMask', () {
    for (final spec in specs) {
      test('agrees with the naive board over 10000 ${spec.label} grids', () {
        // The done-criterion in `PLAN-phase-2.md` §6. Seeded from `Rng`, so a
        // failure is reproducible from the seed named in the message.
        //
        // The comparison collects the first disagreement instead of calling
        // `expect` two million times: at that count the matcher costs more than
        // everything it is checking, and a suite people stop running catches
        // nothing.
        final peers = peerTable(spec);
        String? disagreement;

        for (var seed = 0; seed < 10000 && disagreement == null; seed++) {
          final rng = Rng(seed);
          final fast = SudokuBoard(spec);
          final naive = NaiveBoard(spec, peers);

          // Enough attempts to fill a good part of the grid, including some
          // that are refused, so both boards also see rejected moves.
          for (var attempt = 0; attempt < spec.cells; attempt++) {
            final index = rng.nextInt(spec.cells);
            final digit = rng.nextInt(spec.digits) + 1;
            if (fast.place(index, digit) != naive.place(index, digit)) {
              disagreement = 'seed $seed: placing $digit at $index';
              break;
            }
          }

          // Then empty a few cells, which is where a stale mask would show.
          for (var attempt = 0; attempt < spec.digits; attempt++) {
            final index = rng.nextInt(spec.cells);
            fast.remove(index);
            naive.remove(index);
          }

          for (
            var index = 0;
            index < spec.cells && disagreement == null;
            index++
          ) {
            if (fast.candidateMask(index) != naive.candidateMask(index)) {
              disagreement =
                  'seed $seed: cell $index, ${fast.candidateMask(index)} '
                  'against ${naive.candidateMask(index)}\n'
                  '  ${fast.toClueString()}';
            }
          }
          if (fast.filledCount != naive.filledCount ||
              fast.toClueString() != naive.toClueString()) {
            disagreement ??= 'seed $seed: the grids themselves differ';
          }
        }

        expect(disagreement, isNull, reason: disagreement);
      });
    }
  });

  group('the clue string', () {
    test('round-trips unchanged', () {
      for (final clues in [solved6x6, puzzle6x6, solved9x9, puzzle9x9]) {
        final spec = clues.length == 36 ? SudokuSpec.s6x6 : SudokuSpec.s9x9;
        expect(SudokuBoard.fromClues(spec, clues).toClueString(), clues);
      }
    });

    test('an empty board is all dots', () {
      expect(SudokuBoard(SudokuSpec.s6x6).toClueString(), '.' * 36);
      expect(SudokuBoard(SudokuSpec.s9x9).toClueString(), '.' * 81);
    });

    test('rejects the wrong length', () {
      expect(
        () => SudokuBoard.fromClues(SudokuSpec.s9x9, '.' * 80),
        throwsFormatException,
      );
      expect(
        () => SudokuBoard.fromClues(SudokuSpec.s9x9, '.' * 82),
        throwsFormatException,
      );
      expect(
        () => SudokuBoard.fromClues(SudokuSpec.s9x9, solved6x6),
        throwsFormatException,
        reason: 'a 6x6 grid is not a short 9x9 one',
      );
    });

    test('rejects a character that is not a dot or a digit in range', () {
      // '٤' is an Eastern Arabic four: a digit to a human and to `int.parse`,
      // but not to a format that is one byte per cell.
      for (final bad in ['0', 'x', ' ', '-', '٤']) {
        expect(
          () => SudokuBoard.fromClues(SudokuSpec.s9x9, cluesFrom(bad, 81)),
          throwsFormatException,
          reason: 'accepted "$bad"',
        );
      }
      expect(
        () => SudokuBoard.fromClues(SudokuSpec.s6x6, cluesFrom('7', 36)),
        throwsFormatException,
        reason: '7 is out of range at 6x6',
      );
      expect(
        () => SudokuBoard.fromClues(SudokuSpec.s9x9, cluesFrom('9', 81)),
        returnsNormally,
        reason: '9 is in range at 9x9',
      );
    });

    test('rejects a grid that already breaks the rules', () {
      const spec = SudokuSpec.s9x9;
      final sameRow = cluesFrom('11', 81);
      final sameColumn = cluesFrom('1........1', 81);
      final sameBox = cluesFrom('1.........1', 81);
      for (final clues in [sameRow, sameColumn, sameBox]) {
        expect(
          () => SudokuBoard.fromClues(spec, clues),
          throwsFormatException,
          reason: clues,
        );
      }
      // Two cells away from each other in all three units is fine.
      expect(
        () => SudokuBoard.fromClues(spec, cluesFrom('1...........1', 81)),
        returnsNormally,
      );
    });

    test('names where the problem is', () {
      // Phase 3 logs this when a cached puzzle fails to load; "invalid" would
      // send someone back to the file with nothing to look for.
      try {
        SudokuBoard.fromClues(SudokuSpec.s9x9, cluesFrom('11', 81));
        fail('expected a FormatException');
      } on FormatException catch (error) {
        expect(error.offset, 1);
        expect(error.message, contains('row 0, column 1'));
      }
    });
  });

  group('copy', () {
    test('is independent of the board it came from', () {
      final original = SudokuBoard.fromClues(SudokuSpec.s9x9, puzzle9x9);
      final duplicate = original.copy();

      expect(duplicate.toClueString(), original.toClueString());
      expect(duplicate.filledCount, original.filledCount);

      final empty = firstEmpty(duplicate);
      final digit = lowestCandidate(duplicate, empty);
      expect(duplicate.place(empty, digit), isTrue);

      expect(original.digitAt(empty), 0, reason: 'the original changed');
      expect(original.candidateMask(empty) & bitFor(digit), bitFor(digit));
      expect(original.filledCount, duplicate.filledCount - 1);
    });

    test('carries the masks, not just the digits', () {
      // A copy that rebuilt itself from the clue string would pass the test
      // above and still be wrong here, with every mask left empty.
      const spec = SudokuSpec.s9x9;
      final original = SudokuBoard(spec)..place(spec.indexAt(0, 0), 9);
      final duplicate = original.copy();

      expect(duplicate.place(spec.indexAt(0, 1), 9), isFalse);
      expect(duplicate.candidateMask(spec.indexAt(0, 1)) & bitFor(9), 0);
    });
  });
}

/// The bit standing for [digit] in a candidate mask.
int bitFor(int digit) => 1 << (digit - 1);

/// [prefix], padded with dots to a whole grid of [cells].
String cluesFrom(String prefix, int cells) => prefix.padRight(cells, '.');

/// The first empty cell of [board].
int firstEmpty(SudokuBoard board) {
  for (var index = 0; index < board.spec.cells; index++) {
    if (board.digitAt(index) == 0) return index;
  }
  throw StateError('the board is full');
}

/// The lowest digit that could go in the empty cell at [index].
int lowestCandidate(SudokuBoard board, int index) {
  final mask = board.candidateMask(index);
  for (var digit = 1; digit <= board.spec.digits; digit++) {
    if (mask & bitFor(digit) != 0) return digit;
  }
  throw StateError('cell $index has no candidates');
}

/// For each cell, every other cell sharing its row, column or box.
///
/// Built once per spec rather than per board: the naive board is allowed to be
/// slow, but not so slow that the 10 000-grid comparison stops being run.
List<List<int>> peerTable(SudokuSpec spec) => [
  for (var index = 0; index < spec.cells; index++)
    [
      for (var other = 0; other < spec.cells; other++)
        if (other != index &&
            (spec.rowOf(other) == spec.rowOf(index) ||
                spec.colOf(other) == spec.colOf(index) ||
                spec.boxOf(other) == spec.boxOf(index)))
          other,
    ],
];

/// The same board, implemented the slow obvious way.
///
/// It keeps the digits and nothing else, and answers every question by looking
/// at the cells around one. A `Set` is banned in `lib/` because its iteration
/// order is not guaranteed and the engine's output must be; this one is only
/// ever asked about membership, and it never runs outside a test.
class NaiveBoard {
  NaiveBoard(this.spec, this.peers) : _digits = List<int>.filled(spec.cells, 0);

  final SudokuSpec spec;
  final List<List<int>> peers;
  final List<int> _digits;

  int get filledCount => _digits.where((digit) => digit != 0).length;

  bool place(int index, int digit) {
    if (_digits[index] != 0) return false;
    for (final peer in peers[index]) {
      if (_digits[peer] == digit) return false;
    }
    _digits[index] = digit;
    return true;
  }

  void remove(int index) => _digits[index] = 0;

  int candidateMask(int index) {
    if (_digits[index] != 0) return 0;
    final used = <int>{for (final peer in peers[index]) _digits[peer]};
    var mask = 0;
    for (var digit = 1; digit <= spec.digits; digit++) {
      if (!used.contains(digit)) mask |= bitFor(digit);
    }
    return mask;
  }

  String toClueString() =>
      _digits.map((digit) => digit == 0 ? '.' : '$digit').join();
}

/// A solved 6x6 grid.
const String solved6x6 = '123456456123234561561234345612612345';

/// The same grid with a third of its cells emptied.
const String puzzle6x6 = '.23.56.56.23.34.61.61.34.45.12.12.45';

/// A solved 9x9 grid.
const String solved9x9 =
    '123456789'
    '456789123'
    '789123456'
    '234567891'
    '567891234'
    '891234567'
    '345678912'
    '678912345'
    '912345678';

/// The same grid with a quarter of its cells emptied.
const String puzzle9x9 =
    '.234.678.'
    '456.891.3'
    '78.123.56'
    '2.456.891'
    '.678.123.'
    '891.345.7'
    '34.678.12'
    '6.891.345'
    '.123.567.';
