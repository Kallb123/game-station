// Turns a [Drawing] into PNG bytes at the sheet's own resolution
// (`PLAN-phase-8.md` §4.6).
//
// The same paper fill and the same `paintStroke` the screen paints with,
// recorded onto a `sheetWidth` x `sheetHeight` canvas rather than one scaled
// to a widget — so a drawing cannot export differently from how it looked.
// No `package:image`: `dart:ui` already encodes PNG, and a second decoder for
// the same format is a dependency this phase does not need.
//
// Strokes are painted inside a `saveLayer`, not directly onto the paper rect.
// `drawing_painter.dart`'s own canvas gets away with a flat, unlayered paint
// order — an eraser's `BlendMode.clear` clears straight to transparent, and
// what shows through is whatever real widget sits behind the `CustomPaint`,
// which happens to be painted the same colour as `paperColor`. Nothing sits
// behind a `PictureRecorder`: without the layer, an eraser stroke would clear
// a genuine hole in the PNG — transparent, not paper-coloured — the moment a
// drawing used it. Inside the layer, `clear` only ever erases ink this same
// export already painted; restoring the layer composites it back over the
// paper rect underneath with a normal blend, so a transparent stroke pixel
// leaves the paper showing rather than erasing it too.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Canvas, Color, Paint, Rect;

import '../model/palette.dart';
import '../model/stroke.dart';
import '../ui/drawing_painter.dart';

/// Renders every stroke of [drawing] onto a [sheetWidth] x [sheetHeight]
/// canvas over [paperColor] and encodes the result as PNG.
///
/// [paperColor] is passed in rather than read from a `Theme`: this runs from
/// a button's `onPressed`, not from a paint pass, so there is no
/// `BuildContext` to read one from.
Future<Uint8List> exportDrawingToPng(
  Drawing drawing, {
  required Color paperColor,
}) async {
  const sheetRect = Rect.fromLTWH(0, 0, sheetWidth, sheetHeight);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(sheetRect, Paint()..color = paperColor);
  canvas.saveLayer(sheetRect, Paint());
  for (final stroke in drawing.strokes) {
    paintStroke(
      canvas,
      stroke,
      colorOf: DrawPalette.colorAt,
      widthOf: DrawPencils.widthAt,
    );
  }
  canvas.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(sheetWidth.round(), sheetHeight.round());
  picture.dispose();
  try {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return bytes!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
