// `InvadersSim`'s behaviour (`PLAN-phase-4.md` §4.1, PR 3) and its
// `InvadersEvent`s (`PLAN-phase-5.md` §4.4, PR 4).
//
// Several of the tests below drive the sim through `debugSetAliveRows` and
// `debugSetAlienTimer`/`debugSetAlienFireTimer`/`debugSetUfoTimer`/
// `debugAwardScore` rather than through real play — each says in its own
// comment why, and `invaders_sim.dart` says why the seams exist. The rest —
// the wall reverse, the bunker erosion, auto-fire — go through `step()`
// alone, the same path a real run takes.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_rules.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_sim.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';

void main() {
  group('the alien block', () {
    test('reverses and drops after hitting a wall', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);
      final startDirection = sim.aliens.direction;
      final startY = sim.aliens.originY;

      var reversed = false;
      for (var i = 0; i < 20000 && !reversed; i++) {
        sim.step(PadInput.none);
        if (sim.aliens.direction != startDirection) reversed = true;
      }

      expect(reversed, isTrue, reason: 'the block never reversed');
      expect(sim.aliens.originY, greaterThan(startY));
    });

    test('a dead edge column shrinks the wall box so the block marches '
        'further before reversing', () {
      const rules = InvadersRules.normal;
      final full = InvadersSim(rules: rules, seed: 1);
      final shrunk = InvadersSim(rules: rules, seed: 1);

      // Kill only the rightmost column, the one the formation is
      // marching toward first (`direction` starts at +1): its wall box
      // is now one column narrower on that side than the full grid.
      shrunk.debugSetAliveRows(
        _aliveRowsMissingColumn(rules.alienRows, alienColumns - 1),
      );

      final fullOriginXAtReverse = _originXWhenReversed(full);
      final shrunkOriginXAtReverse = _originXWhenReversed(shrunk);

      expect(shrunkOriginXAtReverse, greaterThan(fullOriginXAtReverse));
    });

    test('a dead bottom row means the block must march lower before it '
        'reaches the player', () {
      // Regression test: the invasion check used to compare the block's
      // *original* box (`rows * alienRowPitch`) against the player's row,
      // so a formation thinned out from the bottom was ruled to have
      // reached the player before any surviving alien actually had.
      final rules = InvadersRules(
        alienRows: InvadersRules.normal.alienRows,
        lives: InvadersRules.normal.lives,
        baseStep: InvadersRules.normal.baseStep,
        minStep: InvadersRules.normal.minStep,
        waveStepRamp: InvadersRules.normal.waveStepRamp,
        fireInterval: InvadersRules.normal.fireInterval,
        minFireInterval: InvadersRules.normal.minFireInterval,
        fireIntervalRamp: InvadersRules.normal.fireIntervalRamp,
        // Alien fire is disabled so the only way `playerKilled` fires is
        // the block reaching the player's row, not a stray shot.
        maxAlienShots: 0,
      );
      final full = InvadersSim(rules: rules, seed: 1);
      final bottomRowDead = InvadersSim(rules: rules, seed: 1);

      // Kill only the bottom row — the one nearest the player.
      bottomRowDead.debugSetAliveRows(
        _aliveRowsMissingRow(rules.alienRows, rules.alienRows - 1),
      );

      final fullOriginYAtInvasion = _originYWhenPlayerKilled(full);
      final bottomRowDeadOriginYAtInvasion = _originYWhenPlayerKilled(
        bottomRowDead,
      );

      // One fewer row between the surviving aliens and the player means
      // one more `alienRowPitch` of marching before the invasion line is
      // crossed.
      expect(
        bottomRowDeadOriginYAtInvasion,
        closeTo(fullOriginYAtInvasion + alienRowPitch, 1e-9),
      );
    });

    test('the march interval shrinks as aliens die and hits its floor', () {
      const rules = InvadersRules.normal;
      const total = 5 * 11;
      final sim = InvadersSim(rules: rules, seed: 1);

      sim.debugSetAliveRows(_aliveRowsWithCount(5, total));
      sim.debugSetAlienTimer(0);
      sim.step(PadInput.none);
      expect(sim.aliens.stepTimer, closeTo(rules.baseStep, 1e-9));

      // Half the aliens: a proportional interval, not yet at the floor.
      sim.debugSetAliveRows(_aliveRowsWithCount(5, 27));
      sim.debugSetAlienTimer(0);
      sim.step(PadInput.none);
      final halfExpected = rules.baseStep * 27 / total;
      expect(halfExpected, greaterThan(rules.minStep));
      expect(sim.aliens.stepTimer, closeTo(halfExpected, 1e-9));

      // One straggler: the formula would ask for less than the floor allows.
      sim.debugSetAliveRows(_aliveRowsWithCount(5, 1));
      sim.debugSetAlienTimer(0);
      sim.step(PadInput.none);
      expect(sim.aliens.stepTimer, rules.minStep);
    });

    test('a cleared wave starts one row lower and faster', () {
      const rules = InvadersRules.normal;
      final sim = InvadersSim(rules: rules, seed: 4);
      final wave1OriginY = sim.aliens.originY;
      final wave1Rows = sim.aliens.rows;

      sim.debugSetAliveRows(List<int>.filled(wave1Rows, 0));
      sim.step(PadInput.none);

      expect(sim.wave, 2);
      expect(sim.aliens.originY, wave1OriginY + alienRowPitch);
      expect(sim.aliens.rows, wave1Rows);
      expect(sim.aliens.direction, 1);
      expect(
        sim.aliens.aliveRows,
        List<int>.filled(wave1Rows, (1 << alienColumns) - 1),
      );
      expect(rules.baseStepForWave(2), lessThan(rules.baseStepForWave(1)));
    });
  });

  group('easy mode', () {
    test('has three rows and five lives by construction, not by branch', () {
      final sim = InvadersSim(rules: InvadersRules.easy, seed: 1);

      expect(sim.aliens.rows, 3);
      expect(sim.lives, 5);
      expect(
        sim.aliens.aliveRows,
        List<int>.filled(3, (1 << alienColumns) - 1),
      );
    });
  });

  group('scoring', () {
    test('the front row scores 10 and the back row scores 30', () {
      // A whole row alive, all 11 columns, rather than one aligned alien:
      // the block's full 176-unit width always spans the player's fixed
      // starting column regardless of how far it has marched by the time
      // the shot arrives, so which alien is hit needs no aiming — only
      // which row is left alive decides the score.
      final frontOnly = InvadersSim(rules: InvadersRules.normal, seed: 3);
      frontOnly.debugSetAliveRows(
        _aliveRowsWithOnlyRow(5, 4),
      ); // front: distance 0
      frontOnly.step(const PadInput(fire: true));
      _stepUntilNoPlayerShots(frontOnly);
      expect(frontOnly.score, 10);

      final backOnly = InvadersSim(rules: InvadersRules.normal, seed: 3);
      backOnly.debugSetAliveRows(
        _aliveRowsWithOnlyRow(5, 0),
      ); // back: distance 4
      backOnly.step(const PadInput(fire: true));
      _stepUntilNoPlayerShots(backOnly);
      expect(backOnly.score, 30);
    });

    test('a bonus life lands at exactly 10,000', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);
      final startingLives = sim.lives;

      sim.debugAwardScore(9999);
      expect(sim.lives, startingLives);

      sim.debugAwardScore(1);
      expect(sim.score, 10000);
      expect(sim.lives, startingLives + 1);

      // A jump straight past the next threshold grants exactly one more,
      // not one per point over it.
      sim.debugAwardScore(9999);
      expect(sim.lives, startingLives + 1);

      // A jump past two thresholds at once grants two lives.
      final fresh = InvadersSim(rules: InvadersRules.normal, seed: 1);
      final freshStartingLives = fresh.lives;
      fresh.debugAwardScore(25000);
      expect(fresh.lives, freshStartingLives + 2);
    });
  });

  group('bunkers', () {
    test('a shot clears a disc from a bunker and stops', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 7);
      const bunkerIndex = 2;
      final bunker = sim.bunkers[bunkerIndex];
      final targetCenter = bunker.x + Bunker.width / 2;
      final fullBlockCount = bunkerColumns * bunkerRows;

      while (sim.player.x + playerWidth / 2 < targetCenter) {
        sim.step(const PadInput(right: true));
      }
      sim.step(const PadInput(fire: true));

      var absorbed = false;
      for (var i = 0; i < 500 && !absorbed; i++) {
        if (sim.shots.where((shot) => shot.fromPlayer).isEmpty) absorbed = true;
        if (!absorbed) sim.step(PadInput.none);
      }

      expect(absorbed, isTrue, reason: 'the shot never stopped');
      expect(sim.shots.where((shot) => shot.fromPlayer), isEmpty);

      final blocksLeft = sim.bunkers[bunkerIndex].blocks.fold<int>(
        0,
        (sum, row) => sum + _popcount(row),
      );
      expect(blocksLeft, lessThan(fullBlockCount));
    });
  });

  group('auto-fire', () {
    test('respects the cooldown', () {
      final sim = InvadersSim(
        rules: InvadersRules.normal,
        seed: 9,
        autoFire: true,
      );
      final fireTicks = <int>[];

      for (var tick = 0; tick < 600; tick++) {
        final before = sim.shots.where((shot) => shot.fromPlayer).length;
        sim.step(PadInput.none);
        final after = sim.shots.where((shot) => shot.fromPlayer).length;
        if (after > before) fireTicks.add(tick);
      }

      expect(fireTicks.length, greaterThan(2));
      const expectedGap = 42; // 0.35 s at 1/120 s per tick.
      for (var i = 1; i < fireTicks.length; i++) {
        expect(fireTicks[i] - fireTicks[i - 1], expectedGap);
      }
    });
  });

  group('events', () {
    test('firing produces a playerShot event, and nothing else', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);

      sim.step(const PadInput(fire: true));

      expect(sim.drainEvents(), [InvadersEvent.playerShot]);
    });

    test('an alien firing produces an alienShot event', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);
      sim.debugSetAlienFireTimer(0);

      sim.step(PadInput.none);

      expect(sim.drainEvents(), [InvadersEvent.alienShot]);
    });

    test('the alien block stepping produces an alienStep event', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);
      sim.debugSetAlienTimer(0);

      sim.step(PadInput.none);

      expect(sim.drainEvents(), [InvadersEvent.alienStep]);
    });

    test('an alien killed produces an alienKilled event', () {
      const rules = InvadersRules.normal;
      final sim = InvadersSim(rules: rules, seed: 3);
      // The same front-row setup as the scoring test above: every column of
      // the front row alive lines up with the player's fixed starting
      // column, so no aiming is needed for the shot to land.
      sim.debugSetAliveRows(_aliveRowsWithOnlyRow(rules.alienRows, 4));

      sim.step(const PadInput(fire: true));
      expect(sim.drainEvents(), [InvadersEvent.playerShot]);

      var killed = false;
      for (var i = 0; i < 2000 && !killed; i++) {
        sim.step(PadInput.none);
        if (sim.drainEvents().contains(InvadersEvent.alienKilled)) {
          killed = true;
        }
      }
      expect(killed, isTrue, reason: 'the alien was never hit');
    });

    test('the UFO arriving produces ufoAppeared, leaving produces ufoLeft', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);
      sim.debugSetUfoTimer(0);

      sim.step(PadInput.none);
      expect(sim.drainEvents(), contains(InvadersEvent.ufoAppeared));

      var left = false;
      for (var i = 0; i < 2000 && !left; i++) {
        sim.step(PadInput.none);
        if (sim.drainEvents().contains(InvadersEvent.ufoLeft)) left = true;
      }
      expect(left, isTrue, reason: 'the UFO never left the field');
    });

    test('destroying the UFO produces a ufoKilled event', () {
      const rules = InvadersRules.normal;
      final sim = InvadersSim(rules: rules, seed: 1);
      // Column 5 is the one the player's fixed starting column fires up —
      // cleared, not the whole block, so the shot reaches the UFO instead of
      // an alien on the way, while the block stays non-empty and clearing no
      // wave.
      sim.debugSetAliveRows(_aliveRowsMissingColumn(rules.alienRows, 5));
      // Held stationary, directly under that column, rather than left to
      // drift as a real spawn would: the shot's flight time up the field is
      // what this test needs to wait out, not a chase into horizontal
      // alignment with a moving target.
      sim.debugSetUfo(const Ufo(x: 104, direction: 0, score: 100));

      sim.step(const PadInput(fire: true));
      expect(sim.drainEvents(), [InvadersEvent.playerShot]);

      var killed = false;
      for (var i = 0; i < 500 && !killed; i++) {
        sim.step(PadInput.none);
        if (sim.drainEvents().contains(InvadersEvent.ufoKilled)) killed = true;
      }
      expect(killed, isTrue, reason: 'the UFO was never hit');
    });

    test('clearing a wave produces a waveCleared event', () {
      const rules = InvadersRules.normal;
      final sim = InvadersSim(rules: rules, seed: 1);
      sim.debugSetAliveRows(List<int>.filled(rules.alienRows, 0));

      sim.step(PadInput.none);

      expect(sim.drainEvents(), contains(InvadersEvent.waveCleared));
    });

    test('the player being hit produces a playerKilled event', () {
      // The player never fires and never moves, so the aliens are never
      // thinned and the block eventually marches down into the player's
      // row — a deterministic way to reach the event with no RNG-dependent
      // aim involved (`invaders_sim.dart`'s `_resolveBlockVsPlayerRow`).
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);

      var killed = false;
      for (var i = 0; i < 20000 && !killed; i++) {
        sim.step(PadInput.none);
        if (sim.drainEvents().contains(InvadersEvent.playerKilled)) {
          killed = true;
        }
      }
      expect(killed, isTrue, reason: 'the player was never hit');
    });

    test('crossing the bonus-life threshold produces an extraLife event', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);

      sim.debugAwardScore(10000);

      expect(sim.drainEvents(), [InvadersEvent.extraLife]);
    });

    test('the buffer caps at maxBufferedEvents, dropping the oldest', () {
      final sim = InvadersSim(rules: InvadersRules.normal, seed: 1);
      sim.debugSetAlienFireTimer(1e9); // isolate the alienStep events below

      // Ten events pushed first, so they are the ones past the cap drops.
      for (var i = 0; i < 10; i++) {
        sim.debugAwardScore(10000); // one extraLife each
      }
      // Then exactly `maxBufferedEvents` more, so all of them survive the cap
      // and none of the ten above do — proof it is the oldest that are
      // dropped, not an arbitrary ten.
      for (var i = 0; i < maxBufferedEvents; i++) {
        sim.debugSetAlienTimer(0);
        sim.step(PadInput.none);
      }

      final events = sim.drainEvents();
      expect(events.length, maxBufferedEvents);
      expect(events, everyElement(InvadersEvent.alienStep));
    });
  });
}

