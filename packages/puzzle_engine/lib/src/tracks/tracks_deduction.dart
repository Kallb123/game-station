import 'dart:typed_data';

import '../difficulty.dart';
import 'tracks_clues.dart';

/// What solving clues by deduction found.
///
/// Sound by construction: every rule below is a logical consequence of the
/// rules of the game (`PLAN-phase-9-tracks.md` §4.3), so a report with
/// [solved] true proves the clues have exactly one solution, namely [cells].
/// The generator relies on that to dig without calling the counter after every
/// removal (§4.5). The converse does not hold: unsolved clues may still be
/// unique, only too hard for the rules the ceiling allowed.
class TracksSolveReport {
  /// Builds a report; [cells] is stored as given.
  const TracksSolveReport({
    required this.solved,
    required this.tier,
    required this.cells,
  });

  /// Whether every cell and every connection was decided.
  final bool solved;

  /// The highest tier a deduction needed, or [Difficulty.expert] when [solved]
  /// is false, meaning the tiers the ceiling allowed were not enough.
  final Difficulty tier;

  /// When [solved], the solution as connection masks, row-major, 0 for an
  /// empty cell. Otherwise the connections proven so far, in the same form, so
  /// a cell holding a single bit has one edge proven and its other still open.
  final List<int> cells;
}

/// Solves [clues] by deduction, never using a tier above [ceiling]; a puzzle
/// that would need one reports `solved: false, tier: Difficulty.expert`.
///
/// The rules, cheapest first (`PLAN-phase-9-tracks.md` §4.5):
///
/// * **T1 (easy).** A row or column whose count is met has its unknown cells
///   empty; one whose unknown cells exactly make up the shortfall has them all
///   track. A track cell with two connections takes no more; with exactly two
///   open sides it takes both. A cell with fewer than two open sides is empty.
///   A connection into an empty cell is impossible.
/// * **T2 (medium).** An unknown connection between two cells of one fragment
///   would close a loop, so it is off. A cell the start cannot reach through
///   open connections and non-empty cells is empty.
/// * **T3 (hard).** One step of lookahead: assume a cell track, then empty, or
///   a side of a track cell on, then off; run T1 and T2 on a copy, and a
///   contradiction proves the opposite.
///
/// T1 runs to a fixpoint; T2 runs only when T1 has stalled and the clues are
/// not solved; T3 only when T2 has stalled. Any progress returns to T1. The
/// tier is the highest one used. The rules are monotone, so the fixpoint, and
/// with it the tier, does not depend on the order cells are visited in.
///
/// A finished board is checked once more against the rules before it is
/// reported solved, so a bug in a rule could cost a puzzle but never vouch for
/// one that has no solution.
///
/// A [ceiling] of [Difficulty.expert] is the same as [Difficulty.hard]: there
/// is no tier above T3 to allow.
///
/// Not exported, like `countTracksSolutions`: it is how a puzzle is built.
TracksSolveReport solveTracks(
  TracksClues clues, {
  Difficulty ceiling = Difficulty.hard,
}) {
  final state = _State.initial(_Grid(clues), clues);
  if (!state.dead) state.deduce(_tierNumber(ceiling));

  if (!state.dead && state.isDecided && state.isSolution) {
    return TracksSolveReport(
      solved: true,
      tier: _difficultyOf(state.tier),
      cells: state.masks(),
    );
  }
  return TracksSolveReport(
    solved: false,
    tier: Difficulty.expert,
    cells: state.masks(),
  );
}

/// One cell deduction can prove, for the hint button (`PLAN-phase-9-tracks.md`
/// §4.5, §4.13).
class TracksStep {
  /// Builds a step.
  const TracksStep({
    required this.cell,
    required this.mask,
    required this.tier,
  });

  /// The cell's index, row-major.
  final int cell;

  /// The piece that cell holds in the solution: two connection bits.
  final int mask;

  /// The highest tier deduction needed to reach this cell from the board, so
  /// it also says how far the hint had to look.
  final Difficulty tier;

  @override
  String toString() => 'TracksStep(cell: $cell, mask: $mask, tier: $tier)';
}

