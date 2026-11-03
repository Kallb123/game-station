import '../solver.dart' show unknownSolutionCount;
import 'track_side.dart';
import 'tracks_clues.dart';

/// How many boards satisfy [clues], counting no further than [limit].
///
/// A board is a solution when every track cell is one of the six pieces,
/// every connection is met by the neighbour's matching bit or leaves through a
/// port, the start cell has its west bit and the goal cell its south bit, no
/// other bit leaves the grid, fixed cells hold exactly their fixed piece, the
/// row and column track-cell counts equal the clues, and no closed loop
/// exists (`PLAN-phase-9-tracks.md` §4.3, §4.4).
///
/// Those rules say "one path from start to goal" without saying it: degree two
/// everywhere means every fragment is a path or a loop, a path has two ends,
/// and the only ends the rules allow are the two ports. So there is exactly one
/// path and, once loops are refused, nothing else on the board. The loop check
/// is therefore the whole of the connectivity rule.
///
/// Returns [unknownSolutionCount] when the search tried more than [maxNodes]
/// cell states. As with `countSolutions`, the cap is on work rather than on
/// time, so the answer depends on the clues alone and never on how busy the
/// device was; a caller must not read it as "no solution".
///
/// [onSolution] receives a copy of each solution found, row-major, 0 for an
/// empty cell. The tests use it to check the right board was found, and a
/// cached clue line can use it to recover its solution instead of storing one.
///
/// Cells are decided in row-major order. Each tries empty first and then
/// [TrackSide.pieces] in their frozen order (NS, EW, NE, ES, SW, NW). The order
/// is written down because it decides node counts, which PR 3's benchmark
/// compares across runs; a different order is a different benchmark.
///
/// Throws [RangeError] when [limit] or [maxNodes] is below 1. [clues] is never
/// modified.
int countTracksSolutions(
  TracksClues clues, {
  int limit = 2,
  int maxNodes = 2000000,
  void Function(List<int> cells)? onSolution,
}) {
  if (limit < 1) {
    throw RangeError.range(limit, 1, null, 'limit');
  }
  if (maxNodes < 1) {
    throw RangeError.range(maxNodes, 1, null, 'maxNodes');
  }
  final search = _TracksSearch(clues, limit, maxNodes, onSolution);
  search.step(0);
  return search.capped ? unknownSolutionCount : search.found;
}

/// One run of the counting search: the board it mutates and unwinds, and the
/// state that lets each placement be judged without rescanning the grid.
class _TracksSearch {
  _TracksSearch(this.clues, this.limit, this.maxNodes, this.onSolution)
    : side = clues.spec.side,
      cells = List<int>.filled(clues.spec.cells, 0),
      parent = List<int>.generate(clues.spec.cells, (i) => i),
      rowPlaced = List<int>.filled(clues.spec.side, 0),
      columnPlaced = List<int>.filled(clues.spec.side, 0);

  final TracksClues clues;
  final int limit;
  final int maxNodes;
  final void Function(List<int> cells)? onSolution;
  final int side;

  /// The board so far; cells at or after the one being decided are 0.
  final List<int> cells;

  /// Union-find parents over cells, linked only when a placement joins them.
  /// There is no path compression, so undoing a link is putting the entry back
  /// to itself; [trail] records which entries to restore.
  final List<int> parent;
  final List<int> trail = [];

  final List<int> rowPlaced;
  final List<int> columnPlaced;

  int found = 0;
  int nodes = 0;
  bool capped = false;

  int _find(int x) {
    while (parent[x] != x) {
      x = parent[x];
    }
    return x;
  }

  /// Decides cell [index] every way it can, then recurses.
  ///
  /// Returns true when the caller should stop unwinding: [limit] solutions are
  /// in hand or the node cap is spent. False is an ordinary dead end.
  bool step(int index) {
    if (index == cells.length) {
      // Row and column counts were bounded from both sides as cells were
      // placed, so reaching the end means they are met exactly.
      found++;
      onSolution?.call(List<int>.of(cells));
      return found >= limit;
    }

    final row = index ~/ side;
    final column = index % side;
    final isStart = index == clues.startCell;
    final isGoal = index == clues.goalCell;
    final fixed = clues.fixed[index];

    // What the neighbours already decided force on this cell's north and west
    // bits. A north bit is present exactly when the cell above points south,
    // so a cell under a south-pointing piece must hold track.
    final needNorth = row > 0 && cells[index - side] & TrackSide.south != 0;
    final needWest = column > 0
        ? cells[index - 1] & TrackSide.east != 0
        : isStart;
    // The east and south bits cannot be checked until the neighbour is
    // decided, but a fixed neighbour has already said what it will accept.
    final noEast =
        column == side - 1 ||
        (clues.fixed[index + 1] != 0 &&
            clues.fixed[index + 1] & TrackSide.west == 0);
    final noSouth = row == side - 1
        ? !isGoal
        : (clues.fixed[index + side] != 0 &&
              clues.fixed[index + side] & TrackSide.north == 0);
    final needSouth = row == side - 1 && isGoal;

    // 0 is tried first, then the six pieces.
    for (var option = -1; option < TrackSide.pieces.length; option++) {
      final mask = option < 0 ? 0 : TrackSide.pieces[option];

      if (fixed != 0 && mask != fixed) continue;
      final hasNorth = mask & TrackSide.north != 0;
      final hasWest = mask & TrackSide.west != 0;
      if (hasNorth != needNorth || hasWest != needWest) continue;
      if (mask & TrackSide.east != 0 && noEast) continue;
      if (mask & TrackSide.south != 0 && noSouth) continue;
      if (needSouth && mask & TrackSide.south == 0) continue;
      // Ports are track by definition: the start has its west bit (needWest)
      // and the goal its south bit (needSouth), so an empty cell fails there.

      if (nodes >= maxNodes) {
        capped = true;
        return true;
      }
      nodes++;

      final isTrack = mask != 0;
      if (isTrack) {
        if (rowPlaced[row] >= clues.rowCounts[row]) continue;
        if (columnPlaced[column] >= clues.columnCounts[column]) continue;
      }
      final newRow = rowPlaced[row] + (isTrack ? 1 : 0);
      final newColumn = columnPlaced[column] + (isTrack ? 1 : 0);
      // Enough cells must be left to reach the clue: the rest of this row, and
      // the rows below in this column.
      if (newRow + (side - 1 - column) < clues.rowCounts[row]) continue;
      if (newColumn + (side - 1 - row) < clues.columnCounts[column]) continue;

      final mark = trail.length;
      // The start cell's west bit goes out through the port, not to a cell.
      final joinsWest = hasWest && column > 0;
      if (hasNorth && joinsWest) {
        // Joining two cells already in one component would close a loop.
        final above = _find(index - side);
        final left = _find(index - 1);
        if (above == left) continue;
        parent[index] = above;
        parent[left] = above;
        trail
          ..add(index)
          ..add(left);
      } else if (hasNorth) {
        parent[index] = _find(index - side);
        trail.add(index);
      } else if (joinsWest) {
        parent[index] = _find(index - 1);
        trail.add(index);
      }

      cells[index] = mask;
      rowPlaced[row] = newRow;
      columnPlaced[column] = newColumn;
      final stop = step(index + 1);
      cells[index] = 0;
      if (isTrack) {
        rowPlaced[row]--;
        columnPlaced[column]--;
      }
      while (trail.length > mark) {
        final undone = trail.removeLast();
        parent[undone] = undone;
      }
      if (stop) return true;
    }
    return false;
  }
}
