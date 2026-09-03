// `SnakeSim`'s behaviour (`PLAN-phase-7-snake.md` §4.1, PR 3).
//
// Several tests below drive the sim through `debugSetBody`, `debugSetTargets`
// and `debugForceMoveNext` rather than through real play, for the same reason
// `invaders_sim_test.dart` gives for its own debug seams: reaching a specific
// shape or a specific target through real play — RNG-placed, in Snake's case
// — would make the test about navigating or aiming rather than about the
// rule it exists to check. `snake_sim.dart` says why each seam exists; the
// turn queue and the move-interval ramp go through `step()` alone, the same
// path a real run takes.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';
import 'package:zibo_games/features/arcade/snake/model/counting.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_rules.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_sim.dart';

/// Forces the very next [SnakeSim.step] call to perform a move, so a test
/// does not have to step through a whole [SnakeRules.moveTicksAt] interval to
/// see one.
void _forceMove(SnakeSim sim, [PadInput input = PadInput.none]) {
  sim.debugForceMoveNext();
  sim.step(input);
}

/// Eats [count] targets for real, each placed directly ahead of the head so
/// no navigation is needed — for tests that only care about the bookkeeping
/// an eat produces (score, level, the counting position), not about reaching
/// the target.
void _eatAhead(SnakeSim sim, int count) {
  for (var i = 0; i < count; i++) {
    final ahead = Cell(sim.body.first.col + 1, sim.body.first.row);
    sim.debugSetTargets([SnakeTarget(cell: ahead, value: sim.nextValue)]);
    _forceMove(sim, const PadInput(right: true));
  }
}