/// The first cell whose full piece deduction proves from [clues] plus the
/// connections in [board], and which [board] does not already show as that
/// piece; null when there is none (board complete, contradiction, or stalled).
///
/// [board] holds connection masks, row-major, as the session keeps them: a bit
/// is a connection the player has drawn, a cell may hold fewer than two, and 0
/// is not yet a track as far as this function knows. Precondition: [board]
/// holds no wrong connection. A hint that disagrees with the solution would
/// mislead, so PR 7 checks the board against the solution first and points at
/// the mistake instead (§4.13). A board that breaks the rules is not repaired
/// here; it ends in a contradiction and the answer is null.
///
/// Cells are scanned in index order before any deduction and again after each
/// rule applies, so the answer is the cheapest provable cell, and the same one
/// every time. Cells fixed by [clues] are never returned: the player sees them
/// already. A cell proven empty is not a step either, because the board shows
/// an empty cell as 0 whether or not the player has worked it out.
///
/// Throws an [ArgumentError] when [board] has the wrong length.
TracksStep? nextTracksStep(TracksClues clues, List<int> board) {
  if (board.length != clues.spec.cells) {
    throw ArgumentError.value(
      board.length,
      'board',
      'must have ${clues.spec.cells} entries',
    );
  }
  final state = _State.initial(_Grid(clues), clues);
  for (var i = 0; i < board.length && !state.dead; i++) {
    for (var k = 0; k < 4; k++) {
      if (board[i] & (1 << k) != 0) state.setSide(i, k, _yes);
    }
  }
  if (state.dead) return null;

  TracksStep? found;
  bool probe(_State s) {
    final grid = s.grid;
    for (var i = 0; i < grid.n; i++) {
      if (clues.fixed[i] != 0 || s.cells[i] != _yes) continue;
      final mask = s.maskOf(i);
      if (_bitCount(mask) == 2 && mask != board[i]) {
        found = TracksStep(cell: i, mask: mask, tier: _difficultyOf(s.tier));
        return true;
      }
    }
    return false;
  }

  state.probe = probe;
  if (probe(state)) return found;
  state.deduce(3);
  return found;
}

int _tierNumber(Difficulty ceiling) => switch (ceiling) {
  Difficulty.easy => 1,
  Difficulty.medium => 2,
  Difficulty.hard || Difficulty.expert => 3,
};

Difficulty _difficultyOf(int tier) => switch (tier) {
  1 => Difficulty.easy,
  2 => Difficulty.medium,
  _ => Difficulty.hard,
};

int _bitCount(int mask) {
  var count = 0;
  for (var m = mask; m != 0; m >>= 1) {
    count += m & 1;
  }
  return count;
}

/// Not decided yet.
const int _unknown = 0;

/// A cell that holds track, or a side that is connected.
const int _yes = 1;

/// A cell that is empty, or a side that is not connected.
const int _no = 2;

/// What never changes while solving one set of clues: the grid's neighbour
/// table, the counts, and scratch space the passes reuse so they allocate
/// nothing. The scratch is shared by every [_State] of one solve, which is safe
/// because a solve is single-threaded and no pass is re-entered while another
/// holds it.
class _Grid {
  _Grid(TracksClues clues)
    : side = clues.spec.side,
      n = clues.spec.cells,
      rowCounts = clues.rowCounts,
      columnCounts = clues.columnCounts,
      start = clues.startCell,
      goal = clues.goalCell,
      neighbour = Int32List(clues.spec.cells * 4),
      parent = Int32List(clues.spec.cells),
      queue = Int32List(clues.spec.cells),
      seen = Uint8List(clues.spec.cells) {
    // Side k is the bit 1 << k: north, east, south, west, the order of
    // [TrackSide.all], so a mask and a side index convert by shifting.
    for (var i = 0; i < n; i++) {
      final row = i ~/ side;
      final column = i % side;
      neighbour[i * 4] = row > 0 ? i - side : -1;
      neighbour[i * 4 + 1] = column < side - 1 ? i + 1 : -1;
      neighbour[i * 4 + 2] = row < side - 1 ? i + side : -1;
      neighbour[i * 4 + 3] = column > 0 ? i - 1 : -1;
    }
  }

  final int side;
  final int n;
  final List<int> rowCounts;
  final List<int> columnCounts;
  final int start;
  final int goal;

  /// Per cell and side, the cell on the other side of it, or -1 off the grid.
  final Int32List neighbour;

  final Int32List parent;
  final Int32List queue;
  final Uint8List seen;
}

