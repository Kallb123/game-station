import '../digit_mask.dart';
import 'candidates.dart';
import 'technique.dart';

/// A digit whose only two places in each of two rows sit in the same two
/// columns — or the transpose, two columns pinned to the same two rows.
///
/// Whichever way the four cells resolve, the digit occupies one per row and one
/// per column, so no other cell in those two columns can hold it. This is the
/// one technique here that reasons across units rather than inside one, which
/// is why it sits in T3 with the triples.
///
/// The scan order is frozen: rows as the base before columns, then digits low
/// to high, then base lines in order.
SolveStep? applyXWing(CandidateGrid grid) {
  for (final base in [grid.units.rows, grid.units.cols]) {
    for (var digit = 1; digit <= grid.spec.digits; digit++) {
      // Where the digit can go in each base line, as a bitmask over positions
      // across it: two base lines form an X-wing exactly when their masks are
      // equal and hold two bits.
      final places = List<int>.filled(base.length, 0);
      for (var line = 0; line < base.length; line++) {
        var mask = 0;
        for (var across = 0; across < base[line].length; across++) {
          if (grid.has(base[line][across], digit)) mask |= 1 << across;
        }
        places[line] = mask;
      }

      for (var first = 0; first < base.length; first++) {
        if (bitCount(places[first]) != 2) continue;
        for (var second = first + 1; second < base.length; second++) {
          if (places[second] != places[first]) continue;

          final eliminations = <Elimination>[];
          for (var line = 0; line < base.length; line++) {
            if (line == first || line == second) continue;
            for (var across = 0; across < base[line].length; across++) {
              if (places[first] & (1 << across) == 0) continue;
              final index = base[line][across];
              if (grid.eliminate(index, digit)) {
                eliminations.add(Elimination(index, digit));
              }
            }
          }
          if (eliminations.isEmpty) continue;

          return SolveStep.eliminations(Technique.xWing, eliminations);
        }
      }
    }
  }
  return null;
}
