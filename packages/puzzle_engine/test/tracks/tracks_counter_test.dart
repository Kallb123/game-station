// The expected counts for every fixture here were checked against an
// independent counter written in Python from the rules, not from this
// implementation: it enumerates self-avoiding paths of cells from the start
// cell to the goal cell, turns each into connection masks, and keeps those that
// match the row and column counts and the fixed cells. It shares no search
// order, no pruning and no loop test with the Dart counter, so agreement means
// two different ways of reading the rules gave the same number. Every fixture,
// the 7x7 and both 9x9s included, was enumerated to exhaustion (the 9x9s in
// about one second and seven, helped by a flood-fill bound on how many cells
// each row and column can still reach). The script lives outside the
// repository.
//
// The counter is the gate for PR 3's generator: a Tracks puzzle is accepted
// only when it counts exactly 1, so a counter that over-prunes would make the
// generator keep ambiguous puzzles and one that under-prunes would reject good
// ones.

import 'package:puzzle_engine/src/solver.dart';
import 'package:puzzle_engine/src/tracks/track_side.dart';
import 'package:puzzle_engine/src/tracks/tracks_clues.dart';
import 'package:puzzle_engine/src/tracks/tracks_counter.dart';
import 'package:test/test.dart';

import 'tracks_fixtures.dart';

// The helpers moved to tracks_fixtures.dart in PR 3; re-exported so a test
// that imports them from here keeps working.
export 'tracks_fixtures.dart';

// ---------------------------------------------------------------------------
// Fixtures. Each is drawn with the pipe-maze letters above; S marks the start
// port (the west edge of that row) and G the goal port (the south edge of that
// column) in the margins.
// ---------------------------------------------------------------------------

/// Unique 5x5. Only the cell at index 5 is fixed (the L at the left of row 1);
/// the counts do the rest.
///
///     S 7F7..      rows    3 3 3 3 2
///       LJ|..      columns 5 5 4 0 0
///       F7|..
///       |LJ..
///       L7...
///        G
final List<int> uniqueFiveSolution = board([
  '7F7..',
  'LJ|..',
  'F7|..',
  '|LJ..',
  'L7...',
]);
final TracksClues uniqueFive = cluesFor(
  5,
  0,
  1,
  [3, 3, 3, 3, 2],
  [5, 5, 4, 0, 0],
  {5: 3},
);

/// Two solutions: the two routes differ in the 2x2 block at rows 2-3, columns
/// 2-3, which can be walked either way round without moving any count. Index
/// 18 is fixed as `|` so the route is pinned everywhere else.
///
///     7F--7     7F7F7
///     LJF7|     LJLJ|
///     .FJ||     .F-7|
///     .L7||     .L7||
///     .FJLJ     .FJLJ
final List<int> twoFiveFirst = board([
  '7F--7',
  'LJF7|',
  '.FJ||',
  '.L7||',
  '.FJLJ',
]);
final List<int> twoFiveSecond = board([
  '7F7F7',
  'LJLJ|',
  '.F-7|',
  '.L7||',
  '.FJLJ',
]);
final TracksClues twoFive = cluesFor(
  5,
  0,
  1,
  [5, 5, 4, 4, 4],
  [2, 5, 5, 5, 5],
  {18: 5},
);

/// No solution: the unique fixture with its last two row counts swapped. The
/// local rules are all satisfiable, only the totals cannot be met together.
final TracksClues noneFive = cluesFor(
  5,
  0,
  1,
  [3, 3, 3, 2, 3],
  [5, 5, 4, 0, 0],
  {5: 3},
);

/// The near-solution that closes a loop. A path runs down the west edge and
/// along the bottom to the goal, and a separate 2x2 ring sits in the north-east
/// corner of the grid. Every cell is a piece, every bit is met, both ports are
/// open, the counts match and the fixed cell (index 8, the ring's `F`) holds
/// its piece. Only "no closed loop" fails, and nothing else on the board fits
/// those counts, so the answer is 0.
///
///     S 7....
///       |..F7
///       |..LJ
///       |....
///       L-7..
///          G
final List<int> loopNearSolution = board([
  '7....',
  '|..F7',
  '|..LJ',
  '|....',
  'L-7..',
]);
final TracksClues loopFive = cluesFor(
  5,
  0,
  2,
  [1, 3, 3, 1, 3],
  [5, 1, 1, 2, 2],
  {8: 6},
);

