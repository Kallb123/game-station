// The picture, as data.
//
// A [Stroke] is a colour, a width and the sheet-coordinate points the finger
// visited. A [Drawing] is a list of them in drawing order, plus an optional
// imported backdrop. `dart:ui` for [Offset] is as close as this file comes to
// Flutter — no widget, no `dart:io` — so its tests are plain `test()` calls
// (`PLAN-phase-8.md` §4.1).

import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

/// The sheet every stroke's points are in, independent of the screen that
/// shows it — the same trick as `PLAN.md` §4.1's 224 x 256 field, so a phone
/// and a tablet draw the same picture (`PLAN-phase-8.md` §1).
const double sheetWidth = 1600;
const double sheetHeight = 1200;

/// One stroke of the pencil, or one pass of the eraser.
@immutable
class Stroke {
  // No assertion that `points` is non-empty: `List.length` is not a
  // constant-expression operation, and every constructor here is `const` so
  // literal strokes can sit in a `const` list. `beginStroke` always seeds a
  // stroke with its first point, so an empty one never arises in practice
  // (`drawing_controller.dart`); the codec refuses one read from disk
  // (`drawing_codec.dart`).
  const Stroke({
    required this.colorIndex,
    required this.sizeIndex,
    required this.points,
  }) : assert(sizeIndex >= 0, 'sizeIndex indexes the pencil-width table');

  /// Index into the swatch palette (`palette.dart`, PR 3).
  final int colorIndex;

  /// Whether [colorIndex] means "erase" rather than a palette entry.
  ///
  /// A dedicated value rather than a magic `-1` read back out of
  /// [colorIndex] at every call site — one place decides what "erasing"
  /// means, and every reader asks it rather than the encoding.
  static const int eraserColorIndex = -1;

  /// Index into the four pencil widths.
  final int sizeIndex;

  /// Sheet-coordinate points, first included, in the order the finger drew
  /// them.
  final List<Offset> points;

  /// Whether this stroke erases rather than draws.
  bool get isEraser => colorIndex == eraserColorIndex;

  @override
  bool operator ==(Object other) =>
      other is Stroke &&
      other.colorIndex == colorIndex &&
      other.sizeIndex == sizeIndex &&
      _offsetsEqual(other.points, points);

  @override
  int get hashCode =>
      Object.hash(colorIndex, sizeIndex, Object.hashAll(points));

  @override
  String toString() =>
      'Stroke(colorIndex: $colorIndex, sizeIndex: $sizeIndex, '
      '${points.length} points)';
}

/// One saved picture: a list of [Stroke]s and, when a photo was imported, a
/// locked backdrop drawn beneath them (`PLAN-phase-8.md` §4.6).
@immutable
class Drawing {
  const Drawing({
    required this.id,
    required this.createdAt,
    this.strokes = const [],
    this.backdrop,
  }) : assert(id != '', 'a drawing always has an id');

  /// `"d1"`, `"d2"`, … — a counter, like profile ids
  /// (`PLAN-phase-1.md` §1, `PLAN.md` §5.2).
  final String id;

  /// When this drawing was started, in UTC.
  final DateTime createdAt;

  /// Every stroke ever drawn on this sheet, oldest first. The undo horizon
  /// (`drawing_controller.dart`) bounds how many of these a child can still
  /// undo, not how many are stored — the picture is every stroke, always.
  final List<Stroke> strokes;

  /// A downscaled, PNG-encoded photo drawn beneath [strokes], or null when
  /// this sheet has no backdrop. Locked: nothing here moves, scales or erases
  /// it (`PLAN-phase-8.md` §4.6).
  final Uint8List? backdrop;

  Drawing copyWith({List<Stroke>? strokes, Uint8List? backdrop}) => Drawing(
    id: id,
    createdAt: createdAt,
    strokes: strokes ?? this.strokes,
    backdrop: backdrop ?? this.backdrop,
  );

  @override
  bool operator ==(Object other) =>
      other is Drawing &&
      other.id == id &&
      other.createdAt == createdAt &&
      _strokesEqual(other.strokes, strokes) &&
      _bytesEqual(other.backdrop, backdrop);

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    Object.hashAll(strokes),
    backdrop == null ? null : Object.hashAll(backdrop!),
  );
}

bool _offsetsEqual(List<Offset> a, List<Offset> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _strokesEqual(List<Stroke> a, List<Stroke> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _bytesEqual(Uint8List? a, Uint8List? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
