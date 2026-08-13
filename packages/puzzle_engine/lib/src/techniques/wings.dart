import '../digit_mask.dart';
import 'candidates.dart';
import 'technique.dart';

/// Three cells holding `xy`, `xz` and `yz`, where the `xy` cell sees both
/// others: whichever way it falls, one of the other two is `z`, so nothing that
/// sees both of them can be.
///
/// This is the one technique here that reasons about a chain of cells rather
/// than about a unit or a pair of lines, and it is what makes T3 a tier a
/// puzzle can actually land in. Without it, a grid that singles and pairs
/// cannot finish almost always needs guessing too: measured over 60 dug 9x9
/// grids, digging as deep as the tier allowed produced Easy and Medium and
/// never once produced Hard. `PLAN-phase-2.md` §2 assumed further techniques
/// would only relabel puzzles; for this one that was wrong, and the note there
/// now records it.
///
/// The scan order is frozen: pivot cells in index order, then the first pincer
/// in index order, then the second after it.
SolveStep? applyXyWing(CandidateGrid grid) {
  for (var pivot = 0; pivot < grid.spec.cells; pivot++) {
    final pivotMask = grid.maskAt(pivot);
    if (bitCount(pivotMask) != 2) continue;

    // Cells with two candidates that the pivot can see, which are the only
    // cells a wing can be built from.
    final pincers = <int>[];
    for (var index = 0; index < grid.spec.cells; index++) {
      if (index == pivot || !_sees(grid, pivot, index)) continue;
      if (bitCount(grid.maskAt(index)) == 2) pincers.add(index);
    }

    for (var first = 0; first < pincers.length; first++) {
      final firstMask = grid.maskAt(pincers[first]);
      // One digit shared with the pivot and one not: `xz` against `xy`.
      if (bitCount(firstMask & pivotMask) != 1) continue;

      for (var second = first + 1; second < pincers.length; second++) {
        final secondMask = grid.maskAt(pincers[second]);
        if (bitCount(secondMask & pivotMask) != 1) continue;
        // The two pincers must take different digits from the pivot, or they
        // are the same arm twice rather than the two ends of a wing.
        if (firstMask & pivotMask == secondMask & pivotMask) continue;

        final shared = firstMask & secondMask & ~pivotMask;
        if (bitCount(shared) != 1) continue;

        final digit = soleDigit(shared);
        final step = _eliminateSeenByBoth(
          grid,
          pincers[first],
          pincers[second],
          digit,
        );
        if (step != null) return step;
      }
    }
  }
  return null;
}

/// Rules [digit] out of every cell that sees both pincers.
///
/// Returns null when that removes nothing, which is the common case: the wing
/// is a true statement about the grid whether or not any cell is positioned to
/// hear it.
SolveStep? _eliminateSeenByBoth(
  CandidateGrid grid,
  int first,
  int second,
  int digit,
) {
  final eliminations = <Elimination>[];
  for (var index = 0; index < grid.spec.cells; index++) {
    if (index == first || index == second) continue;
    if (!_sees(grid, first, index) || !_sees(grid, second, index)) continue;
    if (grid.eliminate(index, digit)) {
      eliminations.add(Elimination(index, digit));
    }
  }
  if (eliminations.isEmpty) return null;
  return SolveStep.eliminations(Technique.xyWing, eliminations);
}

/// Whether [a] and [b] share a row, a column or a box.
bool _sees(CandidateGrid grid, int a, int b) {
  final spec = grid.spec;
  return spec.rowOf(a) == spec.rowOf(b) ||
      spec.colOf(a) == spec.colOf(b) ||
      spec.boxOf(a) == spec.boxOf(b);
}