/// What deduction knows so far: per cell unknown, track or empty, and per cell
/// side unknown, connected or not.
///
/// Both live in one flat byte list so a hypothesis is a single copy: the first
/// [_Grid.n] bytes are the cells, then four bytes per cell for its sides.
/// A side is stored on both cells that share it and the two are only ever
/// written together ([setSide]), which is what keeps them reciprocal. A side
/// facing off the grid has no neighbour and is stored once; it is off except at
/// the two ports.
class _State {
  _State(this.grid) : data = Uint8List(grid.n * 5);

  _State._copy(_State other)
    : grid = other.grid,
      data = Uint8List.fromList(other.data);

  /// Ports, borders and fixed cells laid, in that order: the ports are set
  /// after the borders so that closing every outward side does not reach them.
  factory _State.initial(_Grid grid, TracksClues clues) {
    final state = _State(grid);
    for (var i = 0; i < grid.n; i++) {
      for (var k = 0; k < 4; k++) {
        if (grid.neighbour[i * 4 + k] >= 0) continue;
        final isPort =
            (i == grid.start && k == 3) || (i == grid.goal && k == 2);
        if (!isPort) state.setSide(i, k, _no);
      }
    }
    state.setSide(grid.start, 3, _yes);
    state.setSide(grid.goal, 2, _yes);
    for (var i = 0; i < grid.n; i++) {
      final mask = clues.fixed[i];
      if (mask == 0) continue;
      state.setCell(i, _yes);
      for (var k = 0; k < 4; k++) {
        state.setSide(i, k, mask & (1 << k) != 0 ? _yes : _no);
      }
    }
    return state;
  }

  final _Grid grid;
  final Uint8List data;

  /// Cells are `data[0..n)`.
  Uint8List get cells => data;

  /// Set when a rule found the state impossible. Everything after that is
  /// ignored, and a hypothesis that dies is what lookahead is looking for.
  bool dead = false;

  /// Set when the [probe] asked to stop.
  bool stopped = false;

  /// Bumped on every write, so a pass can tell whether it did anything.
  int changes = 0;

  /// The highest tier the deduction has reached, 1 to 3.
  int tier = 1;

  /// Called after each rule applies, for `nextTracksStep`; returns true to
  /// stop. Null on every hypothesis.
  bool Function(_State)? probe;
  int _probed = 0;

  int sideAt(int cell, int k) => data[grid.n + cell * 4 + k];

  /// Whether the pass should stop: dead, or the probe has what it wanted.
  bool tick() {
    if (dead || stopped) return true;
    final p = probe;
    if (p != null && changes != _probed) {
      _probed = changes;
      if (p(this)) {
        stopped = true;
        return true;
      }
    }
    return false;
  }

  void setCell(int i, int value) {
    final current = data[i];
    if (current == value) return;
    if (current != _unknown) {
      dead = true;
      return;
    }
    data[i] = value;
    changes++;
  }

  /// Decides side [k] of cell [i], and the neighbour's matching side. A side
  /// that is on makes both cells track.
  void setSide(int i, int k, int value) {
    final n = grid.n;
    final current = data[n + i * 4 + k];
    if (current == value) return;
    if (current != _unknown) {
      dead = true;
      return;
    }
    data[n + i * 4 + k] = value;
    changes++;
    final j = grid.neighbour[i * 4 + k];
    if (j >= 0) data[n + j * 4 + (k ^ 2)] = value;
    if (value == _yes) {
      setCell(i, _yes);
      if (j >= 0) setCell(j, _yes);
    }
  }

  /// The connection bits of cell [i] proven so far.
  int maskOf(int i) {
    var mask = 0;
    final base = grid.n + i * 4;
    for (var k = 0; k < 4; k++) {
      if (data[base + k] == _yes) mask |= 1 << k;
    }
    return mask;
  }

  List<int> masks() => [for (var i = 0; i < grid.n; i++) maskOf(i)];

  /// Whether nothing is left unknown, border sides included.
  bool get isDecided {
    for (var i = 0; i < data.length; i++) {
      if (data[i] == _unknown) return false;
    }
    return true;
  }

