import 'candidates.dart';
import 'technique.dart';

/// A digit whose places inside a box all fall on one row or one column.
///
/// Wherever in the box it ends up, it is on that line, so the rest of the line
/// outside the box cannot have it. Boxes are scanned in order, and for each box
/// the row case before the column case.
SolveStep? applyPointingPair(CandidateGrid grid) {
  for (var box = 0; box < grid.units.boxes.length; box++) {
    final cells = grid.units.boxes[box];
    for (var digit = 1; digit <= grid.spec.digits; digit++) {
      final places = _placesFor(grid, cells, digit);
      if (places.length < 2) continue;

      final row = _sharedLine(places, grid.spec.rowOf);
      if (row >= 0) {
        final step = _eliminateOutside(
          grid,
          from: grid.units.rows[row],
          keepBox: box,
          digit: digit,
          technique: Technique.pointingPair,
        );
        if (step != null) return step;
      }

      final col = _sharedLine(places, grid.spec.colOf);
      if (col >= 0) {
        final step = _eliminateOutside(
          grid,
          from: grid.units.cols[col],
          keepBox: box,
          digit: digit,
          technique: Technique.pointingPair,
        );
        if (step != null) return step;
      }
    }
  }
  return null;
}

/// A digit whose places along a row or column all fall inside one box.
///
/// The mirror of a pointing pair: the line claims the digit for that box, so
/// the rest of the box cannot have it. Rows are scanned before columns.
SolveStep? applyBoxLineReduction(CandidateGrid grid) {
  for (final lines in [grid.units.rows, grid.units.cols]) {
    for (final line in lines) {
      for (var digit = 1; digit <= grid.spec.digits; digit++) {
        final places = _placesFor(grid, line, digit);
        if (places.length < 2) continue;

        final box = _sharedLine(places, grid.spec.boxOf);
        if (box < 0) continue;

        final eliminations = <Elimination>[];
        for (final index in grid.units.boxes[box]) {
          if (places.contains(index)) continue;
          if (grid.eliminate(index, digit)) {
            eliminations.add(Elimination(index, digit));
          }
        }
        if (eliminations.isEmpty) continue;

        return SolveStep.eliminations(Technique.boxLineReduction, eliminations);
      }
    }
  }
  return null;
}

/// The cells of [unit] that can still hold [digit].
List<int> _placesFor(CandidateGrid grid, List<int> unit, int digit) {
  final places = <int>[];
  for (final index in unit) {
    if (grid.has(index, digit)) places.add(index);
  }
  return places;
}

/// The line every cell in [places] belongs to, by [lineOf], or -1 when they do
/// not all share one.
int _sharedLine(List<int> places, int Function(int index) lineOf) {
  final first = lineOf(places[0]);
  for (final index in places) {
    if (lineOf(index) != first) return -1;
  }
  return first;
}

/// Rules [digit] out of every cell of [from] that is not in [keepBox].
///
/// Returns null when nothing changed: the digit was already absent from the
/// rest of the line, which is a true statement about the grid and not a step.
SolveStep? _eliminateOutside(
  CandidateGrid grid, {
  required List<int> from,
  required int keepBox,
  required int digit,
  required Technique technique,
}) {
  final eliminations = <Elimination>[];
  for (final index in from) {
    if (grid.spec.boxOf(index) == keepBox) continue;
    if (grid.eliminate(index, digit)) {
      eliminations.add(Elimination(index, digit));
    }
  }
  if (eliminations.isEmpty) return null;
  return SolveStep.eliminations(technique, eliminations);
}
