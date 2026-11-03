// Path helpers shared by the train and water skins (`PLAN-phase-9-tracks.md`
// §4.8).
//
// Both skins draw a piece as a centre line through one cell, ending at the
// midpoint of each side it joins, with a quarter circle for a corner. Keeping
// that geometry in one place means a rail and a pipe turn identically, and a
// new skin starts from these rather than from trigonometry.

import 'dart:math' as math;
import 'dart:ui';

import 'package:puzzle_engine/puzzle_engine.dart' show TrackSide;

/// The midpoint of [side] of [cell].
Offset sideMidpoint(Rect cell, int side) => switch (side) {
  TrackSide.north => Offset(cell.center.dx, cell.top),
  TrackSide.east => Offset(cell.right, cell.center.dy),
  TrackSide.south => Offset(cell.center.dx, cell.bottom),
  TrackSide.west => Offset(cell.left, cell.center.dy),
  _ => throw ArgumentError.value(side, 'side', 'not a single side bit'),
};

/// The sides set in [mask], in `TrackSide.all` order.
List<int> sidesOf(int mask) => [
  for (final side in TrackSide.all)
    if (mask & side != 0) side,
];

/// The centre line of a piece: a straight line or a quarter circle of radius
/// half a cell between the midpoints of the two sides in [mask].
///
/// A one-bit [mask] is a stub from the centre of [cell] towards that side, cut
/// short at [stubReach] of the way (1 reaches the edge).
Path centreline(Rect cell, int mask, {double stubReach = 1}) {
  final sides = sidesOf(mask);
  final path = Path();
  if (sides.isEmpty) return path;
  if (sides.length == 1) {
    final end = Offset.lerp(
      cell.center,
      sideMidpoint(cell, sides[0]),
      stubReach,
    )!;
    return path
      ..moveTo(cell.center.dx, cell.center.dy)
      ..lineTo(end.dx, end.dy);
  }
  final from = sideMidpoint(cell, sides[0]);
  final to = sideMidpoint(cell, sides[1]);
  path.moveTo(from.dx, from.dy);
  final straight =
      mask == (TrackSide.north | TrackSide.south) ||
      mask == (TrackSide.east | TrackSide.west);
  if (straight) return path..lineTo(to.dx, to.dy);

  // The arc is centred on the cell corner the two sides share. In canvas
  // coordinates (y down) a positive cross product turns clockwise.
  final corner = Offset(
    mask & TrackSide.west != 0 ? cell.left : cell.right,
    mask & TrackSide.north != 0 ? cell.top : cell.bottom,
  );
  final a = from - corner;
  final b = to - corner;
  return path..arcToPoint(
    to,
    radius: Radius.circular(cell.width / 2),
    clockwise: a.dx * b.dy - a.dy * b.dx > 0,
  );
}

/// [count] evenly spaced points along [path], each with the unit tangent
/// there. They sit at the middle of equal shares of the length, so two
/// neighbouring cells that each take three share the same spacing across their
/// common edge.
List<({Offset point, Offset tangent})> samplesAlong(Path path, int count) {
  final metrics = path.computeMetrics().toList();
  if (metrics.isEmpty) return const [];
  final metric = metrics.first;
  return [
    for (var i = 0; i < count; i++)
      if (metric.getTangentForOffset(metric.length * (i + 0.5) / count)
          case final tangent?)
        (point: tangent.position, tangent: tangent.vector),
  ];
}

/// [path] moved [offset] along its left-hand normal, as a polyline of [steps]
/// segments. Used for the two rails of a track, which a corner's arc turns
/// into concentric arcs.
Path offsetPath(Path path, double offset, {int steps = 12}) {
  final metrics = path.computeMetrics().toList();
  final result = Path();
  if (metrics.isEmpty) return result;
  final metric = metrics.first;
  for (var i = 0; i <= steps; i++) {
    final tangent = metric.getTangentForOffset(metric.length * i / steps);
    if (tangent == null) continue;
    final normal = Offset(-tangent.vector.dy, tangent.vector.dx);
    final point = tangent.position + normal * offset;
    if (i == 0) {
      result.moveTo(point.dx, point.dy);
    } else {
      result.lineTo(point.dx, point.dy);
    }
  }
  return result;
}

/// [path] cut into dashes of [dash] with [gap] between, for the wrong style's
/// broken look.
Path dashed(Path path, double dash, double gap) {
  final result = Path();
  for (final metric in path.computeMetrics()) {
    for (var at = 0.0; at < metric.length; at += dash + gap) {
      result.addPath(
        metric.extractPath(at, math.min(at + dash, metric.length)),
        Offset.zero,
      );
    }
  }
  return result;
}

/// A repeatable pseudo-random number in 0..1 from a cell's position, so a
/// texture varies from cell to cell without any randomness: the same board
/// looks the same on every frame and every run.
double cellNoise(int row, int column, int salt) {
  final mixed =
      (row * 73 + column * 151 + row * column * 29 + salt * 389).abs() % 997;
  return (mixed * 37 % 101) / 100;
}
