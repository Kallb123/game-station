// Every fixture here was checked against an independent solution counter
// written in Python from the rules — sets of peers, no bitmasks — so the
// expected counts are not this solver's own opinion of itself. Its node counts
// agreed with this implementation's exactly, which is the stronger check: it
// means both make the same cell choices in the same order.
//
// The counting solver is the hot path. The generator calls it once per cell it
// digs, and phase 3 shows the result to a child, so "unique" being wrong is the
// difference between a solvable puzzle and one with two answers.

import 'package:puzzle_engine/src/solver.dart';
import 'package:puzzle_engine/src/sudoku_board.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:test/test.dart';

/// A 17-clue 9x9 from the known-minimal collection: the fewest clues a unique
/// Sudoku can have, and so the hardest case for the counter to get right.
const String seventeenClue =
    '.......1.'
    '4........'
    '.2.......'
    '....5.4.7'
    '..8...3..'
    '..1.9....'
    '3..4..2..'
    '.5.1.....'
    '...8.6...';

/// Its one completion.
const String seventeenClueSolution =
    '693784512'
    '487512936'
    '125963874'
    '932651487'
    '568247391'
    '741398625'
    '319475268'
    '856129743'
    '274836159';

/// [seventeenClue] with a legal 5 added at the top left.
///
/// Legal in the sense the board enforces — no 5 in that row, column or box —
/// and still impossible, because the only completion puts a 6 there. Proving
/// that takes real search, which is what separates this from [starvedCell].
const String unsolvableAfterSearch =
    '5......1.'
    '4........'
    '.2.......'
    '....5.4.7'
    '..8...3..'
    '..1.9....'
    '3..4..2..'
    '.5.1.....'
    '...8.6...';

/// A grid whose top-right cell has no candidates at all: its row holds 1 to 8
/// and its column holds the 9.
const String starvedCell =
    '12345678.'
    '........9'
    '.........'
    '.........'
    '.........'
    '.........'
    '.........'
    '.........'
    '.........';

/// A 6x6 with exactly four completions, for the [max] cases.
const String fourSolutions6x6 = '.2.4.6.5.1.3.3.5.1.6.2.4.4.6.2.1.3.5';

/// A 6x6 with one.
const String unique6x6 = '.234.645.123.345.156.234.456.261.345';

/// A solved 6x6, which is its own only completion.
const String solved6x6 = '123456456123234561561234345612612345';

