// The phase's central check for Snake, the same one `PLAN-phase-4.md` wrote
// for Invaders and `invaders_sim_equivalence_test.dart` still runs: the same
// run must produce identical state whether it is stepped as 600 frames of a
// 60 Hz phone or 1440 frames of a 144 Hz desktop. `SnakeSim.step` always
// advances by exactly one fixed step; what this test varies is only how many
// times a frame's accumulator calls it — through `shared/fixed_step.dart`'s
// `FixedStepAccumulator`, the production accumulator `snake_game.dart` (PR 4)
// drives the sim with, not a reimplementation of its arithmetic.
//
// This was run, before being trusted, against a copy of `_runFrames` below
// that called `sim.step` once per frame with that frame's own `dt` instead of
// going through the accumulator at all: 600 calls against 1440 calls on the
// same seed diverges within the first few seconds of play, which is what
// makes the pass below a real check rather than one that was never seen red
// (`AGENTS.md`).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/shared/fixed_step.dart';
import 'package:zibo_games/features/arcade/shared/pad_input.dart';
import 'package:zibo_games/features/arcade/snake/model/counting.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_rules.dart';
import 'package:zibo_games/features/arcade/snake/model/snake_sim.dart';

void _runFrames(SnakeSim sim, int frameCount, double frameDt) {
  final accumulator = FixedStepAccumulator();
  for (var frame = 0; frame < frameCount; frame++) {
    final steps = accumulator.advance(frameDt);
    for (var i = 0; i < steps; i++) {
      sim.step(PadInput.none);
    }
  }
}

void main() {
  test('ten seconds of play is identical stepped at 60 Hz and at 144 Hz', () {
    const seed = 2026;
    // `easy` rather than `normal`: its wrapping walls mean nothing ends the
    // run early, so the comparison below exercises ten full seconds of
    // movement, eating and level changes rather than freezing at game over
    // a couple of seconds in, the way three lives into a non-wrapping wall
    // would.
    final at60Hz = SnakeSim(
      rules: SnakeRules.easy,
      counting: SnakeCounting.ones,
      seed: seed,
    );
    final at144Hz = SnakeSim(
      rules: SnakeRules.easy,
      counting: SnakeCounting.ones,
      seed: seed,
    );

    _runFrames(at60Hz, 600, 1 / 60);
    _runFrames(at144Hz, 1440, 1 / 144);

    expect(at144Hz.score, at60Hz.score, reason: 'score');
    expect(at144Hz.lives, at60Hz.lives, reason: 'lives');
    expect(at144Hz.level, at60Hz.level, reason: 'level');
    expect(at144Hz.eaten, at60Hz.eaten, reason: 'eaten');
    expect(at144Hz.longest, at60Hz.longest, reason: 'longest');
    expect(at144Hz.isOver, at60Hz.isOver, reason: 'isOver');
    expect(at144Hz.isRespawning, at60Hz.isRespawning, reason: 'isRespawning');
    expect(at144Hz.heading, at60Hz.heading, reason: 'heading');
    expect(at144Hz.nextValue, at60Hz.nextValue, reason: 'nextValue');

    expect(listEquals(at144Hz.body, at60Hz.body), isTrue, reason: 'body');

    expect(
      at144Hz.targets.length,
      at60Hz.targets.length,
      reason: 'target count',
    );
    for (var i = 0; i < at60Hz.targets.length; i++) {
      expect(
        at144Hz.targets[i].cell,
        at60Hz.targets[i].cell,
        reason: 'target $i cell',
      );
      expect(
        at144Hz.targets[i].value,
        at60Hz.targets[i].value,
        reason: 'target $i value',
      );
    }
  });
}
