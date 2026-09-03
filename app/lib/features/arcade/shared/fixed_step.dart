// The frame-rate-independent clock every arcade game steps on
// (`PLAN.md` §4.1, `PLAN-phase-4.md` §4.2), moved here from
// `invaders/invaders_game.dart` and off `InvadersSim` once a second game was
// in hand to share it with (`PLAN-phase-7-snake.md` §4.7) — two copies of the
// one piece of arithmetic the whole fixed-step guarantee rests on is worse
// than one, and only one of them had an equivalence test.
//
// No behaviour changed in the move: [FixedStepAccumulator.advance] is the
// same running-total arithmetic `InvadersGame.update` had, unchanged, and
// `invaders_sim_equivalence_test.dart`'s header is still the record of why it
// is a running total rather than something decremented back towards zero —
// the subtractive form rounds two frame rates to a different leftover
// remainder at exactly the point their totals should agree.

/// Every fixed step is exactly this many seconds — 1/120 s
/// (`PLAN-phase-4.md` §4.2). It divides 60 Hz exactly and halves the judder
/// 1/60 s would leave at 144 Hz. Shared by every arcade game so two games can
/// never end up stepping on two different ticks.
const double fixedStep = 1 / 120;

/// A frame that arrives this late — a garbage-collection pause, a resumed
/// app, a debugger breakpoint — asks for far more steps than a frame can
/// afford (`PLAN-phase-4.md` §4.2). Past this many, the remainder is dropped
/// rather than chased: losing time reads to a child as a shorter pause, where
/// chasing it would replay a burst of input nobody saw coming.
const int maxStepsPerFrame = 8;

/// Turns a stream of frame deltas into a count of [fixedStep]s to run, shared
/// by every arcade game's Flame layer (`PLAN-phase-7-snake.md` §4.7).
///
/// Keeps a running total of frame time and a count of the steps already taken
/// from it, rather than subtracting a leftover each frame: the subtractive
/// form rounds two frame rates to a different remainder at exactly the point
/// their totals should agree, which is the bug
/// `invaders_sim_equivalence_test.dart` was written to catch.
class FixedStepAccumulator {
  /// Seconds of frame time not yet turned into a step.
  double _elapsed = 0;

  /// How many fixed-step-worths of [_elapsed] have been accounted for —
  /// either by a step [advance] returned, or by [maxStepsPerFrame] dropping
  /// the rest of a backlog. Distinct from [totalSteps]: after a drop this
  /// jumps ahead of the steps actually taken, which is the point — it is what
  /// stops the next frame trying to make up the difference.
  int _consumedSteps = 0;

  /// The steps [advance] has returned in total since construction or the last
  /// [reset] — a test seam, so a test can assert the accumulator's arithmetic
  /// directly rather than through a side effect on whatever consumes the
  /// steps.
  int totalSteps = 0;

  /// Adds [dt] seconds of frame time and returns how many [fixedStep]s have
  /// become due since the last call, capped at [maxStepsPerFrame] with any
  /// remainder dropped rather than queued for the next frame.
  int advance(double dt) {
    _elapsed += dt;
    final target = (_elapsed / fixedStep).floor();
    var steps = 0;
    while (_consumedSteps < target && steps < maxStepsPerFrame) {
      _consumedSteps++;
      steps++;
    }
    // The clamp above stopped short of `target`: drop the backlog rather than
    // letting the next frame try to make it up in one go.
    if (steps == maxStepsPerFrame) _consumedSteps = target;
    totalSteps += steps;
    return steps;
  }

  /// Zeroes the accumulator without replaying the skipped interval
  /// (`PLAN-phase-4.md` §4.5) — the delta across a pause is not game time, and
  /// this is what stops the next frame trying to make it up.
  void reset() {
    _elapsed = 0;
    _consumedSteps = 0;
  }
}
