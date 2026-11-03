// The widest check of the session's rules: 500 generated puzzles, each solved
// by replaying its stored solution as a single stroke.
//
// Both halves of the stroke code have to agree with the generator for this to
// pass on every puzzle: the step rule must lay exactly the solution when the
// finger follows it, and `isSolved`, which never looks at the stored solution
// (`PLAN-phase-9-tracks.md` §4.7), must say yes at the end and not before. A
// puzzle where the rules and the solution disagreed would mean the generator's
// uniqueness check and the session's reading of the rules differ.
//
// **No puzzle opens solved, and solved can still come before the last step.**
// A fixed piece's open end is not answered by the free cell beside it, so the
// child always has something to lay. When the goal cell is a fixed piece its
// port bit is already there, so the stroke's last step along it adds nothing and
// the board is solved a step early. The assertion is therefore that `isSolved`
// equals "the board is the solution" at every step, and that it was still false
// before the last step that laid a connection, not that it is false one step
// short.

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../tracks_fixtures.dart';

/// Puzzles per size and difficulty. Eight combinations, so 500 in all: the
/// first four get one more.
int _countFor(int combo) => 62 + (combo < 4 ? 1 : 0);

void main() {
  test('500 puzzles, one stroke each from port to port, are solved', () {
    var replayed = 0;

    for (var combo = 0; combo < offeredCombos.length; combo++) {
      final (spec, difficulty) = offeredCombos[combo];
      for (var index = 0; index < _countFor(combo); index++) {
        final puzzle = generateTracks(
          TracksPuzzleId.parse(
            'tracks:${spec.label}:${difficulty.name}:$index',
          ),
        );
        final label = puzzle.id.toString();
        final session = startSession(puzzle);
        final positions = solutionStroke(puzzle);

        expect(session.isSolved, isFalse, reason: '$label opens solved');

        // The last step that lays something: after it the board is complete,
        // and before it the board is not.
        final cellsBefore = <List<int>>[];
        session.beginStroke(positions.first.$1, positions.first.$2);
        var lastLayingStep = 0;
        for (var step = 1; step < positions.length; step++) {
          final before = [...session.cells];
          cellsBefore.add(before);
          final solvedBefore = session.isSolved;
          session.strokeTo(positions[step].$1, positions[step].$2);
          if (!listEquals(before, session.cells)) lastLayingStep = step;

          expect(
            session.isSolved,
            listEquals(session.cells, puzzle.solution),
            reason: '$label at step $step of ${positions.length - 1}',
          );
          if (solvedBefore) {
            expect(session.isSolved, isTrue, reason: '$label stays solved');
          }
        }
        session.endStroke();

        expect(session.isSolved, isTrue, reason: label);
        expect(session.cells, puzzle.solution, reason: label);
        expect(session.mistakes, 0, reason: label);
        expect(lastLayingStep, greaterThan(0), reason: label);
        // Before the last connection was laid the board differed from the
        // solution, so it was not solved: checked at the step itself above, and
        // here by the board that step started from.
        expect(
          listEquals(cellsBefore[lastLayingStep - 1], puzzle.solution),
          isFalse,
          reason: label,
        );
        replayed++;
      }
    }

    expect(replayed, 500);
  });
}
