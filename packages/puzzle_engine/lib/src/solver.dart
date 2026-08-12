import 'sudoku_board.dart';

/// What [countSolutions] returns when it ran out of nodes before it could
/// finish: the answer is not 0, 1 or 2, it is unknown.
///
/// Every caller treats unknown as "not unique" — the generator's dig step puts
/// the digit back and moves on. Reading it as "no solutions" would keep a hole
/// that makes the puzzle ambiguous, which is the one outcome the counting is
/// there to prevent.
const int unknownSolutionCount = -1;

/// How much work a search did, for a caller that wants to know.
///
/// Passed in rather than returned so the common case — "is it still unique" —
/// stays a function returning an int. The generator ignores it; the tests use
/// it to show the search stopped early, and the phase 7 benchmark will use it
/// to compare boards without timing them.
class SearchStats {
  /// Digits placed during the search, counted once per placement tried.
  ///
  /// This is the quantity [countSolutions]'s `maxNodes` caps, so a run that
  /// returned [unknownSolutionCount] has `nodes == maxNodes`.
  int nodes = 0;
}

/// How many ways [board] can be completed, counting no further than [max].
///
/// The generator only ever asks whether a puzzle is still unique, so the search
/// stops at the second solution rather than enumerating a grid's millions
/// (`PLAN-phase-2.md` §4.4).
///
/// [board] is not modified: the search runs on a copy. The copy is belt and
/// braces rather than load-bearing today — the search unwinds every placement
/// it makes, including when it gives up at the cap, so the original would
/// survive intact either way. It stays because that is a property of the
/// unwinding being exactly right, which is the kind of thing a later change
/// breaks quietly, and because no test can tell the two apart: deleting the
/// copy leaves the whole suite green.
///
/// Returns [unknownSolutionCount] when the search needed more than [maxNodes]
/// placements. The cap is on work rather than on time, which is what makes it
/// safe here: a deadline would make the result depend on how busy the device
/// was, and puzzle IDs are stored on the assumption that it never depends on
/// anything but the board.
///
/// The search picks the empty cell with the fewest candidates, ties going to
/// the lowest index, and tries digits low to high. Both orders are written down
/// because they decide which puzzles the generator keeps: a different order
/// visits a different number of nodes, so a board near the cap could come back
/// unique under one and unknown under the other.
int countSolutions(
  SudokuBoard board, {
  int max = 2,
  int maxNodes = 2000000,
  SearchStats? stats,
}) {
  if (max < 1) throw RangeError.value(max, 'max', 'must be at least 1');
  if (maxNodes < 1) {
    throw RangeError.value(maxNodes, 'maxNodes', 'must be at least 1');
  }

  final search = _Search(board.copy(), max, maxNodes);
  search.step();
  stats?.nodes = search.nodes;
  return search.capped ? unknownSolutionCount : search.found;
}

/// One run of the counting search, holding the state the recursion threads
/// through: the board it mutates and unwinds, and the two counters.
class _Search {
  _Search(this.board, this.max, this.maxNodes);

  final SudokuBoard board;
  final int max;
  final int maxNodes;

  int found = 0;
  int nodes = 0;
  bool capped = false;

  /// Fills one cell every way it can, recursively.
  ///
  /// Returns true when the caller should stop unwinding and give up its own
  /// remaining digits: either [max] solutions are in hand or the node cap is
  /// spent. Returning false means this branch is exhausted, which is an
  /// ordinary dead end.
  bool step() {
    if (board.isFull) {
      found++;
      return found >= max;
    }

    var bestIndex = -1;
    var bestMask = 0;
    var bestCount = board.spec.digits + 1;

    for (var index = 0; index < board.spec.cells; index++) {
      if (board.digitAt(index) != 0) continue;
      final mask = board.candidateMask(index);
      final count = _bitCount(mask);
      if (count < bestCount) {
        bestCount = count;
        bestIndex = index;
        bestMask = mask;
        // Nothing can beat a cell with no candidates, and a later one would
        // have a higher index, so the tie-break has already been decided.
        // Stopping here is the same choice the full scan would make, reached
        // sooner — not a heuristic that could pick a different cell.
        if (count == 0) break;
      }
    }

    // An empty cell no digit fits: this branch cannot be completed.
    if (bestCount == 0) return false;

    for (var digit = 1; digit <= board.spec.digits; digit++) {
      if (bestMask & (1 << (digit - 1)) == 0) continue;

      if (nodes >= maxNodes) {
        capped = true;
        return true;
      }
      nodes++;

      board.place(bestIndex, digit);
      final stop = step();
      board.remove(bestIndex);
      if (stop) return true;
    }
    return false;
  }
}

/// The number of set bits in [mask], by Kernighan's method — one iteration per
/// candidate rather than one per digit.
int _bitCount(int mask) {
  var remaining = mask;
  var count = 0;
  while (remaining != 0) {
    remaining &= remaining - 1;
    count++;
  }
  return count;
}
