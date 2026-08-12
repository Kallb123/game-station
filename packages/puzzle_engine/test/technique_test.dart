// Every fixture here is a position reached while solving a real dug puzzle,
// kept because at that position exactly one technique makes progress. That is
// what makes the table a test of each technique rather than of the solver as a
// whole: if a technique is deleted, its fixture stops being a position the
// solver can advance, and the assertion on which technique fired fails.
//
// The deductions are not taken on the technique solver's word. Every
// elimination is put back on the board and handed to `countSolutions`, which
// must report that the grid then has no solution at all — an independent
// refutation by search, from PR 3's solver, which was itself checked against a
// counter written separately in Python. Every placement is checked the same
// way, by asking which digit leaves the grid solvable. A technique that ruled
// out a digit the puzzle needs would fail there, not merely disagree with a
// number someone typed into this file.

import 'package:puzzle_engine/src/solver.dart';
import 'package:puzzle_engine/src/sudoku_board.dart';
import 'package:puzzle_engine/src/sudoku_spec.dart';
import 'package:puzzle_engine/src/technique_solver.dart';
import 'package:test/test.dart';

/// A position where [technique] is the cheapest — and so the only — progress
/// available, together with the exact deduction it makes there.
class Fixture {
  /// A position where the technique places [digit] at [index].
  const Fixture.places(this.technique, this.clues, this.index, this.digit)
    : eliminations = const [];

  /// A position where the technique rules out [eliminations] and places
  /// nothing.
  const Fixture.eliminates(this.technique, this.clues, this.eliminations)
    : index = -1,
      digit = 0;

  final Technique technique;
  final String clues;
  final int index;
  final int digit;
  final List<Elimination> eliminations;
}

/// One fixture per technique, in tier order.
///
/// All are 9x9: a hidden triple cannot be the first available technique on a
/// 6x6 at all, for the reason recorded beside that fixture, and the rest are
/// size generic. The 6x6 checks live in their own group below rather than
/// being duplicated here.
const List<Fixture> fixtures = [
  Fixture.places(
    Technique.nakedSingle,
    '.25.....6'
    '.7.....34'
    '.1.46.285'
    '137.....2'
    '.423...67'
    '..6..2453'
    '.61.73..8'
    '..39.46..'
    '754..1..9',
    20,
    9,
  ),
  Fixture.places(
    Technique.hiddenSingle,
    '.2...971.'
    '6.81..93.'
    '.1..6.2..'
    '...5....2'
    '.4.39....'
    '.96...4..'
    '..12..5.8'
    '.8.....7.'
    '....8.3..',
    8,
    6,
  ),
  Fixture.eliminates(
    Technique.nakedPair,
    '.2...971.'
    '..8.259.4'
    '.....72.5'
    '.375.6...'
    '...3.8...'
    '.....24..'
    '9612..5..'
    '....5...1'
    '.5..81.2.',
    [
      Elimination(58, 3),
      Elimination(58, 4),
      Elimination(66, 4),
      Elimination(75, 4),
    ],
  ),
  Fixture.eliminates(
    Technique.hiddenPair,
    '.354..761'
    '7..5..498'
    '.846.7253'
    '.4....516'
    '..794.382'
    '......974'
    '4....2637'
    '8...6.145'
    '6....4829',
    [
      Elimination(41, 1),
      Elimination(50, 1),
      Elimination(50, 3),
      Elimination(50, 8),
    ],
  ),
  Fixture.eliminates(
    Technique.pointingPair,
    '216954783'
    '..8132.4.'
    '.43687.21'
    '..2..531.'
    '437816295'
    '1.5..34..'
    '.2..61...'
    '6....9..2'
    '3....8..4',
    [Elimination(60, 5), Elimination(69, 5), Elimination(78, 5)],
  ),
  Fixture.eliminates(
    Technique.boxLineReduction,
    '871962435'
    '359874162'
    '246531789'
    '96.1.3...'
    '12.4.53.6'
    '4356.7...'
    '7..3.68..'
    '...2.8...'
    '.8.749...',
    [
      Elimination(61, 1),
      Elimination(62, 1),
      Elimination(70, 1),
      Elimination(71, 1),
    ],
  ),
  Fixture.eliminates(
    Technique.nakedTriple,
    '187956423'
    '...732186'
    '326481..9'
    '2..8.93.7'
    '.93217.64'
    '...5.3..2'
    '4.21956.8'
    '..13.8.45'
    '...6.4..1',
    [
      Elimination(28, 4),
      Elimination(28, 5),
      Elimination(45, 8),
      Elimination(46, 4),
    ],
  ),
  // A hidden triple is only ever the *first* available technique on a unit
  // with seven or more empty cells. With six or fewer, the three cells the
  // triple does not occupy hold exactly the unit's other missing digits, which
  // is a naked subset of three or fewer — and every one of those is tried
  // before this. That is why there is no 6x6 fixture here, and why this one
  // sits in a nearly full 9x9 with one wide-open box.
  Fixture.eliminates(
    Technique.hiddenTriple,
    '715.3.9.6'
    '648...3.2'
    '3926....5'
    '.87.46..3'
    '4.18....9'
    '....1...8'
    '25..67891'
    '....9.527'
    '.79..5634',
    [
      Elimination(12, 1),
      Elimination(30, 2),
      Elimination(48, 2),
      Elimination(48, 3),
    ],
  ),
  Fixture.eliminates(
    Technique.xWing,
    '681492753'
    '9....5..4'
    '54.8.7..9'
    '359278416'
    '.64351.9.'
    '1..9463.5'
    '.95..463.'
    '43...95.1'
    '.1652394.',
    [Elimination(54, 7), Elimination(62, 7)],
  ),
];

