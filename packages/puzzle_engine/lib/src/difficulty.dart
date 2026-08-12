/// How hard a puzzle is, which is the same thing as which techniques solving it
/// needs (`PLAN.md` §3.4).
///
/// The enum is the tier: `Difficulty.hard.index + 1 == 3`. One value carries
/// both the label the app shows and the tier the solver reports, so there is no
/// table pairing the two that could fall out of step
/// (`PLAN-phase-2.md` §4.5).
///
/// The engine never returns a display string. What a child reads is phase 5's
/// i18n concern; what the engine decides is which of these four a grid is.
enum Difficulty {
  /// T1: naked and hidden singles are enough.
  easy,

  /// T2: also needs a naked or hidden pair, a pointing pair or a box-line
  /// reduction.
  medium,

  /// T3: also needs a naked or hidden triple, or an X-wing.
  hard,

  /// T4: no technique in T1–T3 makes progress, so solving it needs a guess.
  ///
  /// Assigned by exclusion rather than by detection, which is why implementing
  /// further techniques would refine this label without changing which puzzles
  /// the generator produces (`PLAN-phase-2.md` §2).
  expert,
}
