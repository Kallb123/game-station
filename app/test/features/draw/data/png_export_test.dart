// [exportDrawingToPng]'s own test: the exported bytes decode to a real PNG
// at the sheet's own resolution, and its pixels are the paper colour where
// nothing was drawn and the stroke's colour where a stroke was
// (`PLAN-phase-8.md` §6 PR 5's own done-criterion).
//
// No `matchesGoldenFile`: `drawing_painter_test.dart`'s header gives the
// reason — Skia and Impeller differ, and so does platform to platform. This
// decodes the export itself and reads specific pixels back out of it, which
// is a claim about this code rather than about a byte-for-byte image.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color, Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/data/png_export.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';

const Color _paper = Color(0xFFFFFFFF);
const Color _black = Color(0xFF000000); // DrawPalette.colors[10]

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('exports at the sheet\'s own 1600 x 1200 resolution', () async {
    final drawing = Drawing(id: 'd1', createdAt: DateTime.utc(2026, 8, 20));

    final bytes = await exportDrawingToPng(drawing, paperColor: _paper);
    final image = await _decode(bytes);

    expect(image.width, 1600);
    expect(image.height, 1200);
  });

  test('paints the paper colour where nothing was drawn', () async {
    final drawing = Drawing(id: 'd1', createdAt: DateTime.utc(2026, 8, 20));

    final bytes = await exportDrawingToPng(drawing, paperColor: _paper);
    final pixels = await _rawRgba(bytes);

    expect(_pixelAt(pixels, 1600, x: 10, y: 10), _paper);
  });

  test('paints a stroke in its own colour, on the paper elsewhere', () async {
    // A thick, wide horizontal black line, well clear of both edges — a
    // reference drawing small enough to reason about by hand.
    final drawing = Drawing(
      id: 'd1',
      createdAt: DateTime.utc(2026, 8, 20),
      strokes: const [
        Stroke(
          colorIndex: 10, // Black, DrawPalette.colors[10]
          sizeIndex: 3, // 52 sheet units wide, DrawPencils.widths[3]
          points: [Offset(200, 600), Offset(600, 600)],
        ),
      ],
    );

    final bytes = await exportDrawingToPng(drawing, paperColor: _paper);
    final pixels = await _rawRgba(bytes);

    // On the line, comfortably inside its 52-unit width.
    expect(_pixelAt(pixels, 1600, x: 400, y: 600), _black);
    // Off the line entirely, and off both ends of it.
    expect(_pixelAt(pixels, 1600, x: 10, y: 10), _paper);
    expect(_pixelAt(pixels, 1600, x: 400, y: 1190), _paper);
  });

  test('an erased stroke leaves paper, not a transparent hole', () async {
    // A black line, then an eraser pass along the same points — on screen
    // this reads as bare paper, and the export has to agree: nothing sits
    // behind an offscreen `PictureRecorder` the way a themed widget sits
    // behind the sheet on screen, so a `BlendMode.clear` that reached the
    // paper rect itself would leave a transparent hole instead.
    final drawing = Drawing(
      id: 'd1',
      createdAt: DateTime.utc(2026, 8, 20),
      strokes: const [
        Stroke(
          colorIndex: 10, // Black
          sizeIndex: 3,
          points: [Offset(200, 600), Offset(600, 600)],
        ),
        Stroke(
          colorIndex: Stroke.eraserColorIndex,
          sizeIndex: 3,
          points: [Offset(200, 600), Offset(600, 600)],
        ),
      ],
    );

    final bytes = await exportDrawingToPng(drawing, paperColor: _paper);
    final pixels = await _rawRgba(bytes);

    expect(_pixelAt(pixels, 1600, x: 400, y: 600), _paper);
  });
}

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  return frame.image;
}

Future<ByteData> _rawRgba(Uint8List png) async {
  final image = await _decode(png);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return bytes!;
}

Color _pixelAt(ByteData rgba, int width, {required int x, required int y}) {
  final offset = (y * width + x) * 4;
  return Color.fromARGB(
    rgba.getUint8(offset + 3),
    rgba.getUint8(offset),
    rgba.getUint8(offset + 1),
    rgba.getUint8(offset + 2),
  );
}