/// Unique 7x7: a winding path, two fixed corners.
///
///     .......
///     ...F-7.
///     ...|.L7
///   S 7..|F-J
///     |..|L7.
///     |F7|FJ.
///     LJLJL7.
///           G
final List<int> uniqueSevenSolution = board([
  '.......',
  '...F-7.',
  '...|.L7',
  '7..|F-J',
  '|..|L7.',
  '|F7|FJ.',
  'LJLJL7.',
]);
final TracksClues uniqueSeven = cluesFor(
  7,
  3,
  5,
  [0, 3, 3, 5, 4, 6, 6],
  [4, 2, 2, 6, 5, 6, 2],
  {25: 6, 39: 6},
);

/// Unique 9x9: a 50-cell path that runs round the edge of the grid and winds
/// back on itself, with eight fixed cells. The empty middle block is what
/// makes it hard to count, since no count forbids the track from entering it.
///
/// The expected count of 1 was enumerated to exhaustion by the Python counter
/// (about a second there).
///
///     F-7F7F7F7
///     |FJ|LJ|||
///     |L7|F-J||
///     |.LJL--J|
///     |.......|
///     |.......|
///   S J.......|
///     ........|
///     .F------J
///      G
final List<int> uniqueNineSolution = board([
  'F-7F7F7F7',
  '|FJ|LJ|||',
  '|L7|F-J||',
  '|.LJL--J|',
  '|.......|',
  '|.......|',
  'J.......|',
  '........|',
  '.F------J',
]);
final TracksClues uniqueNine = cluesFor(
  9,
  6,
  1,
  [9, 9, 9, 8, 2, 2, 2, 1, 8],
  [7, 4, 5, 5, 5, 5, 5, 5, 9],
  {1: 10, 3: 6, 7: 6, 11: 9, 14: 9, 16: 5, 18: 5, 30: 9},
);

/// A second unique 9x9 with only six fixed cells, whose route hugs the west
/// edge and doubles back through the south-west corner.
///
///     F7F-----7
///     |||F----J
///     ||||.....
///     ||||.....
///     ||||.....
///     |LJ|.....
///   S JF-J.....
///     FJF7.....
///     L-JL7....
///        G
final List<int> uniqueNineBSolution = board([
  'F7F-----7',
  '|||F----J',
  '||||.....',
  '||||.....',
  '||||.....',
  '|LJ|.....',
  'JF-J.....',
  'FJF7.....',
  'L-JL7....',
]);
final TracksClues uniqueNineB = cluesFor(
  9,
  6,
  4,
  [9, 9, 4, 4, 4, 4, 4, 4, 5],
  [9, 9, 9, 9, 3, 2, 2, 2, 2],
  {10: 5, 29: 5, 30: 5, 56: 10, 64: 9, 74: 9},
);