/// [rows] rows' worth of otherwise-full alive bitmasks with [deadCol] dead
/// in every row.
List<int> _aliveRowsMissingColumn(int rows, int deadCol) =>
    List<int>.filled(rows, ((1 << alienColumns) - 1) & ~(1 << deadCol));

/// Steps [sim] until its block reverses direction, returning the `originX`
/// it reversed at — the wall box's edge is what decides that value, so a
/// narrower box (fewer alive edge columns) reverses at a larger `originX`.
double _originXWhenReversed(InvadersSim sim) {
  final startDirection = sim.aliens.direction;
  for (var i = 0; i < 20000; i++) {
    sim.step(PadInput.none);
    if (sim.aliens.direction != startDirection) return sim.aliens.originX;
  }
  throw StateError('the block never reversed');
}

/// [rows] rows' worth of alive bitmasks totalling exactly [aliveCount]
/// aliens, filled from row 0 — which cells does not matter to any test that
/// uses this, only how many.
List<int> _aliveRowsWithCount(int rows, int aliveCount) {
  final result = List<int>.filled(rows, 0);
  var remaining = aliveCount;
  for (var row = 0; row < rows && remaining > 0; row++) {
    final take = remaining >= alienColumns ? alienColumns : remaining;
    result[row] = (1 << take) - 1;
    remaining -= take;
  }
  return result;
}