void main() {
  group('counting', () {
    test('a 17-clue 9x9 has exactly one solution', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue);
      expect(countSolutions(board), 1);
    });

    test('a solved board is its own solution', () {
      final board = SudokuBoard.fromClues(
        SudokuSpec.s9x9,
        seventeenClueSolution,
      );
      expect(countSolutions(board), 1);
    });

    test('an empty 9x9 stops at the second solution', () {
      final stats = SearchStats();
      final board = SudokuBoard(SudokuSpec.s9x9);
      expect(countSolutions(board, stats: stats), 2);

      // An empty 9x9 has about 6.7 x 10^21 completions. Finishing in a
      // hundred-odd placements is the proof that `max` stopped the search
      // rather than the grid running out of answers.
      expect(stats.nodes, lessThan(200));
      expect(
        stats.nodes,
        greaterThanOrEqualTo(81),
        reason: 'the first solution alone needs 81 placements',
      );
    });

    test('a lower max stops sooner', () {
      final one = SearchStats();
      final two = SearchStats();
      expect(
        countSolutions(SudokuBoard(SudokuSpec.s9x9), max: 1, stats: one),
        1,
      );
      expect(
        countSolutions(SudokuBoard(SudokuSpec.s9x9), max: 2, stats: two),
        2,
      );
      expect(one.nodes, lessThan(two.nodes));
    });

    test('max caps the count without changing what is below it', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s6x6, fourSolutions6x6);
      expect(countSolutions(board, max: 1), 1);
      expect(countSolutions(board, max: 2), 2);
      expect(countSolutions(board, max: 4), 4);
      expect(
        countSolutions(board, max: 10),
        4,
        reason: 'the grid has four, so a higher ceiling changes nothing',
      );
    });

    test('a 6x6 is counted on its own geometry', () {
      expect(
        countSolutions(SudokuBoard.fromClues(SudokuSpec.s6x6, unique6x6)),
        1,
      );
      expect(
        countSolutions(SudokuBoard.fromClues(SudokuSpec.s6x6, solved6x6)),
        1,
      );
      expect(countSolutions(SudokuBoard(SudokuSpec.s6x6)), 2);
    });
  });

  group('no solutions', () {
    test('a cell with no candidates is refused without searching', () {
      final stats = SearchStats();
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, starvedCell);
      expect(countSolutions(board, stats: stats), 0);
      expect(stats.nodes, 0, reason: 'the dead cell is found before any move');
    });

    test('a legal grid with no completion is refused after searching', () {
      // The board cannot reject this one on placement — the extra 5 breaks no
      // row, column or box — so 0 here is the search's answer, not the board's.
      final stats = SearchStats();
      final board = SudokuBoard.fromClues(
        SudokuSpec.s9x9,
        unsolvableAfterSearch,
      );
      expect(countSolutions(board, stats: stats), 0);
      expect(stats.nodes, greaterThan(100));
    });
  });

  group('the node cap', () {
    test('reports unknown rather than guessing', () {
      final stats = SearchStats();
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue);
      expect(countSolutions(board, maxNodes: 100, stats: stats), -1);
      expect(countSolutions(board, maxNodes: 100), unknownSolutionCount);
      expect(stats.nodes, 100, reason: 'it stops at the cap, not past it');
    });

    test('the same board answers fully when the cap allows it', () {
      // The pair is the point: unknown is a statement about the budget, not
      // about the puzzle.
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue);
      expect(countSolutions(board, maxNodes: 100), unknownSolutionCount);
      expect(countSolutions(board), 1);
    });

    test('a cap large enough to finish is not reached', () {
      final stats = SearchStats();
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue);
      expect(countSolutions(board, stats: stats), 1);
      expect(stats.nodes, lessThan(2000000));
    });
  });

  group("the caller's board", () {
    test('is not modified, whatever the search does to its copy', () {
      for (final clues in [seventeenClue, unsolvableAfterSearch, starvedCell]) {
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, clues);
        final before = board.toClueString();
        final filled = board.filledCount;

        countSolutions(board);
        countSolutions(board, maxNodes: 100);

        expect(board.toClueString(), before, reason: clues);
        expect(board.filledCount, filled, reason: clues);
      }
    });
  });

  group('determinism', () {
    test('two runs over the same board agree, down to the node count', () {
      // The generator digs by asking this question thousands of times. If the
      // answer could vary, the puzzle for a given ID could vary with it.
      for (final clues in [
        seventeenClue,
        unsolvableAfterSearch,
        unique6x6,
        fourSolutions6x6,
      ]) {
        final spec = clues.length == 36 ? SudokuSpec.s6x6 : SudokuSpec.s9x9;
        final first = SearchStats();
        final second = SearchStats();

        final a = countSolutions(
          SudokuBoard.fromClues(spec, clues),
          stats: first,
        );
        final b = countSolutions(
          SudokuBoard.fromClues(spec, clues),
          stats: second,
        );

        expect(a, b, reason: clues);
        expect(first.nodes, second.nodes, reason: clues);
      }
    });

    test('the search order is the frozen one', () {
      // Not sacred numbers, but a tripwire: the MRV tie-break and the low-to-
      // high digit order decide how much work a board costs, and so which
      // boards come back unknown at a given cap. A change here is a change to
      // that boundary, and should be made deliberately rather than noticed
      // later in a golden file. Both counts were reproduced by the independent
      // Python counter, so they describe the algorithm rather than this code.
      final empty = SearchStats();
      final minimal = SearchStats();
      final firstOnly = SearchStats();
      countSolutions(SudokuBoard(SudokuSpec.s9x9), stats: empty);
      countSolutions(
        SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue),
        stats: minimal,
      );
      countSolutions(
        SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue),
        max: 1,
        stats: firstOnly,
      );

      expect(empty.nodes, 91);
      expect(minimal.nodes, 6519);

      // The `max: 1` run is the one that pins the digit order. An exhaustive
      // count visits the same nodes whichever end it starts from, so only a
      // search that stops early can tell 1-to-9 from 9-to-1: reversed, this
      // board takes 1748 nodes instead.
      expect(firstOnly.nodes, 4835);
    });

    test('a board reached by a different route counts the same', () {
      // Same position, built by placing rather than parsing: the answer follows
      // from the grid, not from how the grid arrived.
      final parsed = SudokuBoard.fromClues(SudokuSpec.s9x9, seventeenClue);
      final built = SudokuBoard(SudokuSpec.s9x9);
      for (var index = seventeenClue.length - 1; index >= 0; index--) {
        final digit = parsed.digitAt(index);
        if (digit != 0) built.place(index, digit);
      }

      final parsedStats = SearchStats();
      final builtStats = SearchStats();
      expect(countSolutions(parsed, stats: parsedStats), 1);
      expect(countSolutions(built, stats: builtStats), 1);
      expect(parsedStats.nodes, builtStats.nodes);
    });
  });

  group('arguments', () {
    test('a max or cap below one is a caller mistake', () {
      final board = SudokuBoard(SudokuSpec.s9x9);
      expect(() => countSolutions(board, max: 0), throwsRangeError);
      expect(() => countSolutions(board, max: -1), throwsRangeError);
      expect(() => countSolutions(board, maxNodes: 0), throwsRangeError);
    });
  });
}