/// A 9x9 with one solution that the techniques cannot finish: the T4 case,
/// assigned by exclusion rather than detected (`PLAN-phase-2.md` §4.5).
const String expert9x9 =
    '.42..3...'
    '..5..4..9'
    '....7....'
    '...7..6..'
    '46....79.'
    '9...4..15'
    '1.....3.8'
    '..9.2..6.'
    '.8.....4.';

/// A 6x6 that needs a technique above singles, with one solution.
const String medium6x6 = '..652...........1.3....4164...5.3...';

/// A 6x6 with one solution that the techniques cannot finish.
const String expert6x6 = '......2....1....5...43....6...3.156.';

void main() {
  group('each technique on the fixture where it is the only progress', () {
    for (final fixture in fixtures) {
      test('${fixture.technique.name} makes its deduction', () {
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, fixture.clues);
        expect(
          countSolutions(board),
          1,
          reason: 'a fixture has to be a real puzzle, not just a grid',
        );

        final step = nextStep(board);
        expect(step, isNotNull);
        expect(
          step!.technique,
          fixture.technique,
          reason:
              'the fixture exists to leave this technique the only progress; '
              'anything else here means a cheaper one now fires, and the '
              'fixture no longer tests what it names',
        );
        expect(step.index, fixture.index);
        expect(step.digit, fixture.digit);
        expect(step.eliminations, fixture.eliminations);
      });

      test('${fixture.technique.name} deduces something true', () {
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, fixture.clues);
        final step = nextStep(board)!;

        if (step.isPlacement) {
          expect(step.digit, _forcedDigitAt(fixture.clues, step.index));
          return;
        }
        for (final elimination in step.eliminations) {
          expect(
            _solutionsWith(fixture.clues, elimination),
            0,
            reason: '$elimination, but the grid still has a solution with it',
          );
        }
      });

      test('${fixture.technique.name} puts the board in its own tier', () {
        // The fixture is a position inside a puzzle of exactly this tier, so
        // the solve from here reaches this technique and stops there. A tier
        // above would mean the fixture also needs something dearer and is
        // testing two things at once.
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, fixture.clues);
        final report = solveWithTechniques(board);

        expect(report.solved, isTrue);
        expect(report.tier, fixture.technique.tier);
        expect(report.steps.first.technique, fixture.technique);
      });
    }
  });

  group('tiers', () {
    test('singles alone are Easy', () {
      for (final fixture in fixtures) {
        if (fixture.technique.tier != Difficulty.easy) continue;
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, fixture.clues);
        final report = solveWithTechniques(board);

        expect(report.tier, Difficulty.easy);
        for (final step in report.steps) {
          expect(
            step.technique.tier,
            Difficulty.easy,
            reason: 'an Easy solve may only use singles',
          );
        }
      }
    });

    test('a board needing an X-wing is Hard', () {
      final fixture = fixtures.firstWhere(
        (f) => f.technique == Technique.xWing,
      );
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, fixture.clues);
      final report = solveWithTechniques(board);

      expect(report.tier, Difficulty.hard);
      expect(
        report.steps.any((step) => step.technique == Technique.xWing),
        isTrue,
      );
    });

    test('a board technique cannot finish is Expert, and says so', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, expert9x9);
      expect(countSolutions(board), 1, reason: 'it is solvable by search');

      final report = solveWithTechniques(board);
      expect(report.solved, isFalse);
      expect(report.tier, Difficulty.expert);
      expect(
        report.steps,
        isNotEmpty,
        reason:
            'Expert means the techniques do not finish it, not that they '
            'never bite: this one makes progress and then stops',
      );
    });

    test('a board no technique touches at all is Expert with no steps', () {
      // An empty grid is the extreme of the same case: every digit is possible
      // in every cell, so nothing is a single, nothing is confined to a pair of
      // cells, and no digit is restricted to one line of a box. Every
      // technique returns nothing and the report is Expert by exclusion.
      //
      // It stands in for a *puzzle* that stops all nine at move one, which is
      // rarer than it sounds: 5000 minimal grids dug while building this test
      // all offered at least one elimination on the opening position, so no
      // such fixture is committed here. See `PLAN-phase-2.md` §6, PR 4.
      final report = solveWithTechniques(SudokuBoard(SudokuSpec.s9x9));

      expect(report.solved, isFalse);
      expect(report.tier, Difficulty.expert);
      expect(report.steps, isEmpty);
      expect(nextStep(SudokuBoard(SudokuSpec.s9x9)), isNull);
    });

    test('a solved board is solved, at the cheapest tier', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, expert9x9);
      final solution = _solutionOf(board);
      final report = solveWithTechniques(solution);

      expect(report.solved, isTrue);
      expect(report.tier, Difficulty.easy, reason: 'it needed no technique');
      expect(report.steps, isEmpty);
      expect(nextStep(solution), isNull);
    });

    test('the techniques are declared in tier order', () {
      // The solver reads the tier off the first technique that fires, which is
      // only the cheapest available if the enum is ordered. Nothing else
      // enforces it, and reordering the enum is a one-line change that would
      // otherwise mislabel every puzzle the generator judges.
      var previous = Difficulty.easy;
      for (final technique in Technique.values) {
        expect(
          technique.tier.index,
          greaterThanOrEqualTo(previous.index),
          reason: '${technique.name} is declared out of tier order',
        );
        previous = technique.tier;
      }
    });
  });

  group('6x6', () {
    test('is solved on its own 2-row by 3-column boxes', () {
      // The techniques are size generic, but every one of them asks what a box
      // contains. A box read as 3 rows by 2 columns would deduce digits that
      // are wrong in a way the grid still looks plausible after, so this runs
      // the whole solver against a shape where the two differ.
      final board = SudokuBoard.fromClues(SudokuSpec.s6x6, medium6x6);
      expect(countSolutions(board), 1);

      final report = solveWithTechniques(board);
      expect(report.solved, isTrue);
      expect(report.tier, Difficulty.medium);
    });

    test('reaches Expert by exclusion like a 9x9 does', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s6x6, expert6x6);
      expect(countSolutions(board), 1);

      final report = solveWithTechniques(board);
      expect(report.solved, isFalse);
      expect(report.tier, Difficulty.expert);
    });

    test('every deduction on a 6x6 is true', () {
      // The same independent check as the 9x9 fixtures, run over a whole solve
      // rather than one step: a box read the wrong way round would place a
      // digit the grid cannot take, and search says so.
      final board = SudokuBoard.fromClues(SudokuSpec.s6x6, medium6x6);
      final replay = SudokuBoard.fromClues(SudokuSpec.s6x6, medium6x6);

      for (final step in solveWithTechniques(board).steps) {
        if (!step.isPlacement) continue;
        final probe = replay.copy();
        probe.place(step.index, step.digit);
        expect(
          countSolutions(probe),
          1,
          reason: '${step.digit} at ${step.index} leaves no solution',
        );
        replay.place(step.index, step.digit);
      }
      expect(replay.isFull, isTrue);
    });
  });

  group("the caller's board", () {
    test('is byte-identical after a solve', () {
      // The generator judges a board it is still digging, so a solver that
      // filled it in would corrupt the puzzle being judged rather than fail
      // visibly.
      for (final clues in [expert9x9, fixtures.first.clues]) {
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, clues);
        final before = board.toClueString();
        final filled = board.filledCount;

        solveWithTechniques(board);
        nextStep(board);

        expect(board.toClueString(), before, reason: clues);
        expect(board.filledCount, filled, reason: clues);
      }
    });
  });

  group('determinism', () {
    test('two solves of the same board make the same steps in order', () {
      // A technique that scanned units or digits in an unspecified order could
      // still solve every puzzle and would still be a defect: the generator
      // judges a puzzle by which technique came first, so the tier — and so
      // which puzzle a stored ID names — would drift between runs.
      for (final clues in [
        expert9x9,
        medium6x6,
        for (final fixture in fixtures) fixture.clues,
      ]) {
        final spec = clues.length == SudokuSpec.s6x6.cells
            ? SudokuSpec.s6x6
            : SudokuSpec.s9x9;
        final first = solveWithTechniques(SudokuBoard.fromClues(spec, clues));
        final second = solveWithTechniques(SudokuBoard.fromClues(spec, clues));

        expect(first.tier, second.tier, reason: clues);
        expect(first.solved, second.solved, reason: clues);
        expect(
          first.steps.map((step) => step.toString()).toList(),
          second.steps.map((step) => step.toString()).toList(),
          reason: clues,
        );
      }
    });

    test('a hint is the first step of the solve it starts', () {
      for (final fixture in fixtures) {
        final board = SudokuBoard.fromClues(SudokuSpec.s9x9, fixture.clues);
        expect(
          nextStep(board).toString(),
          solveWithTechniques(board).steps.first.toString(),
          reason: fixture.clues,
        );
      }
    });
  });

  group('the report', () {
    test('does not hand out a mutable step list', () {
      final board = SudokuBoard.fromClues(SudokuSpec.s9x9, expert9x9);
      final report = solveWithTechniques(board);

      expect(
        report.steps.clear,
        throwsUnsupportedError,
        reason: 'phase 3 will hold this list while the player works',
      );
    });
  });
}

