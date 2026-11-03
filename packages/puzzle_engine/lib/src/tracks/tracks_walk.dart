import '../rng.dart';
import 'track_side.dart';
import 'tracks_spec.dart';

/// The shape a generated path must have: how many cells long and how many
/// corners (`PLAN-phase-9-tracks.md` §4.5).
///
/// The length band keeps the clue counts informative (a path that fills a third
/// of the grid says little per row) and the turn floor keeps the path from
/// hugging an edge, which an unconstrained walk often does and which makes a
/// dull puzzle.
class TracksWalkBand {
  /// A band of paths with [minLength] to [maxLength] cells inclusive and at
  /// least [minTurns] corner pieces.
  const TracksWalkBand({
    required this.minLength,
    required this.maxLength,
    required this.minTurns,
  });

  /// The fewest cells a path may have, the start and the goal included.
  final int minLength;

  /// The most cells a path may have.
  final int maxLength;

  /// The fewest corner pieces in the solution the path makes.
  final int minTurns;
}

/// Cells entered before [walkTracksPath] gives up, unless told otherwise.
///
/// Chosen by measurement over 1000 seeds per size (`PLAN-phase-9-tracks.md`
/// §4.5). A walk that succeeds almost always does so within about 100 cells
/// (9x9 median 45, 95th percentile 110); the rest is a long tail of walks
/// wandering in a region the band cannot be met from. At 1000 the hit rate is
/// 99.9% on 7x7 and 97.8% on 9x9, against 98.7% at 3000 and 99.6% at 10000,
/// so extra budget buys a fraction of a percent while a miss costs a whole
/// walk. The generator abandons the attempt and moves to the next seed.
const int defaultTracksWalkBudget = 1000;

/// Draws the ports: the start row, then the goal column.
///
/// The start is on the west edge and the goal on the south edge
/// (`PLAN-phase-9-tracks.md` §2). They share a cell only in the bottom-left
/// corner, so when the start is on the bottom row the goal column skips
/// column 0 and the two cells are never the same. The start is drawn first;
/// the order is part of the frozen stream.
(int startRow, int goalColumn) drawTracksPorts(TracksSpec spec, Rng rng) {
  final side = spec.side;
  final startRow = rng.nextInt(side);
  final goalColumn = startRow == side - 1
      ? 1 + rng.nextInt(side - 1)
      : rng.nextInt(side);
  return (startRow, goalColumn);
}

/// A random self-avoiding path of cells from the start cell to the goal cell
/// that fits [band], or null when [stepBudget] cells are entered first.
///
/// Randomised depth-first: at each cell the four directions are tried in an
/// order [rng] shuffles. The shuffle is of a fresh copy of [TrackSide.all]
/// each time a cell is entered, including when the search returns to it after
/// backtracking. That is a draw from the frozen stream and so part of the
/// generator's output, as in `_fill` in `generator.dart`: a shuffle hoisted out
/// of the recursion would produce different paths from the same seed.
///
/// The goal ends the path. Entering it accepts when the length and the corner
/// count are in [band], and otherwise backtracks. Corners are counted as the
/// solution's masks will show them, with the start entered moving east through
/// its port and the goal left moving south through its.
///
/// Two prunes keep the walk from exploring dead regions:
///
/// - **Length.** Cells so far plus the Manhattan distance to the goal exceeds
///   `maxLength`: no path from here can be short enough.
/// - **Reach.** A flood fill through unvisited cells cannot reach the goal: the
///   walk has cut the grid in two.
///
/// Track cells may sit side by side without connecting; that is legal in the
/// genre, so nothing here keeps a path off its own neighbours.
///
/// The result lists the cell indices, row-major, from the start cell to the
/// goal cell.
List<int>? walkTracksPath(
  TracksSpec spec,
  int startRow,
  int goalColumn,
  Rng rng,
  TracksWalkBand band, {
  int stepBudget = defaultTracksWalkBudget,
}) {
  final walk = _Walk(
    spec,
    spec.indexAt(startRow, 0),
    spec.indexAt(spec.side - 1, goalColumn),
    rng,
    band,
    stepBudget,
  );
  return walk.run();
}

/// The connection masks of the solution that [path] draws, row-major, with the
/// start's west bit and the goal's south bit set.
///
/// Throws an [ArgumentError] if two consecutive cells are not neighbours.
List<int> tracksSolutionFor(TracksSpec spec, List<int> path) {
  final masks = List<int>.filled(spec.cells, 0);
  for (var i = 0; i < path.length; i++) {
    final into = i == 0
        ? TrackSide.west
        : _sideFacing(spec, path[i], path[i - 1]);
    final out = i == path.length - 1
        ? TrackSide.south
        : _sideFacing(spec, path[i], path[i + 1]);
    masks[path[i]] = into | out;
  }
  return masks;
}

