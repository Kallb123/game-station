import '../digit_mask.dart';
import 'candidates.dart';
import 'technique.dart';

/// The only cell whose digit is forced by its own candidates: one left, so that
/// is what goes there.
///
/// Scanned in index order, which is the frozen order — the first single found
/// is the step reported, and a different scan would report a different step
/// list for the same puzzle.
SolveStep? applyNakedSingle(CandidateGrid grid) {
  for (var index = 0; index < grid.spec.cells; index++) {
    final mask = grid.maskAt(index);
    if (bitCount(mask) != 1) continue;

    final digit = soleDigit(mask);
    grid.place(index, digit);
    return SolveStep.placement(Technique.nakedSingle, index, digit);
  }
  return null;
}

/// A digit with one place left in a unit, whatever else that cell could hold.
///
/// The cell may have several candidates of its own; what is forced is the
/// digit's position, not the cell's content. That is why this is a separate
/// technique from a naked single and not a special case of it.
SolveStep? applyHiddenSingle(CandidateGrid grid) {
  for (final unit in grid.units.all) {
    for (var digit = 1; digit <= grid.spec.digits; digit++) {
      var only = -1;
      var count = 0;
      for (final index in unit) {
        if (!grid.has(index, digit)) continue;
        count++;
        if (count > 1) break;
        only = index;
      }
      if (count != 1) continue;

      grid.place(only, digit);
      return SolveStep.placement(Technique.hiddenSingle, only, digit);
    }
  }
  return null;
}