void main() {
  group('turning', () {
    test('a held button queues one turn, not one per tick', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.off,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(5, 5),
        Cell(4, 5),
        Cell(3, 5),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(0, 0), value: 0)]);

      // Hold UP for most of an interval without releasing it. If every held
      // tick queued a turn instead of only the rising edge, the queue would
      // already be at its two-entry cap by the time RIGHT is pressed below,
      // and RIGHT would be dropped.
      for (var i = 0; i < 15; i++) {
        sim.step(const PadInput(up: true));
      }
      // A second direction, pressed while UP is still held: only room for it
      // if holding UP did not already fill the queue.
      sim.step(const PadInput(up: true, right: true));

      _forceMove(sim); // consumes the queued UP
      expect(sim.heading, SnakeDirection.up);
      _forceMove(sim); // consumes the queued RIGHT
      expect(sim.heading, SnakeDirection.right);
    });

    test('a reversal is refused', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.off,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(5, 5),
        Cell(4, 5),
        Cell(3, 5),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(0, 0), value: 0)]);

      sim.step(const PadInput(left: true)); // opposite of the current heading
      _forceMove(sim);

      expect(sim.heading, SnakeDirection.right);
      expect(sim.body.first, Cell(6, 5));
    });

    test('two turns inside one move interval both land', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.off,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(5, 5),
        Cell(4, 5),
        Cell(3, 5),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(0, 0), value: 0)]);

      sim.step(const PadInput(up: true));
      sim.step(const PadInput(right: true));

      _forceMove(sim);
      expect(sim.heading, SnakeDirection.up);
      _forceMove(sim);
      expect(sim.heading, SnakeDirection.right);
    });
  });

  group('growth', () {
    test('adds exactly growPerTarget cells and the tail follows', () {
      const rules = SnakeRules.normal;
      final sim = SnakeSim(rules: rules, counting: SnakeCounting.off, seed: 1);
      sim.debugSetBody([
        Cell(5, 5),
        Cell(4, 5),
        Cell(3, 5),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(6, 5), value: 0)]);

      _forceMove(sim, const PadInput(right: true)); // eats the target
      expect(sim.body.first, Cell(6, 5));
      // The segment that was the tail's neighbour before eating — (3, 5),
      // the pre-eat tail, is dropped on this very move, same as any move —
      // is the one growth is about to keep around for `growPerTarget` more
      // moves instead of dropping it on the next one.
      final tailAfterEating = sim.body.last;
      // Eating spawned a fresh replacement target at an RNG-chosen free
      // cell; move it out of the way so the moves below cannot accidentally
      // eat again and add more growth than the test expects.
      sim.debugSetTargets(const [SnakeTarget(cell: Cell(0, 0), value: 999)]);

      final lengthsAfterEating = <int>[sim.body.length];
      for (var i = 0; i < rules.growPerTarget; i++) {
        _forceMove(sim, const PadInput(right: true));
        lengthsAfterEating.add(sim.body.length);
      }

      // One cell longer for each of `growPerTarget` moves after the eat.
      for (var i = 1; i < lengthsAfterEating.length; i++) {
        expect(lengthsAfterEating[i], lengthsAfterEating[i - 1] + 1);
      }
      // The tail followed rather than the body teleporting: `growPerTarget`
      // moves of growth is exactly how long the tail that was about to be
      // dropped stays put instead.
      expect(sim.body.contains(tailAfterEating), isTrue);

      // Growth has been fully applied: the next move drops that tail and no
      // longer adds a cell.
      final steadyLength = sim.body.length;
      _forceMove(sim, const PadInput(right: true));
      expect(sim.body.length, steadyLength);
      expect(sim.body.contains(tailAfterEating), isFalse);
    });
  });

  group('walls', () {
    test('crashes at an edge when wrapWalls is false', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.off,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(13, 8),
        Cell(12, 8),
        Cell(11, 8),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(0, 0), value: 0)]);

      _forceMove(sim);

      expect(sim.lives, SnakeRules.normal.lives - 1);
      expect(sim.isRespawning, isTrue);
    });

    test('wraps to the opposite edge when wrapWalls is true', () {
      final sim = SnakeSim(
        rules: SnakeRules.easy,
        counting: SnakeCounting.off,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(13, 8),
        Cell(12, 8),
        Cell(11, 8),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(0, 0), value: 0)]);

      _forceMove(sim);

      expect(sim.lives, SnakeRules.easy.lives);
      expect(sim.isRespawning, isFalse);
      expect(sim.body.first, Cell(0, 8));
    });
  });

  test(
    'running into its own body crashes, unless the cell is the vacating tail',
    () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.off,
        seed: 1,
      );
      // A hooked body: heading right from (5, 5) steps onto (6, 5), a middle
      // segment rather than the tail at (7, 5), so the tail vacating cannot
      // excuse this move.
      sim.debugSetBody([
        Cell(5, 5),
        Cell(5, 6),
        Cell(6, 6),
        Cell(6, 5),
        Cell(7, 5),
      ], heading: SnakeDirection.right);
      sim.debugSetTargets([SnakeTarget(cell: Cell(0, 0), value: 0)]);

      _forceMove(sim);

      expect(sim.lives, SnakeRules.normal.lives - 1);
      expect(sim.drainEvents(), contains(SnakeEvent.crashed));
    },
  );

  group('a crash', () {
    test('keeps the score, the level and the counting position', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.ones,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(5, 8),
        Cell(4, 8),
        Cell(3, 8),
      ], heading: SnakeDirection.right);
      _eatAhead(sim, 2);

      final scoreBefore = sim.score;
      final levelBefore = sim.level;
      final nextBefore = sim.nextValue;
      expect(nextBefore, 3); // 1 and 2 already eaten

      sim.debugSetBody([
        Cell(13, 8),
        Cell(12, 8),
        Cell(11, 8),
      ], heading: SnakeDirection.right);
      _forceMove(sim); // crashes into the wall

      expect(sim.score, scoreBefore);
      expect(sim.level, levelBefore);
      expect(sim.nextValue, nextBefore);

      // Still true once the respawn pause ends.
      for (var i = 0; i < SnakeRules.normal.respawnTicks; i++) {
        sim.step(PadInput.none);
      }
      expect(sim.isRespawning, isFalse);
      expect(sim.score, scoreBefore);
      expect(sim.level, levelBefore);
      expect(sim.nextValue, nextBefore);
    });
  });

  group('a decoy', () {
    test('crossed emits notYet once per entry and nothing else', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.ones,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(5, 5),
        Cell(4, 5),
        Cell(3, 5),
      ], heading: SnakeDirection.right);
      // The next value (1) sits out of reach; a decoy (worth 4, not next)
      // sits directly ahead.
      sim.debugSetTargets([
        SnakeTarget(cell: Cell(0, 0), value: sim.nextValue),
        const SnakeTarget(cell: Cell(6, 5), value: 4),
      ]);

      final scoreBefore = sim.score;
      _forceMove(sim, const PadInput(right: true));

      expect(sim.drainEvents(), [SnakeEvent.notYet]);
      expect(sim.score, scoreBefore);
      expect(sim.nextValue, 1);

      // The decoy was crossed, not eaten: it is still on the field, and the
      // snake has already moved off it, so sitting on the field for further
      // ticks before the next move must not fire a second time.
      for (var i = 0; i < 5; i++) {
        sim.step(PadInput.none);
      }
      expect(sim.drainEvents(), isEmpty);
    });
  });

  group('a level clear', () {
    test('scores the bonus and speeds the game up', () {
      const rules = SnakeRules.normal;
      final sim = SnakeSim(rules: rules, counting: SnakeCounting.off, seed: 1);
      // Starts near the left edge rather than mid-field: ten eats move the
      // head ten cells right, and mid-field would run it off the far wall
      // before the level clears.
      sim.debugSetBody([
        Cell(2, 8),
        Cell(1, 8),
        Cell(0, 8),
      ], heading: SnakeDirection.right);

      _eatAhead(sim, rules.targetsPerLevel - 1);
      final scoreBeforeLast = sim.score;
      expect(sim.level, 1);

      _eatAhead(sim, 1);

      expect(sim.level, 2);
      expect(
        sim.score,
        scoreBeforeLast + rules.pointsPerTarget + rules.levelBonus,
      );
      expect(
        rules.moveTicksAt(sim.level, 0),
        lessThan(rules.moveTicksAt(1, 0)),
      );
    });
  });

  group('longest', () {
    test('is the peak body length reached, not the length at game over', () {
      final sim = SnakeSim(
        rules: SnakeRules.normal,
        counting: SnakeCounting.off,
        seed: 1,
      );
      sim.debugSetBody([
        Cell(5, 8),
        Cell(4, 8),
        Cell(3, 8),
      ], heading: SnakeDirection.right);

      _eatAhead(sim, 2);
      final peak = sim.longest;
      expect(peak, greaterThan(SnakeRules.normal.startLength));

      // Crash, which resets the body back down to startLength.
      sim.debugSetBody([
        Cell(13, 8),
        Cell(12, 8),
        Cell(11, 8),
      ], heading: SnakeDirection.right);
      _forceMove(sim);

      expect(sim.body.length, isNot(peak));
      expect(sim.longest, peak);
    });
  });
}
