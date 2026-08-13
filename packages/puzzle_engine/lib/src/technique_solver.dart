import 'difficulty.dart';
import 'sudoku_board.dart';
import 'techniques/candidates.dart';
import 'techniques/technique.dart';

export 'difficulty.dart';
export 'techniques/technique.dart' show Elimination, SolveStep, Technique;

/// What solving a board by technique found out about it.
class SolveReport {
  /// A report of a solve that got as far as [steps] and earned [tier].
  const SolveReport({
    required this.solved,
    required this.tier,
    required this.steps,
  });

  /// Whether the techniques finished the grid.
  ///
  /// False means they ran out of ideas, not that the puzzle is unsolvable: an
  /// Expert grid is solvable by search and is exactly the case where this is
  /// false. It is also what an inconsistent grid — one with an empty cell no
  /// digit fits — reports, since no technique advances that either. The
  /// generator never hands one over, because it digs down from a complete grid,
  /// and `countSolutions` is what answers "does this have an answer at all".
  final bool solved;

  /// The difficulty this grid earns: the highest tier any step needed, or
  /// [Difficulty.expert] when [solved] is false.
  final Difficulty tier;

  /// Every deduction, in the order it was made.
  final List<SolveStep> steps;

  @override
  String toString() =>
      'SolveReport(${tier.name}, '
      '${solved ? 'solved' : 'unsolved'}, ${steps.length} steps)';
}

/// Solves as much of [board] as technique allows, and reports what it cost.
///
/// This is how the generator judges a dug puzzle (`PLAN.md` §3.4): a grid is
/// Easy when singles finish it and Expert when nothing here touches it. The
/// tier is therefore a statement about this list of techniques, which is why
/// the list is frozen alongside the generator rather than extended freely — see
/// [Technique].
///
/// [board] is not modified. The generator calls this on a grid it is still
/// digging, and phase 3 will call it on the one a child is looking at.
///
/// The loop terminates because every step it accepts either fills a cell or
/// removes at least one candidate, and neither is ever undone: there is no
/// backtracking here, since a technique states a fact about the grid rather
/// than trying a possibility.
SolveReport solveWithTechniques(SudokuBoard board) {
  final grid = CandidateGrid(board);
  final steps = <SolveStep>[];
  var tier = Difficulty.easy;

  while (!grid.board.isFull) {
    final step = _stepOn(grid);
    if (step == null) break;

    steps.add(step);
    if (step.technique.tier.index > tier.index) tier = step.technique.tier;
  }

  final solved = grid.board.isFull;
  return SolveReport(
    solved: solved,
    tier: solved ? tier : Difficulty.expert,
    steps: List.unmodifiable(steps),
  );
}

/// The next deduction available on [board], or null when technique has run out.
///
/// This is phase 3's hint (`PLAN-phase-2.md` §4.5): the cheapest available
/// step, which is the one a child is most likely to have been able to find.
/// Nothing in this phase calls it outside its tests — the widget that will is
/// phase 3's, and putting it here now would be a phase boundary crossed for no
/// gain.
SolveStep? nextStep(SudokuBoard board) => _stepOn(CandidateGrid(board));

/// The next cell technique can decide on [board], or null when technique runs
/// out before deciding one.
///
/// [nextStep] can return an elimination — most of the catalogue narrows
/// candidates without deciding a cell — but "4 is ruled out of three cells" is
/// not a hint a child can act on (`PLAN-phase-3.md` §3). So this runs the same
/// loop [solveWithTechniques] does, on its own [CandidateGrid], until a step
/// places a digit, and gives up only once the loop runs out of technique
/// first. It touches no generation path: the generator judges a grid by
/// [solveWithTechniques] alone, and this is additive beside it.
SolveStep? nextPlacement(SudokuBoard board) {
  final grid = CandidateGrid(board);
  while (!grid.board.isFull) {
    final step = _stepOn(grid);
    if (step == null) return null;
    if (step.isPlacement) return step;
  }
  return null;
}

/// The first technique that makes progress, tried cheapest first.
///
/// [Technique.values] is in tier order by declaration, so this both applies the
/// step and establishes that nothing cheaper was available — which is what lets
/// the caller read the tier off the step rather than proving a negative.
SolveStep? _stepOn(CandidateGrid grid) {
  for (final technique in Technique.values) {
    final step = technique.apply(grid);
    if (step != null) return step;
  }
  return null;
}
