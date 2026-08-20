// The canvas: turns a picture into pixels.
//
// A stateless render function over three inputs — the baked image, the live
// strokes still reachable by undo, and the stroke under the finger right now
// (`PLAN-phase-8.md` §4.3). It knows nothing about undo, redo, pointers or
// persistence; [DrawSheetScreen] (`draw_sheet_screen.dart`) is what owns the
// baked [ui.Image] across frames and hands this painter a fresh snapshot
// every time something changes.
//
// No image golden tests: `matchesGoldenFile` differs between Skia and
// Impeller and between platforms, so a golden here would fail on somebody's
// machine for a reason that is not the code. Instead this is tested against
// `TestRecordingCanvas`, which records every canvas call and its order —
// what asserts the "at most 51 strokes plus one image" bound and the
// paper-under-strokes ordering the eraser risk depends on
// (`PLAN-phase-8.md` §4.3, §7).

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model/stroke.dart';

/// Paints the sheet: the paper colour, then [baked], then [liveStrokes] in
/// order, then [current] on top.
///
/// Painted in sheet coordinates ([sheetWidth] x [sheetHeight] from
/// `stroke.dart`) and scaled to fill `size` — the same painter therefore
/// draws a phone's canvas and the export's own 1600 x 1200 identically
/// (`PLAN-phase-8.md` §4.6): a drawing cannot export differently from how it
/// looked.
class DrawingPainter extends CustomPainter {
  DrawingPainter({
    required this.baked,
    required this.liveStrokes,
    required this.current,
    required this.paperColor,
    required this.colorOf,
    required this.widthOf,
    this.backdrop,
  });

  /// An imported photo, downscaled to fit the sheet (`photo_import.dart`),
  /// or null when this drawing has none. Drawn beneath [baked] and never
  /// folded into it — a later "remove the photo" stays a field change
  /// rather than a re-render of pixels already mixed together
  /// (`PLAN-phase-8.md` §4.3, §4.6).
  final ui.Image? backdrop;

  /// Every stroke below the undo horizon, folded into one image by the
  /// screen's bake — or null before the first bake.
  final ui.Image? baked;

  /// Strokes still reachable by undo, oldest first. At most `drawUndoHorizon`
  /// of them (`drawing_controller.dart`).
  final List<Stroke> liveStrokes;

  /// The stroke under the finger right now, or null when nothing is being
  /// drawn.
  final Stroke? current;

  /// The sheet's background, painted first and outside the `saveLayer` below
  /// so an eraser's `BlendMode.clear` reveals paper rather than punching
  /// through to whatever sits behind this widget (`PLAN-phase-8.md` §4.2,
  /// §7).
  final Color paperColor;

  /// Resolves a [Stroke.colorIndex] to a paint colour. A placeholder
  /// signature until `palette.dart` (PR 3) supplies the twelve named
  /// swatches — never called for an eraser stroke.
  final Color Function(int colorIndex) colorOf;

  /// Resolves a [Stroke.sizeIndex] to a stroke width, in sheet units.
  final double Function(int sizeIndex) widthOf;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paperColor);

    canvas.save();
    canvas.scale(size.width / sheetWidth, size.height / sheetHeight);

    // Isolated in its own layer so an eraser's `BlendMode.clear` only ever
    // clears pixels painted inside this layer — the backdrop, the bake and
    // the live strokes — rather than reaching through to whatever this
    // canvas sits on top of. Without this, clearing punches straight past
    // the paper rect painted above (it is on the canvas *outside* this
    // layer) to whatever is behind the widget, which is how an eraser ends
    // up looking like it draws in black instead of revealing paper.
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, sheetWidth, sheetHeight),
      Paint(),
    );
    if (backdrop case final image?) drawBackdropImage(canvas, image);
    if (baked case final image?) drawBakedImage(canvas, image);
    for (final stroke in liveStrokes) {
      paintStroke(canvas, stroke, colorOf: colorOf, widthOf: widthOf);
    }
    if (current case final stroke?) {
      paintStroke(canvas, stroke, colorOf: colorOf, widthOf: widthOf);
    }
    canvas.restore();

    canvas.restore();
  }

  /// Compares the live stroke's point count, the stroke-list length and the
  /// baked and backdrop images' identity — not the strokes' contents — so a
  /// rebuild that changed neither does not repaint (`PLAN-phase-8.md` §4.3).
  @override
  bool shouldRepaint(covariant DrawingPainter oldDelegate) =>
      !identical(oldDelegate.baked, baked) ||
      !identical(oldDelegate.backdrop, backdrop) ||
      oldDelegate.liveStrokes.length != liveStrokes.length ||
      (oldDelegate.current?.points.length ?? 0) !=
          (current?.points.length ?? 0);
}

