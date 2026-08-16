// Tuning constants for one run of Invaders (`PLAN-phase-4.md` §4.4).
//
// Every number in `PLAN.md` §4.1 is a field here rather than a literal at its
// call site, for two reasons stated in the phase plan: easy mode becomes data
// a test constructs (`normal` and `easy` below) instead of a branch a test
// enumerates, and the device-pass tuning in PR 8 is a diff to this file
// alone.
//
// The starting values match the original cabinet's feel and are expected to
// move after that pass; moving them is not a plan change.

import 'package:flutter/foundation.dart';

/// One run's tuning: alien rows and lives, the march and fire timing, and
/// their per-wave ramps.
///
/// [normal] and [easy] are the only two instances a run is built from
/// (`PLAN.md` §4.1) — nothing else in the app constructs one, which is what
/// keeps "is the numbers table right" a question about two rows rather than
/// about every call site that might have copied one.
@immutable
class InvadersRules {
  const InvadersRules({
    required this.alienRows,
    required this.lives,
    required this.baseStep,
    required this.minStep,
    required this.waveStepRamp,
    required this.fireInterval,
    required this.minFireInterval,
    required this.fireIntervalRamp,
    required this.maxAlienShots,
  });

  /// Rows in the alien block: 5 for [normal], 3 for [easy].
  final int alienRows;

  /// Starting lives.
  final int lives;

  /// The block's march interval at wave 1, in seconds, with every alien
  /// still alive — the time between one sideways step and the next.
  final double baseStep;

  /// The floor [baseStep] shrinks towards, both within a wave as aliens die
  /// and across waves.
  final double minStep;

  /// The fraction [baseStep] is multiplied by for each wave past the first —
  /// 0.88 is "shrinks 12% per wave".
  final double waveStepRamp;

  /// Seconds between one alien shot and the next being allowed, at wave 1.
  final double fireInterval;

  /// The floor [fireInterval] shrinks towards across waves.
  final double minFireInterval;

  /// Seconds subtracted from [fireInterval] for each wave past the first.
  final double fireIntervalRamp;

  /// Alien shots allowed in flight at once.
  final int maxAlienShots;

  /// The block's march interval at wave 1 with every alien still alive,
  /// after [wave]'s ramp — [InvadersSim] scales this further by how many
  /// aliens are still alive (`PLAN.md` §4.1).
  double baseStepForWave(int wave) =>
      _rampedDown(baseStep, waveStepRamp, wave - 1).clamp(minStep, baseStep);

  /// The alien fire cadence for [wave], in seconds.
  double fireIntervalForWave(int wave) =>
      (fireInterval - fireIntervalRamp * (wave - 1)).clamp(
        minFireInterval,
        fireInterval,
      );

  static const InvadersRules normal = InvadersRules(
    alienRows: 5,
    lives: 3,
    baseStep: 0.70,
    minStep: 0.09,
    waveStepRamp: 0.88,
    fireInterval: 1.2,
    minFireInterval: 0.35,
    fireIntervalRamp: 0.08,
    maxAlienShots: 3,
  );

  static const InvadersRules easy = InvadersRules(
    alienRows: 3,
    lives: 5,
    baseStep: 1.10,
    minStep: 0.20,
    waveStepRamp: 0.94,
    fireInterval: 2.2,
    minFireInterval: 0.9,
    fireIntervalRamp: 0.08,
    maxAlienShots: 1,
  );
}

/// [base] multiplied by [ramp] [steps] times, without `dart:math`'s `pow` —
/// one fewer thing to check is deterministic across platforms, on a codebase
/// that already hand-rolls the arithmetic it depends on (`game_rng.dart`).
double _rampedDown(double base, double ramp, int steps) {
  var value = base;
  for (var i = 0; i < steps; i++) {
    value *= ramp;
  }
  return value;
}