  /// A decided board checked against the rules from scratch: two connections
  /// on every track cell and none on an empty one, counts met, and one path
  /// from the start port to the goal port that visits every track cell.
  bool get isSolution {
    final n = grid.n;
    var tracks = 0;
    for (var i = 0; i < n; i++) {
      final mask = maskOf(i);
      if (data[i] == _yes) {
        if (_bitCount(mask) != 2) return false;
        tracks++;
      } else if (mask != 0) {
        return false;
      }
    }
    for (var r = 0; r < grid.side; r++) {
      var count = 0;
      for (var c = 0; c < grid.side; c++) {
        if (data[r * grid.side + c] == _yes) count++;
      }
      if (count != grid.rowCounts[r]) return false;
    }
    for (var c = 0; c < grid.side; c++) {
      var count = 0;
      for (var r = 0; r < grid.side; r++) {
        if (data[r * grid.side + c] == _yes) count++;
      }
      if (count != grid.columnCounts[c]) return false;
    }
    if (sideAt(grid.start, 3) != _yes || sideAt(grid.goal, 2) != _yes) {
      return false;
    }
    var cell = grid.start;
    var entered = 3;
    for (var visited = 1; visited <= n; visited++) {
      var leave = -1;
      for (var k = 0; k < 4; k++) {
        if (k != entered && sideAt(cell, k) == _yes) leave = k;
      }
      if (leave < 0) return false;
      final next = grid.neighbour[cell * 4 + leave];
      if (next < 0) return cell == grid.goal && visited == tracks;
      cell = next;
      entered = leave ^ 2;
    }
    return false;
  }

  /// Runs the rules up to [maxTier], following the tier order of
  /// `PLAN-phase-9-tracks.md` §4.5. Leaves [tier] at the highest tier used.
  void deduce(int maxTier) {
    while (true) {
      rulesT1();
      if (tick() || isDecided) return;
      if (maxTier >= 2) {
        if (tier < 2) tier = 2;
        final before = changes;
        rulesT2();
        if (tick()) return;
        if (changes != before) continue;
      }
      if (maxTier >= 3) {
        if (tier < 3) tier = 3;
        if (lookahead()) {
          if (tick()) return;
          continue;
        }
      }
      return;
    }
  }

  /// T1 and T2 to a joint fixpoint: what a hypothesis is followed through, and
  /// what the main state runs after each lookahead proof.
  void closure() {
    while (true) {
      rulesT1();
      if (tick()) return;
      final before = changes;
      rulesT2();
      if (tick() || changes == before) return;
    }
  }

  /// T1 to a fixpoint.
  void rulesT1() {
    while (true) {
      final before = changes;
      cellRules();
      if (tick()) return;
      countRules();
      if (tick() || changes == before) return;
    }
  }

  void cellRules() {
    final n = grid.n;
    for (var i = 0; i < n; i++) {
      final base = n + i * 4;
      final cell = data[i];
      if (cell == _no) {
        for (var k = 0; k < 4; k++) {
          // A connection into an empty cell is impossible; an unknown one is
          // closed, a connected one is the contradiction.
          if (data[base + k] != _no) setSide(i, k, _no);
        }
      } else {
        var on = 0;
        var off = 0;
        for (var k = 0; k < 4; k++) {
          final side = data[base + k];
          if (side == _yes) on++;
          if (side == _no) off++;
        }
        final open = 4 - off;
        if (cell == _yes) {
          if (on > 2 || open < 2) {
            dead = true;
          } else if (on == 2) {
            for (var k = 0; k < 4; k++) {
              if (data[base + k] == _unknown) setSide(i, k, _no);
            }
          } else if (open == 2) {
            for (var k = 0; k < 4; k++) {
              if (data[base + k] == _unknown) setSide(i, k, _yes);
            }
          }
        } else if (open < 2) {
          setCell(i, _no);
        }
      }
      if (tick()) return;
    }
  }

  void countRules() {
    final side = grid.side;
    for (var r = 0; r < side; r++) {
      lineRule(r * side, 1, grid.rowCounts[r]);
      if (tick()) return;
    }
    for (var c = 0; c < side; c++) {
      lineRule(c, side, grid.columnCounts[c]);
      if (tick()) return;
    }
  }

  /// One row or column: [first] is its first cell, [step] the distance to the
  /// next, [count] the clue.
  void lineRule(int first, int step, int count) {
    var track = 0;
    var unknown = 0;
    for (var m = 0, i = first; m < grid.side; m++, i += step) {
      if (data[i] == _yes) track++;
      if (data[i] == _unknown) unknown++;
    }
    if (track > count || track + unknown < count) {
      dead = true;
      return;
    }
    if (unknown == 0) return;
    final value = track == count
        ? _no
        : (track + unknown == count ? _yes : _unknown);
    if (value == _unknown) return;
    for (var m = 0, i = first; m < grid.side; m++, i += step) {
      if (data[i] == _unknown) setCell(i, value);
    }
  }