/// The digit that has to go at [index], established by search rather than by
/// technique: it is the only one that leaves the grid with a solution.
int _forcedDigitAt(String clues, int index) {
  final spec = SudokuSpec.s9x9;
  var forced = 0;
  for (var digit = 1; digit <= spec.digits; digit++) {
    final probe = SudokuBoard.fromClues(spec, clues);
    if (!probe.place(index, digit)) continue;
    if (countSolutions(probe, max: 1) == 0) continue;

    expect(forced, 0, reason: 'cell $index takes more than one digit');
    forced = digit;
  }
  expect(forced, isNot(0), reason: 'cell $index takes no digit at all');
  return forced;
}

/// How many solutions [clues] has once the ruled-out candidate is put back.
///
/// Zero is the proof that the elimination was sound.
int _solutionsWith(String clues, Elimination elimination) {
  final board = SudokuBoard.fromClues(SudokuSpec.s9x9, clues);
  expect(
    board.place(elimination.index, elimination.digit),
    isTrue,
    reason: '$elimination was never a candidate the rules allowed',
  );
  return countSolutions(board);
}

/// The one completion of [board], filled in by search.
SudokuBoard _solutionOf(SudokuBoard board) {
  final spec = board.spec;
  final solution = board.copy();
  while (!solution.isFull) {
    var placed = false;
    for (var index = 0; index < spec.cells; index++) {
      if (solution.digitAt(index) != 0) continue;
      final digit = _forcedDigitAt(solution.toClueString(), index);
      solution.place(index, digit);
      placed = true;
      break;
    }
    expect(placed, isTrue, reason: 'the grid has no completion');
  }
  return solution;
}
