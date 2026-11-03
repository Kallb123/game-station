// The solved route as a line every skin shares (`PLAN-phase-9-tracks.md`
// §4.8).
//
// One geometry, many skins: the train, the water and the snail all follow the
// same centre line at a speed that is only `cellsPerSecond`, so no skin can
// make its journey longer or shorter than another's, and the journey can be
// tested as numbers (which cell at t = 0.5, how long the line is) with no
// pixels involved.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;
import 'package:puzzle_engine/puzzle_engine.dart';

import 'track_skin.dart' show BoardLayout;

/// The track from the start port to the goal port, as a centre line in grid
/// units with quarter-circle corners, parametrised by arc length.
///
/// Grid units: x across columns, y down rows, cell (0, 0) spanning (0, 0) to
/// (1, 1). The route begins at the centre of the start port square
/// `(startRow, -1)` and ends at the centre of the goal port square
/// `(side, goalColumn)`. Within a cell the line runs from the midpoint of the
/// side it enters by to the midpoint of the side it leaves by: straight
/// (length 1) or a quarter circle of radius 0.5 centred on the cell corner the
/// two sides share (length pi/4). Each port contributes a straight half cell
/// (length 0.5) between its centre and the grid edge.
@immutable
class TrackGeometry {
  TrackGeometry._(this.route, List<_Segment> segments)
    : _segments = List.unmodifiable(segments),
      length = segments.last.start + segments.last.length;

  /// The route along [cells] (one connection mask per cell, row-major), or null
  /// unless the track runs unbroken from the start port to the goal port:
  /// every cell on the way holds exactly two bits, one of them the side the
  /// walk came in by, each step's neighbour returns the bit, and the goal cell
  /// leaves south. The step budget is the cell count, so a loop ends the walk.
  ///
  /// Joined is not solved — counts are not checked — so the caller decides
  /// whether a journey may run.
  static TrackGeometry? trace(TracksClues clues, List<int> cells) {
    final spec = clues.spec;
    final side = spec.side;
    if (cells.length != spec.cells) return null;

    final squares = <(int, int)>[(clues.startRow, -1)];
    final lines = <_Segment>[];
    var distance = 0.0;
    void add(_Segment Function(double start) make) {
      final segment = make(distance);
      lines.add(segment);
      distance += segment.length;
    }

    add(
      (start) => _Segment.line(
        start,
        Offset(-0.5, clues.startRow + 0.5),
        Offset(0, clues.startRow + 0.5),
      ),
    );

    var cell = clues.startCell;
    var cameIn = TrackSide.west;
    for (var step = 0; step < spec.cells; step++) {
      final mask = cells[cell];
      final out = mask & ~cameIn;
      // Two bits, one of them the way in: what is left is exactly one bit.
      if (mask & cameIn == 0 || out == 0 || out & (out - 1) != 0) return null;

      final row = spec.rowOf(cell);
      final column = spec.columnOf(cell);
      squares.add((row, column));
      add((start) => _Segment.cell(start, row, column, cameIn, out));

      if (cell == clues.goalCell && out == TrackSide.south) {
        squares.add((side, clues.goalColumn));
        add(
          (start) => _Segment.line(
            start,
            Offset(clues.goalColumn + 0.5, side.toDouble()),
            Offset(clues.goalColumn + 0.5, side + 0.5),
          ),
        );
        return TrackGeometry._(List.unmodifiable(squares), lines);
      }

      final nextRow =
          row +
          (out == TrackSide.south ? 1 : 0) -
          (out == TrackSide.north ? 1 : 0);
      final nextColumn =
          column +
          (out == TrackSide.east ? 1 : 0) -
          (out == TrackSide.west ? 1 : 0);
      if (nextRow < 0 ||
          nextRow >= side ||
          nextColumn < 0 ||
          nextColumn >= side) {
        return null;
      }
      final next = spec.indexAt(nextRow, nextColumn);
      cameIn = TrackSide.opposite(out);
      if (cells[next] & cameIn == 0) return null;
      cell = next;
    }
    return null;
  }

  /// The squares the route passes through, ports included: the start port
  /// first, the goal port last.
  final List<(int row, int column)> route;

  /// One entry per square in [route], in order.
  final List<_Segment> _segments;

  /// Total arc length in grid units.
  final double length;

  /// The segment holding distance [d], and [d] measured from its start. A
  /// distance exactly on a boundary belongs to the later segment; the last
  /// segment takes everything up to and including the end.
  (int, double) _locate(double t) {
    final d = t.clamp(0.0, 1.0) * length;
    var index = _segments.length - 1;
    while (index > 0 && _segments[index].start > d) {
      index--;
    }
    return (index, d - _segments[index].start);
  }

