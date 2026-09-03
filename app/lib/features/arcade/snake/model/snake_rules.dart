// Tuning constants for one run of Snake (`PLAN-phase-7-snake.md` §4.4).
//
// Every number in §4.1 and §4.3 is a field here rather than a literal at its
// call site, for the two reasons `PLAN-phase-4.md` §4.4 gives for
// `InvadersRules`: easy mode is data a test constructs ([normal] and [easy]
// below) rather than a branch a test enumerates, and the device pass in
// `PLAN-phase-7-snake.md` PR 7 is a diff to this file alone.
//
// These are starting values, chosen to be slow rather than measured — the
// device pass is what moves them (`PLAN-phase-7-snake.md` §4.4, §9).

import 'package:flutter/foundation.dart';

/// One run's tuning: lives, growth, the move-speed ramp, wrapping, how many
/// targets a level and the field hold, scoring, and the two pause durations.
///
/// [normal] and [easy] are the only two instances a run is built from
/// (`PLAN.md` §4.4's one arcade-wide easy-mode flag) — nothing else in the app
/// constructs one.
@immutable
class SnakeRules {
  const SnakeRules({
    required this.lives,
    required this.startLength,
    required this.growPerTarget,
    required this.startMoveTicks,
    required this.levelRampTicks,
    required this.perTargetTicks,
    required this.minMoveTicks,
    required this.wrapWalls,
    required this.targetsPerLevel,
    required this.visibleTargets,
    required this.pointsPerTarget,
    required this.levelBonus,
    required this.respawnTicks,
    required this.flashTicks,
  });

  /// Starting lives.
  final int lives;

  /// Cells the snake is long at the start of a run and after every respawn.
  final int startLength;

  /// Cells added to the snake for each target eaten.
  final int growPerTarget;

  /// Fixed steps per cell at level 1 with nothing eaten yet — the slowest the
  /// snake ever moves.
  final int startMoveTicks;

  /// Fixed steps subtracted from the move interval for each level past the
  /// first.
  final int levelRampTicks;

  /// Fixed steps subtracted from the move interval for each target eaten
  /// within the current level.
  final int perTargetTicks;

  /// The floor [startMoveTicks] shrinks towards — the fastest the snake ever
  /// moves.
  final int minMoveTicks;

  /// Whether the head reappears on the opposite edge instead of crashing.
  final bool wrapWalls;

  /// Targets eaten to clear a level — a decade, in both counting modes.
  final int targetsPerLevel;

  /// Targets shown on the field at once in counting mode: the next value,
  /// plus decoys.
  final int visibleTargets;

  /// Points scored for eating the next target.
  final int pointsPerTarget;

  /// Points scored for clearing a level.
  final int levelBonus;

  /// Fixed steps the snake stays paused after a crash, before respawning.
  final int respawnTicks;

  /// Fixed steps a crossed decoy stays flashing for.
  final int flashTicks;

  /// Fixed steps per cell at [level] (1-based) once [eatenThisLevel] targets
  /// have been eaten within it (`PLAN-phase-7-snake.md` §4.2). Both ramps
  /// subtract whole ticks, so every speed the game can reach is exact on
  /// every machine — the equivalence test compares integers rather than
  /// floats accumulated in a different order.
  int moveTicksAt(int level, int eatenThisLevel) =>
      (startMoveTicks -
              levelRampTicks * (level - 1) -
              perTargetTicks * eatenThisLevel)
          .clamp(minMoveTicks, startMoveTicks);

  static const SnakeRules normal = SnakeRules(
    lives: 3,
    startLength: 3,
    growPerTarget: 2,
    startMoveTicks: 20,
    levelRampTicks: 2,
    perTargetTicks: 1,
    minMoveTicks: 8,
    wrapWalls: false,
    targetsPerLevel: 10,
    visibleTargets: 3,
    pointsPerTarget: 10,
    levelBonus: 50,
    respawnTicks: 60,
    flashTicks: 24,
  );

  static const SnakeRules easy = SnakeRules(
    lives: 5,
    startLength: 3,
    growPerTarget: 1,
    startMoveTicks: 32,
    levelRampTicks: 1,
    perTargetTicks: 0,
    minMoveTicks: 16,
    wrapWalls: true,
    targetsPerLevel: 10,
    visibleTargets: 2,
    pointsPerTarget: 10,
    levelBonus: 50,
    respawnTicks: 60,
    flashTicks: 24,
  );
}