void main() {
  group('fixtures are what the comments say', () {
    // The hand-written boards must obey the rules the counter is meant to
    // enforce, or a counter that agreed with a wrong board would pass.
    test('each hand-written solution passes the rule checker', () {
      expect(brokenRules(uniqueFive, uniqueFiveSolution), isEmpty);
      expect(brokenRules(twoFive, twoFiveFirst), isEmpty);
      expect(brokenRules(twoFive, twoFiveSecond), isEmpty);
      expect(brokenRules(uniqueSeven, uniqueSevenSolution), isEmpty);
      expect(brokenRules(uniqueNine, uniqueNineSolution), isEmpty);
      expect(brokenRules(uniqueNineB, uniqueNineBSolution), isEmpty);
    });

    test('the near-solution meets counts and fixed cells and fails only the '
        'no-loop rule', () {
      expect(brokenRules(loopFive, loopNearSolution), ['loop']);
    });

    test('the checker does notice each other rule being broken', () {
      // Guards the guard: a checker that reported nothing would make the
      // test above pass for any board.
      final wrongCount = List<int>.of(uniqueFiveSolution)..[24] = 5;
      expect(brokenRules(uniqueFive, wrongCount), contains('counts'));
      final wrongFixed = List<int>.of(uniqueFiveSolution)..[5] = 6;
      expect(brokenRules(uniqueFive, wrongFixed), contains('fixed'));
      final unmatched = List<int>.of(uniqueFiveSolution)..[7] = 3;
      expect(brokenRules(uniqueFive, unmatched), contains('connections'));
    });
  });

  group('countTracksSolutions', () {
    test('a unique 5x5 counts 1 and delivers the hand-written board', () {
      final found = solutionsOf(uniqueFive);
      expect(found, [uniqueFiveSolution]);
      expect(countTracksSolutions(uniqueFive), 1);
    });

    test('two solutions: counts 2, and at limit 3 exactly 2, both seen', () {
      expect(countTracksSolutions(twoFive), 2);

      final seen = solutionsOf(twoFive, limit: 3);
      expect(seen, hasLength(2));
      expect(seen, containsAll([twoFiveFirst, twoFiveSecond]));
      expect(countTracksSolutions(twoFive, limit: 3), 2);
    });

    test('no solution counts 0 and never calls onSolution', () {
      expect(countTracksSolutions(noneFive), 0);
      expect(solutionsOf(noneFive), isEmpty);
    });

    test('the only near-solution closes a loop, so the count is 0', () {
      expect(countTracksSolutions(loopFive), 0);
      expect(solutionsOf(loopFive), isEmpty);
    });

    test('a unique 7x7 counts 1 and delivers its board', () {
      expect(solutionsOf(uniqueSeven), [uniqueSevenSolution]);
      expect(countTracksSolutions(uniqueSeven), 1);
    });

    test('a unique 9x9 counts 1 and delivers its board', () {
      expect(solutionsOf(uniqueNine), [uniqueNineSolution]);
      expect(countTracksSolutions(uniqueNine), 1);
    });

    test('a second unique 9x9 with six fixed cells counts 1', () {
      expect(solutionsOf(uniqueNineB), [uniqueNineBSolution]);
      expect(countTracksSolutions(uniqueNineB), 1);
    });

    test('the 9x9 is counted within a sensible number of nodes', () {
      // PR 3's generator calls the counter once per candidate, so a 9x9 that
      // needs the whole default budget would make generation unusable. The
      // cap is on work rather than time, so this does not depend on the
      // machine: a count that blew the budget returns unknownSolutionCount.
      expect(countTracksSolutions(uniqueNine, maxNodes: 200000), 1);
      expect(countTracksSolutions(uniqueNineB, maxNodes: 200000), 1);
    });

    test('limit 1 stops at the first solution', () {
      final found = <List<int>>[];
      expect(countTracksSolutions(twoFive, limit: 1, onSolution: found.add), 1);
      expect(found, hasLength(1));
    });

    test(
      'a node cap too small for the search returns unknownSolutionCount',
      () {
        expect(
          countTracksSolutions(uniqueFive, maxNodes: 3),
          unknownSolutionCount,
        );
        expect(
          countTracksSolutions(uniqueNine, maxNodes: 10),
          unknownSolutionCount,
        );
      },
    );

    test('a start cell that is also the goal is a one-cell path', () {
      // startRow = side - 1 and goalColumn = 0 name the same corner cell,
      // which then holds the south-west piece: west in, south out.
      final clues = cluesFor(5, 4, 0, [0, 0, 0, 0, 1], [1, 0, 0, 0, 0]);
      expect(clues.startCell, clues.goalCell);
      final found = solutionsOf(clues);
      expect(found, hasLength(1));
      expect(found.single, [
        for (var i = 0; i < 25; i++)
          i == 20 ? TrackSide.south | TrackSide.west : 0,
      ]);
      expect(countTracksSolutions(clues), 1);
    });

    test('onSolution receives copies the counter does not reuse', () {
      final found = solutionsOf(twoFive);
      found.first.fillRange(0, found.first.length, 99);
      expect(found.last, isNot(contains(99)));
      expect(countTracksSolutions(twoFive), 2);
    });

    test('rejects a limit or node cap below 1', () {
      expect(
        () => countTracksSolutions(uniqueFive, limit: 0),
        throwsRangeError,
      );
      expect(
        () => countTracksSolutions(uniqueFive, limit: -1),
        throwsRangeError,
      );
      expect(
        () => countTracksSolutions(uniqueFive, maxNodes: 0),
        throwsRangeError,
      );
    });

    test('does not change the clues it is given', () {
      final before = uniqueNine.encode();
      countTracksSolutions(uniqueNine);
      countTracksSolutions(uniqueNine, limit: 1);
      expect(uniqueNine.encode(), before);
      expect(uniqueNine.fixed, hasLength(81));
    });
  });
}
