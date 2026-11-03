// Helpers shared by the Tracks tests: drawing a board, building clues from a
// diagram, checking a finished board against the rules the long way, and
// listing what the counter finds.

import 'package:puzzle_engine/src/tracks/track_side.dart';
import 'package:puzzle_engine/src/tracks/tracks_clues.dart';
import 'package:puzzle_engine/src/tracks/tracks_counter.dart';
import 'package:puzzle_engine/src/tracks/tracks_spec.dart';

/// Reads a board drawn in the usual pipe-maze letters, one string per row:
/// `.` empty, `|` north-south, `-` east-west, `L` north-east, `F` east-south,
/// `7` south-west, `J` north-west.
List<int> board(List<String> rows) {
  const pieceOf = {'.': 0, '|': 5, '-': 10, 'L': 3, 'F': 6, '7': 12, 'J': 9};
  return [
    for (final row in rows)
      for (final glyph in row.split('')) pieceOf[glyph]!,
  ];
}

/// Clues for a board of [side] with the given fixed cells, spelled as
/// `index: piece` pairs so a fixture reads like the diagram it comes from.
TracksClues cluesFor(
  int side,
  int startRow,
  int goalColumn,
  List<int> rows,
  List<int> columns, [
  Map<int, int> fixed = const {},
]) {
  final cells = List<int>.filled(side * side, 0);
  for (final index in fixed.keys) {
    cells[index] = fixed[index]!;
  }
  return TracksClues(
    spec: TracksSpec(side),
    startRow: startRow,
    goalColumn: goalColumn,
    rowCounts: rows,
    columnCounts: columns,
    fixed: cells,
  );
}

/// The rules of `PLAN-phase-9-tracks.md` §4.3, checked on a finished board
/// the long way, so a test can say exactly which rule a board breaks. Returns
/// the names of the rules that fail; empty means a solution.
///
/// Written separately from the counter's incremental checks on purpose: a
/// board both agree on is checked by two different readings of the rules.
List<String> brokenRules(TracksClues clues, List<int> cells) {
  final spec = clues.spec;
  final side = spec.side;
  final broken = <String>[];

  bool has(int index, int bit) => cells[index] & bit != 0;

  if (cells.any((c) => c != 0 && !TrackSide.isPiece(c))) broken.add('pieces');

  var connectionsOk = true;
  for (var r = 0; r < side; r++) {
    for (var c = 0; c < side; c++) {
      final i = spec.indexAt(r, c);
      for (final bit in TrackSide.all) {
        if (!has(i, bit)) continue;
        final dr = bit == TrackSide.north
            ? -1
            : (bit == TrackSide.south ? 1 : 0);
        final dc = bit == TrackSide.west ? -1 : (bit == TrackSide.east ? 1 : 0);
        final nr = r + dr;
        final nc = c + dc;
        final inside = nr >= 0 && nr < side && nc >= 0 && nc < side;
        if (inside) {
          if (!has(spec.indexAt(nr, nc), TrackSide.opposite(bit))) {
            connectionsOk = false;
          }
        } else {
          final isStartPort = i == clues.startCell && bit == TrackSide.west;
          final isGoalPort = i == clues.goalCell && bit == TrackSide.south;
          if (!isStartPort && !isGoalPort) connectionsOk = false;
        }
      }
    }
  }
  if (!connectionsOk) broken.add('connections');

  if (!has(clues.startCell, TrackSide.west) ||
      !has(clues.goalCell, TrackSide.south)) {
    broken.add('ports');
  }

  for (var i = 0; i < cells.length; i++) {
    if (clues.fixed[i] != 0 && cells[i] != clues.fixed[i]) {
      broken.add('fixed');
      break;
    }
  }

  var countsOk = true;
  for (var r = 0; r < side; r++) {
    var n = 0;
    for (var c = 0; c < side; c++) {
      if (cells[spec.indexAt(r, c)] != 0) n++;
    }
    if (n != clues.rowCounts[r]) countsOk = false;
  }
  for (var c = 0; c < side; c++) {
    var n = 0;
    for (var r = 0; r < side; r++) {
      if (cells[spec.indexAt(r, c)] != 0) n++;
    }
    if (n != clues.columnCounts[c]) countsOk = false;
  }
  if (!countsOk) broken.add('counts');

  // No loop: walking from the start along the connections must reach every
  // track cell, because anything left over is a separate component.
  if (connectionsOk && TrackSide.isPiece(cells[clues.startCell])) {
    var walked = 0;
    var index = clues.startCell;
    var cameFrom = TrackSide.west;
    while (walked <= cells.length) {
      walked++;
      final leave = cells[index] & ~cameFrom;
      if (leave == TrackSide.south && index == clues.goalCell) break;
      final r =
          spec.rowOf(index) +
          (leave == TrackSide.north ? -1 : (leave == TrackSide.south ? 1 : 0));
      final c =
          spec.columnOf(index) +
          (leave == TrackSide.west ? -1 : (leave == TrackSide.east ? 1 : 0));
      index = spec.indexAt(r, c);
      cameFrom = TrackSide.opposite(leave);
    }
    if (walked != cells.where((c) => c != 0).length) broken.add('loop');
  }
  return broken;
}

/// All solutions the counter reports for [clues], up to [limit].
List<List<int>> solutionsOf(TracksClues clues, {int limit = 2}) {
  final found = <List<int>>[];
  countTracksSolutions(clues, limit: limit, onSolution: found.add);
  return found;
}