  /// T2: no early loop, then reach.
  void rulesT2() {
    final n = grid.n;
    final parent = grid.parent;
    for (var i = 0; i < n; i++) {
      parent[i] = i;
    }
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }

    // Fragments are the connected pieces of the connections already known. An
    // edge appears twice (once from each cell), so look east and south only.
    for (var i = 0; i < n; i++) {
      for (var k = 1; k <= 2; k++) {
        final j = grid.neighbour[i * 4 + k];
        // The goal port faces off the grid: it joins no cell.
        if (j < 0 || sideAt(i, k) != _yes) continue;
        final a = find(i);
        final b = find(j);
        if (a == b) {
          // Connections that close a loop: no board has them.
          dead = true;
          return;
        }
        parent[a] = b;
      }
    }
    for (var i = 0; i < n; i++) {
      for (var k = 1; k <= 2; k++) {
        final j = grid.neighbour[i * 4 + k];
        if (j < 0 || sideAt(i, k) != _unknown) continue;
        if (find(i) == find(j)) {
          // Joining a fragment to itself closes a loop. No exception for the
          // last connection: the ends leave through the ports, they do not
          // meet (§4.4).
          setSide(i, k, _no);
          if (tick()) return;
        }
      }
    }

    // Reach: everything on the path is joined to the start by connections
    // that are still possible.
    final seen = grid.seen;
    final queue = grid.queue;
    for (var i = 0; i < n; i++) {
      seen[i] = 0;
    }
    var head = 0;
    var tail = 0;
    queue[tail++] = grid.start;
    seen[grid.start] = 1;
    while (head < tail) {
      final i = queue[head++];
      for (var k = 0; k < 4; k++) {
        if (sideAt(i, k) == _no) continue;
        final j = grid.neighbour[i * 4 + k];
        if (j < 0 || seen[j] != 0 || data[j] == _no) continue;
        seen[j] = 1;
        queue[tail++] = j;
      }
    }
    for (var i = 0; i < n; i++) {
      if (seen[i] != 0 || data[i] == _no) continue;
      if (data[i] == _yes) {
        dead = true;
        return;
      }
      setCell(i, _no);
      if (tick()) return;
    }
  }

  /// T3: tries each undecided cell and each open side of a track cell both
  /// ways on a copy, and applies what a contradiction proves.
  ///
  /// Returns whether anything was proven. Without a probe it keeps scanning
  /// after a proof, which saves rescanning from the top for each one and finds
  /// the same fixpoint (the rules are monotone); with a probe it returns at
  /// the first so the caller can look at the board between proofs.
  bool lookahead() {
    final n = grid.n;
    var progress = false;
    for (var i = 0; i < n; i++) {
      if (data[i] == _unknown) {
        if (refutes(i, -1, _yes)) {
          setCell(i, _no);
        } else if (refutes(i, -1, _no)) {
          setCell(i, _yes);
        }
        if (data[i] != _unknown) {
          progress = true;
          if (afterProof()) return true;
        }
      }
      if (data[i] != _yes) continue;
      for (var k = 0; k < 4; k++) {
        if (sideAt(i, k) != _unknown) continue;
        final j = grid.neighbour[i * 4 + k];
        // An edge between two track cells is tried from the lower one only.
        if (j >= 0 && j < i && data[j] == _yes) continue;
        if (refutes(i, k, _yes)) {
          setSide(i, k, _no);
        } else if (refutes(i, k, _no)) {
          setSide(i, k, _yes);
        }
        if (sideAt(i, k) != _unknown) {
          progress = true;
          if (afterProof()) return true;
        }
      }
    }
    return progress;
  }

  /// After a proof: propagate it, and report whether the scan should end.
  bool afterProof() {
    if (tick()) return true;
    closure();
    return dead || stopped || probe != null;
  }

  /// Whether assuming [value] for cell [i] (or side [k] when not negative)
  /// leads T1 and T2 to a contradiction.
  bool refutes(int i, int k, int value) {
    final copy = _State._copy(this);
    if (k < 0) {
      copy.setCell(i, value);
    } else {
      copy.setSide(i, k, value);
    }
    copy.closure();
    return copy.dead;
  }
}