/// [rows] rows' worth of otherwise-full alive bitmasks with [deadRow]
/// entirely dead.
List<int> _aliveRowsMissingRow(int rows, int deadRow) => [
  for (var row = 0; row < rows; row++)
    if (row == deadRow) 0 else (1 << alienColumns) - 1,
];

/// Steps [sim] until it emits `playerKilled`, returning the block's
/// `originY` at that point.
double _originYWhenPlayerKilled(InvadersSim sim) {
  for (var i = 0; i < 20000; i++) {
    sim.step(PadInput.none);
    if (sim.drainEvents().contains(InvadersEvent.playerKilled)) {
      return sim.aliens.originY;
    }
  }
  throw StateError('the player was never hit');
}

/// [rows] rows' worth of alive bitmasks with every column alive in
/// [aliveRow] alone.
List<int> _aliveRowsWithOnlyRow(int rows, int aliveRow) => [
  for (var row = 0; row < rows; row++)
    if (row == aliveRow) (1 << alienColumns) - 1 else 0,
];

/// Steps [sim] until no player shot remains — hit, or left the field.
void _stepUntilNoPlayerShots(InvadersSim sim) {
  for (var i = 0; i < 2000; i++) {
    if (sim.shots.where((shot) => shot.fromPlayer).isEmpty) return;
    sim.step(PadInput.none);
  }
}

int _popcount(int mask) {
  var count = 0;
  var value = mask;
  while (value != 0) {
    value &= value - 1;
    count++;
  }
  return count;
}
