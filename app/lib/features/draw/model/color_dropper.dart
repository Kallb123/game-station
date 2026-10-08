// The colour dropper's arithmetic: which palette colour is under a point.
//
// A drawing is data, not pixels (`PLAN-phase-8.md` §4.1), so the answer is
// computed from the strokes rather than read back off the screen. A rendered
// read-back would also return the anti-aliased fringe of a stroke's edge and
// the photo's pixels, neither of which is a palette index, and it would need
// an engine to test; this needs `dart:ui`'s [Offset] and [Color] and nothing
// else, so its tests are plain `test()` calls, like `stroke.dart`'s.
//
// Three layers answer, topmost first (`PLAN-phase-8.md` §4.8): the strokes,
// then the backdrop photo if there is one, then the bare paper. This file
// answers the first two; the sheet screen (`draw_sheet_screen.dart`) owns
// the decoded photo and the theme's paper colour and chains the three.

import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;

import 'palette.dart';
import 'stroke.dart';

/// How many straight pieces each quadratic segment of a stroke is flattened
/// into for the distance test. Eight keeps the flattened curve well inside a
/// tenth of a sheet unit of the real one at the 2-unit sampling distance the
/// sheet draws at (`draw_sheet_screen.dart`'s `drawSampleDistance`), which is
/// far below the 4-unit radius of the thinnest pencil.
const int _curveSteps = 8;

abstract final class ColorDropper {
  /// The palette index of the ink showing at [point], in sheet coordinates,
  /// or null when no ink does.
  ///
  /// The topmost — last drawn — stroke that covers [point] decides. If that
  /// stroke is an eraser the answer is null even where a pencil stroke lies
  /// beneath it: the eraser cleared that ink, so what shows is whatever is
  /// under all the ink, and the caller asks the backdrop and then the paper.
  /// An eraser that does not cover [point] is not consulted, which is why
  /// this walks from the top and stops at the first stroke that does.
  static int? inkAt(List<Stroke> strokes, Offset point) {
    for (var i = strokes.length - 1; i >= 0; i--) {
      final stroke = strokes[i];
      if (!covers(stroke, point)) continue;
      return stroke.isEraser ? null : stroke.colorIndex;
    }
    return null;
  }

  /// Whether [stroke], as `paintStroke` (`drawing_painter.dart`) renders it,
  /// paints [point].
  ///
  /// The rendered shape is the stroke's path stroked at its pencil width with
  /// round caps and joins, which is every point within half that width of
  /// the path. The path is [paintStroke]'s own: a quadratic segment per
  /// sample with the sample as control point and the midpoints as ends, then
  /// a straight line to the last sample — not the polyline through the
  /// samples, which cuts a corner the curve does not. A one-point stroke is a
  /// filled dot of the same radius. The edge is inclusive.
  static bool covers(Stroke stroke, Offset point) {
    final points = stroke.points;
    if (points.isEmpty) return false;
    final radius = DrawPencils.widthAt(stroke.sizeIndex) / 2;
    if (points.length == 1) {
      return (point - points.first).distanceSquared <= radius * radius;
    }

    var start = points.first;
    for (var i = 0; i < points.length - 1; i++) {
      final control = points[i];
      final end = Offset.lerp(points[i], points[i + 1], 0.5)!;
      if (_nearQuadratic(start, control, end, point, radius)) return true;
      start = end;
    }
    return _distanceSquaredToSegment(start, points.last, point) <=
        radius * radius;
  }

  /// The photo's colour at [point], or null when [point] is outside the
  /// photo.
  ///
  /// [rgba] is the photo's straight (not premultiplied) 8-bit pixels,
  /// [pixelWidth] x [pixelHeight] of them, as `ui.ImageByteFormat.rawRgba`
  /// returns. [sheetSize] is the size the photo occupies on the sheet, which
  /// need not match the pixel size, and it sits centred and unscaled-by-
  /// aspect exactly where `drawBackdropImage` (`drawing_painter.dart`) puts
  /// it. The returned colour keeps the photo's alpha, so a caller can blend
  /// a transparent pixel over the paper it really shows on.
  static Color? backdropColorAt({
    required ByteData rgba,
    required int pixelWidth,
    required int pixelHeight,
    required Size sheetSize,
    required Offset point,
  }) {
    final left = (sheetWidth - sheetSize.width) / 2;
    final top = (sheetHeight - sheetSize.height) / 2;
    final dx = point.dx - left;
    final dy = point.dy - top;
    if (dx < 0 || dy < 0 || dx > sheetSize.width || dy > sheetSize.height) {
      return null;
    }
    // Clamped because the photo's right and bottom edges are inside it (the
    // inclusive test above) and would otherwise index one pixel past the end.
    final x = (dx / sheetSize.width * pixelWidth).floor().clamp(
      0,
      pixelWidth - 1,
    );
    final y = (dy / sheetSize.height * pixelHeight).floor().clamp(
      0,
      pixelHeight - 1,
    );
    final offset = (y * pixelWidth + x) * 4;
    return Color.fromARGB(
      rgba.getUint8(offset + 3),
      rgba.getUint8(offset),
      rgba.getUint8(offset + 1),
      rgba.getUint8(offset + 2),
    );
  }
}

bool _nearQuadratic(
  Offset start,
  Offset control,
  Offset end,
  Offset point,
  double radius,
) {
  // A quadratic curve lies inside the hull of its three points, so a point
  // further than [radius] outside their bounding box cannot be near it. Most
  // segments of most strokes are rejected here, which is what keeps a tap
  // cheap over a drawing of thousands.
  final minX = _min3(start.dx, control.dx, end.dx) - radius;
  final maxX = _max3(start.dx, control.dx, end.dx) + radius;
  final minY = _min3(start.dy, control.dy, end.dy) - radius;
  final maxY = _max3(start.dy, control.dy, end.dy) + radius;
  if (point.dx < minX ||
      point.dx > maxX ||
      point.dy < minY ||
      point.dy > maxY) {
    return false;
  }

  final limit = radius * radius;
  var previous = start;
  for (var step = 1; step <= _curveSteps; step++) {
    final t = step / _curveSteps;
    final u = 1 - t;
    final next = Offset(
      u * u * start.dx + 2 * u * t * control.dx + t * t * end.dx,
      u * u * start.dy + 2 * u * t * control.dy + t * t * end.dy,
    );
    if (_distanceSquaredToSegment(previous, next, point) <= limit) return true;
    previous = next;
  }
  return false;
}

double _distanceSquaredToSegment(Offset a, Offset b, Offset p) {
  final ab = b - a;
  final lengthSquared = ab.distanceSquared;
  if (lengthSquared == 0) return (p - a).distanceSquared;
  final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared).clamp(
    0.0,
    1.0,
  );
  return (p - (a + ab * t)).distanceSquared;
}

double _min3(double a, double b, double c) =>
    a < b ? (a < c ? a : c) : (b < c ? b : c);

double _max3(double a, double b, double c) =>
    a > b ? (a > c ? a : c) : (b > c ? b : c);