/// Draws [image] to fill the sheet, in sheet coordinates.
///
/// Shared between [DrawingPainter.paint] and the bake compositing in
/// `draw_sheet_screen.dart`, so the baked image is scaled identically
/// whichever call site is drawing it.
void drawBakedImage(Canvas canvas, ui.Image image) {
  canvas.drawImageRect(
    image,
    Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
    const Rect.fromLTWH(0, 0, sheetWidth, sheetHeight),
    Paint(),
  );
}

/// Draws [image] centered in the sheet at its own size, never stretched.
///
/// `downscaleToSheet` (`photo_import.dart`) guarantees [image] already fits
/// within [sheetWidth] x [sheetHeight] without upscaling, so centering it is
/// the only placement decision left — stretching it to fill the sheet would
/// distort whatever aspect ratio the photo actually had.
void drawBackdropImage(Canvas canvas, ui.Image image) {
  final size = Size(image.width.toDouble(), image.height.toDouble());
  final offset = Offset(
    (sheetWidth - size.width) / 2,
    (sheetHeight - size.height) / 2,
  );
  canvas.drawImageRect(image, Offset.zero & size, offset & size, Paint());
}

/// Decodes [bytes] into a [ui.Image].
///
/// Shared by `draw_sheet_screen.dart`, which decodes a resumed or freshly
/// imported backdrop once, and `png_export.dart`, which decodes one to draw
/// into the export — so a backdrop is never decoded by two different code
/// paths that could disagree.
Future<ui.Image> decodeSheetImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  return frame.image;
}

/// Draws one [stroke] into [canvas], in sheet coordinates.
///
/// Shared between [DrawingPainter.paint] and the bake compositing in
/// `draw_sheet_screen.dart`, so a stroke renders identically whether it is
/// being drawn live or folded into the baked image.
void paintStroke(
  Canvas canvas,
  Stroke stroke, {
  required Color Function(int colorIndex) colorOf,
  required double Function(int sizeIndex) widthOf,
}) {
  final width = widthOf(stroke.sizeIndex);
  final color = stroke.isEraser
      ? const Color(0x00000000)
      : colorOf(stroke.colorIndex);
  final blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;
  final points = stroke.points;

  if (points.length == 1) {
    // A tap: a filled dot, not an invisible zero-length line
    // (`PLAN-phase-8.md` §4.2).
    canvas.drawCircle(
      points.first,
      width / 2,
      Paint()
        ..color = color
        ..blendMode = blendMode
        ..isAntiAlias = true,
    );
    return;
  }

  // Quadratic segments, control point at each sample and end point at the
  // midpoint of that sample and the next, so the curve passes through the
  // midpoints and never corners at a sample — then a final segment to the
  // last point exactly, which is where the finger left
  // (`PLAN-phase-8.md` §4.2).
  final path = Path()..moveTo(points.first.dx, points.first.dy);
  for (var i = 0; i < points.length - 1; i++) {
    final mid = Offset.lerp(points[i], points[i + 1], 0.5)!;
    path.quadraticBezierTo(points[i].dx, points[i].dy, mid.dx, mid.dy);
  }
  path.lineTo(points.last.dx, points.last.dy);

  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..blendMode = blendMode
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true,
  );
}