  /// The point at fraction [t] of [length], in grid units. [t] is clamped to
  /// 0..1.
  Offset pointAt(double t) {
    final (index, local) = _locate(t);
    return _segments[index].pointAt(local);
  }

  /// The unit tangent at [t], pointing the way the traveller moves.
  Offset directionAt(double t) {
    final (index, local) = _locate(t);
    return _segments[index].directionAt(local);
  }

  /// The square the point at [t] lies in. A distance exactly on the boundary
  /// between two squares belongs to the later one, except t = 1, which is the
  /// goal port.
  (int row, int column) positionAt(double t) => route[_locate(t).$1];

  /// The route from t = 0 to [upTo], in canvas coordinates under [layout].
  Path toPath(BoardLayout layout, {double upTo = 1}) {
    final reach = upTo.clamp(0.0, 1.0) * length;
    final path = Path();
    path.moveTo(
      layout.toCanvas(_segments.first.pointAt(0)).dx,
      layout.toCanvas(_segments.first.pointAt(0)).dy,
    );
    final radius = Radius.circular(layout.cellSize / 2);
    for (final segment in _segments) {
      final covered = math.min(segment.length, reach - segment.start);
      if (covered <= 1e-12) break;
      final end = layout.toCanvas(segment.pointAt(covered));
      if (segment.clockwise == null) {
        path.lineTo(end.dx, end.dy);
      } else {
        path.arcToPoint(end, radius: radius, clockwise: segment.clockwise!);
      }
    }
    return path;
  }
}

/// One stretch of the centre line: a straight, or a quarter circle.
@immutable
class _Segment {
  const _Segment._(
    this.start,
    this.length,
    this._from,
    this._to,
    this._centre,
    this._turn,
  );

  factory _Segment.line(double start, Offset from, Offset to) =>
      _Segment._(start, (to - from).distance, from, to, null, 0);

  /// The segment through the cell at ([row], [column]) from the midpoint of
  /// side [entry] to the midpoint of side [exit].
  factory _Segment.cell(
    double start,
    int row,
    int column,
    int entry,
    int exit,
  ) {
    final from = _midpoint(row, column, entry);
    final to = _midpoint(row, column, exit);
    if (entry == TrackSide.opposite(exit)) {
      return _Segment.line(start, from, to);
    }
    // The two sides meet at one corner: the x of the east/west side and the y
    // of the north/south side.
    final horizontal = (entry == TrackSide.east || entry == TrackSide.west)
        ? entry
        : exit;
    final vertical = horizontal == entry ? exit : entry;
    final centre = Offset(
      column + (horizontal == TrackSide.east ? 1.0 : 0.0),
      row + (vertical == TrackSide.south ? 1.0 : 0.0),
    );
    final a = from - centre;
    final b = to - centre;
    // Positive cross product turns toward +y, which is clockwise on screen.
    final turn = (a.dx * b.dy - a.dy * b.dx) > 0 ? 1.0 : -1.0;
    return _Segment._(start, math.pi / 4, from, to, centre, turn);
  }

  static Offset _midpoint(int row, int column, int side) => switch (side) {
    TrackSide.north => Offset(column + 0.5, row.toDouble()),
    TrackSide.south => Offset(column + 0.5, row + 1.0),
    TrackSide.east => Offset(column + 1.0, row + 0.5),
    _ => Offset(column.toDouble(), row + 0.5),
  };

  /// Distance along the route at which this segment begins.
  final double start;

  /// Arc length: 1 or 0.5 for a line, pi/4 for a quarter circle.
  final double length;

  final Offset _from;
  final Offset _to;

  /// The circle's centre, or null for a line.
  final Offset? _centre;

  /// +1 clockwise on screen, -1 anticlockwise, for an arc.
  final double _turn;

  /// Null for a line, else whether the arc runs clockwise on screen.
  bool? get clockwise => _centre == null ? null : _turn > 0;

  /// The point [local] along the segment.
  Offset pointAt(double local) {
    final centre = _centre;
    if (centre == null) {
      return _from + (_to - _from) * (local / length);
    }
    final angle = _angleOf(_from - centre) + _turn * local / 0.5;
    return centre + Offset(math.cos(angle), math.sin(angle)) * 0.5;
  }

  /// The unit tangent [local] along the segment.
  Offset directionAt(double local) {
    final centre = _centre;
    if (centre == null) return (_to - _from) / length;
    final angle = _angleOf(_from - centre) + _turn * local / 0.5;
    return Offset(-math.sin(angle), math.cos(angle)) * _turn;
  }

  static double _angleOf(Offset v) => math.atan2(v.dy, v.dx);
}