/// The number of corner pieces in [solution], which is how many times the
/// track turns.
int tracksTurns(List<int> solution) {
  var turns = 0;
  for (final mask in solution) {
    if (mask != 0 &&
        mask != (TrackSide.north | TrackSide.south) &&
        mask != (TrackSide.east | TrackSide.west)) {
      turns++;
    }
  }
  return turns;
}

/// The side of cell [from] that faces its neighbour [to].
int _sideFacing(TracksSpec spec, int from, int to) {
  final delta = to - from;
  if (delta == 1 && spec.columnOf(from) < spec.side - 1) return TrackSide.east;
  if (delta == -1 && spec.columnOf(from) > 0) return TrackSide.west;
  if (delta == spec.side) return TrackSide.south;
  if (delta == -spec.side) return TrackSide.north;
  throw ArgumentError('cells $from and $to are not neighbours');
}

/// The state of one [walkTracksPath] call, so the recursion carries a cell and
/// a direction rather than a dozen parameters.
class _Walk {
  _Walk(this.spec, this.start, this.goal, this.rng, this.band, this.budget)
    : side = spec.side,
      visited = List<bool>.filled(spec.cells, false),
      mark = List<int>.filled(spec.cells, 0),
      stack = List<int>.filled(spec.cells, 0),
      path = <int>[],
      goalRow = spec.rowOf(goal),
      goalColumn = spec.columnOf(goal);

  final TracksSpec spec;
  final int side;
  final int start;
  final int goal;
  final int goalRow;
  final int goalColumn;
  final Rng rng;
  final TracksWalkBand band;
  final int budget;

  final List<bool> visited;
  final List<int> path;

  // Flood-fill scratch, allocated once per walk. A cell is "seen" when its
  // mark equals the current stamp, so nothing is cleared between fills.
  final List<int> mark;
  final List<int> stack;
  int _stamp = 0;

  int _entered = 0;

  List<int>? run() {
    if (!_enter(start, TrackSide.east, 0)) return null;
    return List<int>.of(path);
  }

  /// Enters [cell], moving [heading] (the side of travel, `east` for the start
  /// since the port is on its west), with [turns] corners already behind it.
  /// Returns true with [path] complete, false to backtrack or on budget
  /// exhaustion (which [_entered] records).
  bool _enter(int cell, int heading, int turns) {
    if (++_entered > budget) return false;

    path.add(cell);
    visited[cell] = true;

    if (cell == goal) {
      // Leaving through the south port is a corner unless the track arrived
      // moving south.
      final total = turns + (heading == TrackSide.south ? 0 : 1);
      if (path.length >= band.minLength &&
          path.length <= band.maxLength &&
          total >= band.minTurns) {
        return true;
      }
    } else if (path.length + _distanceToGoal(cell) <= band.maxLength &&
        _goalReachable(cell)) {
      final sides = List<int>.of(TrackSide.all);
      rng.shuffle(sides);
      final row = spec.rowOf(cell);
      final column = spec.columnOf(cell);
      for (final toward in sides) {
        final int next;
        if (toward == TrackSide.north) {
          if (row == 0) continue;
          next = cell - side;
        } else if (toward == TrackSide.south) {
          if (row == side - 1) continue;
          next = cell + side;
        } else if (toward == TrackSide.east) {
          if (column == side - 1) continue;
          next = cell + 1;
        } else {
          if (column == 0) continue;
          next = cell - 1;
        }
        if (visited[next]) continue;
        if (_enter(next, toward, turns + (toward == heading ? 0 : 1))) {
          return true;
        }
        if (_entered > budget) break;
      }
    }

    visited[cell] = false;
    path.removeLast();
    return false;
  }

  int _distanceToGoal(int cell) {
    final dr = goalRow - spec.rowOf(cell);
    final dc = goalColumn - spec.columnOf(cell);
    return (dr < 0 ? -dr : dr) + (dc < 0 ? -dc : dc);
  }

  /// Whether the goal can still be reached from [from] through unvisited
  /// cells. The goal is never expanded: it ends the path.
  bool _goalReachable(int from) {
    final stamp = ++_stamp;
    var top = 0;
    stack[top++] = from;
    mark[from] = stamp;
    while (top > 0) {
      final cell = stack[--top];
      final row = spec.rowOf(cell);
      final column = spec.columnOf(cell);
      for (var d = 0; d < 4; d++) {
        final int next;
        if (d == 0) {
          if (row == 0) continue;
          next = cell - side;
        } else if (d == 1) {
          if (column == side - 1) continue;
          next = cell + 1;
        } else if (d == 2) {
          if (row == side - 1) continue;
          next = cell + side;
        } else {
          if (column == 0) continue;
          next = cell - 1;
        }
        if (visited[next] || mark[next] == stamp) continue;
        if (next == goal) return true;
        mark[next] = stamp;
        stack[top++] = next;
      }
    }
    return false;
  }
}
