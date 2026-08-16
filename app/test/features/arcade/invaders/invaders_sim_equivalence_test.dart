// The phase's central check (`PLAN-phase-4.md` §1, §3): the same run must
// produce identical state whether it is stepped as 600 frames of a 60 Hz
// phone or 1440 frames of a 144 Hz desktop. `InvadersSim.step` always
// advances by exactly `InvadersSim.fixedStep`; what this test varies is only
// how many times a frame's accumulator calls it (`PLAN-phase-4.md` §4.2).
//
// This was run, before being trusted, against a simulation stepped once per
// frame with that frame's own `dt` instead of through an accumulator at all —
// 600 calls against 1440 calls on the same seed diverges within the first
// wave, which is what makes the pass below a real check rather than one that
// was never seen red (`AGENTS.md`).
//
// `_runFrames` tracks *cumulative* elapsed time and derives the step target
// from it each frame, rather than decrementing a running accumulator by
// `fixedStep` as `PLAN-phase-4.md` §4.2's sketch does. That subtractive form
// was tried first and failed this test by exactly one tick at 144 Hz: 1440
// additions of `1/144` round to a hair under 10.0 s in binary floating point,
// where 600 additions of `1/60` land on exactly 10.0 s, so the two runs
// carried a different leftover remainder into a step neither took. Deriving
// the target from the running total avoids compounding that rounding error
// and both rates land on the same 1200 steps — worth knowing before
// `invaders_game.dart` (PR 4) copies the sketch verbatim.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_rules.dart';
import 'package:zibo_games/features/arcade/invaders/model/invaders_sim.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';

const int _maxStepsPerFrame = 8;

/// Runs [sim] for [frameCount] frames of [frameDt] seconds each.
void _runFrames(InvadersSim sim, int frameCount, double frameDt) {
  var elapsed = 0.0;
  var stepsDone = 0;
  for (var frame = 0; frame < frameCount; frame++) {
    elapsed += frameDt;
    final target = (elapsed / InvadersSim.fixedStep).floor();
    var steps = 0;
    while (stepsDone < target && steps < _maxStepsPerFrame) {
      sim.step(PadInput.none);
      stepsDone++;
      steps++;
    }
    // A frame that hit the clamp drops the backlog rather than chasing it.
    if (steps == _maxStepsPerFrame) stepsDone = target;
  }
}

void main() {
  test('ten seconds of play is identical stepped at 60 Hz and at 144 Hz', () {
    const seed = 2026;
    final at60Hz = InvadersSim(rules: InvadersRules.normal, seed: seed);
    final at144Hz = InvadersSim(rules: InvadersRules.normal, seed: seed);

    _runFrames(at60Hz, 600, 1 / 60);
    _runFrames(at144Hz, 1440, 1 / 144);

    expect(at144Hz.score, at60Hz.score, reason: 'score');
    expect(at144Hz.lives, at60Hz.lives, reason: 'lives');
    expect(at144Hz.wave, at60Hz.wave, reason: 'wave');
    expect(at144Hz.kills, at60Hz.kills, reason: 'kills');
    expect(at144Hz.isOver, at60Hz.isOver, reason: 'isOver');

    expect(
      listEquals(at144Hz.aliens.aliveRows, at60Hz.aliens.aliveRows),
      isTrue,
      reason: 'alien bits',
    );
    expect(
      at144Hz.aliens.originX,
      at60Hz.aliens.originX,
      reason: 'alien originX',
    );
    expect(
      at144Hz.aliens.originY,
      at60Hz.aliens.originY,
      reason: 'alien originY',
    );
    expect(
      at144Hz.aliens.direction,
      at60Hz.aliens.direction,
      reason: 'alien direction',
    );

    expect(at144Hz.player.x, at60Hz.player.x, reason: 'player x');
    expect(at144Hz.player.alive, at60Hz.player.alive, reason: 'player alive');

    expect(at144Hz.shots.length, at60Hz.shots.length, reason: 'shot count');
    for (var i = 0; i < at60Hz.shots.length; i++) {
      expect(at144Hz.shots[i].x, at60Hz.shots[i].x, reason: 'shot $i x');
      expect(at144Hz.shots[i].y, at60Hz.shots[i].y, reason: 'shot $i y');
      expect(
        at144Hz.shots[i].fromPlayer,
        at60Hz.shots[i].fromPlayer,
        reason: 'shot $i fromPlayer',
      );
    }

    expect(
      at144Hz.bunkers.length,
      at60Hz.bunkers.length,
      reason: 'bunker count',
    );
    for (var i = 0; i < at60Hz.bunkers.length; i++) {
      expect(
        listEquals(at144Hz.bunkers[i].blocks, at60Hz.bunkers[i].blocks),
        isTrue,
        reason: 'bunker $i blocks',
      );
    }
  });
}
