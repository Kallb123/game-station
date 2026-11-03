// Shared helpers for the Tracks session tests: real generated puzzles, and the
// searches that find the ones with a property a test needs.
//
// A made-up grid would let a test pass against a board no generator would
// produce, so every puzzle here comes from `generateTracks`. Where a case needs
// a particular shape (a start cell that is not fixed, a cell next to a fixed
// piece), the helper scans consecutive indices and the caller asserts it found
// one, rather than the test hard-coding an index whose reason nobody remembers.
// The scan is deterministic: the same code finds the same puzzle every run.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/tracks/model/tracks_session.dart';

/// A stroke position: a cell, or a port just outside the grid.
typedef Position = (int row, int column);

final Map<String, TracksPuzzle> _generated = {};

/// The puzzle for [id], generated once per test run.
TracksPuzzle puzzleFor(String id) =>
    _generated.putIfAbsent(id, () => generateTracks(TracksPuzzleId.parse(id)));

/// A session over [puzzle] with nothing played.
TracksSession startSession(
  TracksPuzzle puzzle, {
  MistakeFeedback feedback = MistakeFeedback.immediate,
}) => TracksSession.start(
  id: puzzle.id,
  clues: puzzle.clues,
  solution: puzzle.solution,
  mistakeFeedback: feedback,
);

/// A session resumed from [saved] over [puzzle].
TracksSession resumeSession(
  TracksPuzzle puzzle,
  TracksInProgress saved, {
  MistakeFeedback feedback = MistakeFeedback.immediate,
}) => TracksSession.resume(
  id: puzzle.id,
  clues: puzzle.clues,
  solution: puzzle.solution,
  saved: saved,
  mistakeFeedback: feedback,
);

/// The (row, column) of [cell].
Position positionOf(TracksSpec spec, int cell) =>
    (spec.rowOf(cell), spec.columnOf(cell));

/// What a fresh board holds, worked out here rather than read from the session:
/// the fixed pieces exactly. A fixed piece's bit toward a free cell stays
/// unanswered, because seeding the answer completed cells the child never
/// touched and opened some puzzles already solved.
List<int> initialBoard(TracksClues clues) => [...clues.fixed];

/// The cell next to [cell] on [side], or null at the edge of the grid.
int? neighbourOf(TracksSpec spec, int cell, int side) {
  final row =
      spec.rowOf(cell) +
      (side == TrackSide.south ? 1 : 0) -
      (side == TrackSide.north ? 1 : 0);
  final column =
      spec.columnOf(cell) +
      (side == TrackSide.east ? 1 : 0) -
      (side == TrackSide.west ? 1 : 0);
  if (row < 0 || row >= spec.side || column < 0 || column >= spec.side) {
    return null;
  }
  return spec.indexAt(row, column);
}

/// Every in-grid neighbour of [cell], with the side of [cell] it lies on.
List<({int side, int cell})> neighboursOf(TracksSpec spec, int cell) => [
  for (final side in TrackSide.all)
    if (neighbourOf(spec, cell, side) case final neighbour?)
      (side: side, cell: neighbour),
];

/// The solution's cells in path order, from the start cell to the goal cell.
List<int> solutionPath(TracksPuzzle puzzle) {
  final spec = puzzle.id.spec;
  final path = <int>[];
  var cell = puzzle.clues.startCell;
  var cameIn = TrackSide.west;
  while (true) {
    path.add(cell);
    final out = puzzle.solution[cell] & ~cameIn;
    if (cell == puzzle.clues.goalCell && out == TrackSide.south) return path;
    cell = neighbourOf(spec, cell, out)!;
    cameIn = TrackSide.opposite(out);
  }
}

/// The positions of one stroke that lays the whole solution: the start port,
/// every solution cell in order, the goal port.
List<Position> solutionStroke(TracksPuzzle puzzle) {
  final spec = puzzle.id.spec;
  return [
    (puzzle.clues.startRow, -1),
    for (final cell in solutionPath(puzzle)) positionOf(spec, cell),
    (spec.side, puzzle.clues.goalColumn),
  ];
}

/// Plays [positions] as one stroke on [session], and ends it.
void stroke(TracksSession session, List<Position> positions) {
  session.beginStroke(positions.first.$1, positions.first.$2);
  for (final position in positions.skip(1)) {
    session.strokeTo(position.$1, position.$2);
  }
  session.endStroke();
}

/// The board and marks of [session], copied, so a later change cannot reach it.
typedef Snapshot = ({List<int> cells, List<bool> marks});

Snapshot snapshotOf(TracksSession session) => (
  cells: [...session.cells],
  marks: [for (var i = 0; i < session.spec.cells; i++) session.isMarked(i)],
);

/// Expects [session] to hold exactly [snapshot].
void expectBoard(TracksSession session, Snapshot snapshot) {
  final now = snapshotOf(session);
  expect(now.cells, snapshot.cells);
  expect(now.marks, snapshot.marks);
}

/// The first puzzle, scanning consecutive indices of each of [combos] in turn,
/// for which [probe] returns a value, with that value.
///
/// Fails the calling test when none does, so a fixture that stops existing
/// (a generator change) is a loud failure and not a test that quietly skips
/// its own subject.
({TracksPuzzle puzzle, T found}) findPuzzle<T extends Object>(
  T? Function(TracksPuzzle puzzle) probe, {
  List<(TracksSpec, Difficulty)> combos = const [
    (TracksSpec.s5x5, Difficulty.easy),
  ],
  int limit = 300,
}) {
  for (final (spec, difficulty) in combos) {
    for (var index = 0; index < limit; index++) {
      final puzzle = puzzleFor(
        'tracks:${spec.label}:${difficulty.name}:$index',
      );
      final found = probe(puzzle);
      if (found != null) return (puzzle: puzzle, found: found);
    }
  }
  fail('no puzzle in the first $limit of $combos has the property searched');
}

/// Every offered size and difficulty, the combinations `PLAN-phase-9-tracks.md`
/// §4.1 ships.
const List<(TracksSpec, Difficulty)> offeredCombos = [
  (TracksSpec.s5x5, Difficulty.easy),
  (TracksSpec.s5x5, Difficulty.medium),
  (TracksSpec.s7x7, Difficulty.easy),
  (TracksSpec.s7x7, Difficulty.medium),
  (TracksSpec.s7x7, Difficulty.hard),
  (TracksSpec.s9x9, Difficulty.easy),
  (TracksSpec.s9x9, Difficulty.medium),
  (TracksSpec.s9x9, Difficulty.hard),
];
