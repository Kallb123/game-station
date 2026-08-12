import '../digit_mask.dart';
import 'candidates.dart';
import 'technique.dart';

/// Two cells in a unit that hold the same two candidates: between them they use
/// both digits, so no other cell in the unit can.
SolveStep? applyNakedPair(CandidateGrid grid) =>
    _nakedSubset(grid, 2, Technique.nakedPair);

/// Three cells in a unit sharing three candidates between them, by the same
/// argument as a naked pair.
///
/// The three cells need not each hold all three digits — two of them may hold
/// two apiece. What matters is that the union is three digits over three cells.
SolveStep? applyNakedTriple(CandidateGrid grid) =>
    _nakedSubset(grid, 3, Technique.nakedTriple);

/// Two digits in a unit that can only go in the same two cells: those cells
/// hold those digits, so everything else they might have held is out.
SolveStep? applyHiddenPair(CandidateGrid grid) =>
    _hiddenSubset(grid, 2, Technique.hiddenPair);

/// Three digits in a unit confined to the same three cells.
SolveStep? applyHiddenTriple(CandidateGrid grid) =>
    _hiddenSubset(grid, 3, Technique.hiddenTriple);

/// Naked pairs and triples, which differ only in [size].
///
/// A cell qualifies when it has between two and [size] candidates: one would be
/// a naked single, and more than [size] cannot fit inside a [size]-digit union.
/// The subset itself eliminates nothing from its own cells — it narrows the
/// rest of the unit — so a subset whose unit holds nothing else is found and
/// discarded rather than reported as a step.
SolveStep? _nakedSubset(CandidateGrid grid, int size, Technique technique) {
  for (final unit in grid.units.all) {
    final pool = <int>[];
    for (final index in unit) {
      final count = bitCount(grid.maskAt(index));
      if (count >= 2 && count <= size) pool.add(index);
    }
    if (pool.length < size) continue;

    SolveStep? found;
    _combinations(pool.length, size, (picks) {
      var union = 0;
      for (final pick in picks) {
        union |= grid.maskAt(pool[pick]);
      }
      if (bitCount(union) != size) return false;

      final eliminations = <Elimination>[];
      for (final index in unit) {
        if (_holds(pool, picks, index)) continue;
        for (var digit = 1; digit <= grid.spec.digits; digit++) {
          if (union & bitFor(digit) == 0) continue;
          if (grid.eliminate(index, digit)) {
            eliminations.add(Elimination(index, digit));
          }
        }
      }
      if (eliminations.isEmpty) return false;

      found = SolveStep.eliminations(technique, eliminations);
      return true;
    });
    if (found != null) return found;
  }
  return null;
}

/// Hidden pairs and triples: the naked case with cells and digits swapped.
///
/// A digit qualifies when it has between two and [size] places left in the
/// unit; one place would be a hidden single. When [size] such digits share
/// exactly [size] cells, those cells belong to those digits and lose whatever
/// else they were holding.
SolveStep? _hiddenSubset(CandidateGrid grid, int size, Technique technique) {
  for (final unit in grid.units.all) {
    // Where each digit can still go, as a bitmask over positions in the unit
    // rather than over cells of the grid: a unit is at most nine cells, so a
    // subset's footprint is one integer to union and one to count.
    final places = List<int>.filled(grid.spec.digits + 1, 0);
    final pool = <int>[];
    for (var digit = 1; digit <= grid.spec.digits; digit++) {
      var mask = 0;
      for (var slot = 0; slot < unit.length; slot++) {
        if (grid.has(unit[slot], digit)) mask |= 1 << slot;
      }
      places[digit] = mask;
      final count = bitCount(mask);
      if (count >= 2 && count <= size) pool.add(digit);
    }
    if (pool.length < size) continue;

    SolveStep? found;
    _combinations(pool.length, size, (picks) {
      var union = 0;
      var subset = 0;
      for (final pick in picks) {
        union |= places[pool[pick]];
        subset |= bitFor(pool[pick]);
      }
      if (bitCount(union) != size) return false;

      final eliminations = <Elimination>[];
      for (var slot = 0; slot < unit.length; slot++) {
        if (union & (1 << slot) == 0) continue;
        for (var digit = 1; digit <= grid.spec.digits; digit++) {
          if (subset & bitFor(digit) != 0) continue;
          if (grid.eliminate(unit[slot], digit)) {
            eliminations.add(Elimination(unit[slot], digit));
          }
        }
      }
      if (eliminations.isEmpty) return false;

      found = SolveStep.eliminations(technique, eliminations);
      return true;
    });
    if (found != null) return found;
  }
  return null;
}

/// Whether [index] is one of the cells [picks] selects out of [pool].
bool _holds(List<int> pool, List<int> picks, int index) {
  for (final pick in picks) {
    if (pool[pick] == index) return true;
  }
  return false;
}

/// Every combination of [size] positions out of [poolSize], in ascending order,
/// stopping at the first one [visit] accepts.
///
/// The picks list is reused between calls, so [visit] must not keep it. Nothing
/// here allocates per combination, which matters because the triple scan runs
/// over every unit of every attempt the generator makes.
void _combinations(int poolSize, int size, bool Function(List<int>) visit) {
  final picks = List<int>.filled(size, 0);

  bool walk(int start, int depth) {
    if (depth == size) return visit(picks);
    for (var pick = start; pick + (size - depth) <= poolSize; pick++) {
      picks[depth] = pick;
      if (walk(pick + 1, depth + 1)) return true;
    }
    return false;
  }

  walk(0, 0);
}
