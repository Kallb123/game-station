import '../difficulty.dart';
import 'candidates.dart';
import 'fish.dart';
import 'intersections.dart';
import 'singles.dart';
import 'subsets.dart';

/// The techniques the solver knows, in the order it tries them, each paired
/// with the tier it costs and the function that applies it.
///
/// The declaration order *is* the tier order (`PLAN.md` §3.4), so the solver's
/// loop is a walk over [Technique.values]: the first entry that makes progress
/// is by construction the cheapest one available, and the tier it reports is
/// the highest entry it had to reach.
///
/// Holding the function here rather than in a table beside the enum means there
/// is exactly one list to keep in order. It costs an import cycle — this file
/// names the technique functions and each of those files names [Technique] to
/// label its step — which Dart resolves without ceremony, and which is cheaper
/// than a parallel array whose drift would silently mislabel a deduction.
///
/// This is not the full published catalogue of Sudoku techniques, and does not
/// need to be: T4 means "none of these makes progress"
/// (`PLAN-phase-2.md` §2), so a further technique would only relabel puzzles
/// that already generate.
enum Technique {
  /// A cell with one candidate left.
  nakedSingle(Difficulty.easy, applyNakedSingle),

  /// A digit with one place left in a row, column or box.
  hiddenSingle(Difficulty.easy, applyHiddenSingle),

  /// Two cells in a unit holding the same two candidates, which are therefore
  /// unavailable to the rest of the unit.
  nakedPair(Difficulty.medium, applyNakedPair),

  /// Two digits in a unit confined to the same two cells, which therefore hold
  /// nothing else.
  hiddenPair(Difficulty.medium, applyHiddenPair),

  /// A digit confined to one row or column within a box, and so removable from
  /// the rest of that line.
  pointingPair(Difficulty.medium, applyPointingPair),

  /// A digit confined to one box within a row or column, and so removable from
  /// the rest of that box.
  boxLineReduction(Difficulty.medium, applyBoxLineReduction),

  /// Three cells in a unit sharing three candidates between them.
  nakedTriple(Difficulty.hard, applyNakedTriple),

  /// Three digits in a unit confined to the same three cells.
  hiddenTriple(Difficulty.hard, applyHiddenTriple),

  /// A digit whose only places in two rows are the same two columns, or the
  /// transpose.
  xWing(Difficulty.hard, applyXWing);

  const Technique(this.tier, this.apply);

  /// The lowest difficulty a puzzle needing this technique can be.
  final Difficulty tier;

  /// Applies this technique to [CandidateGrid], returning the step it made or
  /// null when it found nothing.
  ///
  /// A non-null return always changed the grid — a placement or at least one
  /// elimination — which is what makes the solver's loop terminate.
  final SolveStep? Function(CandidateGrid grid) apply;
}

/// One candidate ruled out of one cell.
class Elimination {
  /// [digit] can no longer go in the cell at [index].
  const Elimination(this.index, this.digit);

  /// The cell the digit was ruled out of.
  final int index;

  /// The digit that can no longer go there.
  final int digit;

  @override
  bool operator ==(Object other) =>
      other is Elimination && other.index == index && other.digit == digit;

  @override
  int get hashCode => Object.hash(index, digit);

  @override
  String toString() => 'cell $index cannot be $digit';
}

/// One deduction: either a digit placed, or candidates ruled out.
///
/// Both kinds exist because most techniques above T1 never place anything —
/// a naked pair narrows other cells and leaves the grid otherwise as it was.
/// Phase 3's hint UI reads [isPlacement] to decide whether it has an answer to
/// reveal or a reason to explain; nothing in this phase calls it outside tests.
class SolveStep {
  /// A digit deduced for one cell.
  const SolveStep.placement(this.technique, this.index, this.digit)
    : eliminations = const [];

  /// Candidates ruled out without any cell being decided.
  ///
  /// [ruledOut] is never empty: a technique that changed nothing did not make
  /// progress and returns null instead, which is what stops the solver's loop
  /// from spinning on it. It is copied because a step outlives the technique
  /// that made it — phase 3 holds a whole solve while a child works through the
  /// grid, and `SolveReport.steps` is unmodifiable for the same reason.
  SolveStep.eliminations(this.technique, List<Elimination> ruledOut)
    : index = -1,
      digit = 0,
      eliminations = List.unmodifiable(ruledOut),
      assert(ruledOut.isNotEmpty, 'a step must change something');

  /// Which technique reached this conclusion.
  final Technique technique;

  /// The cell a digit was placed in, or -1 for an elimination step.
  final int index;

  /// The digit placed, or 0 for an elimination step.
  final int digit;

  /// The candidates ruled out, empty for a placement.
  final List<Elimination> eliminations;

  /// Whether this step decided a cell rather than narrowing others.
  bool get isPlacement => index >= 0;

  @override
  String toString() => isPlacement
      ? '${technique.name}: $digit at $index'
      : '${technique.name}: ${eliminations.join(', ')}';
}
