// [ColorDropper]'s hit test: which palette colour is under a point of the
// sheet. Plain `test()` calls — the model needs `dart:ui`'s geometry and no
// engine (`PLAN-phase-8.md` §4.8).

import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/color_dropper.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';

/// Pencil radii in sheet units, by size index: half of `DrawPencils.widths`
/// (8, 18, 32, 52). Named here so the edge cases below read as geometry.
const double _thinRadius = 4;
const double _mediumRadius = 9;

Stroke _stroke(int colorIndex, int sizeIndex, List<Offset> points) =>
    Stroke(colorIndex: colorIndex, sizeIndex: sizeIndex, points: points);

Stroke _eraser(int sizeIndex, List<Offset> points) =>
    _stroke(Stroke.eraserColorIndex, sizeIndex, points);

void main() {
  group('inkAt', () {
    test('an empty sheet has no ink anywhere', () {
      expect(ColorDropper.inkAt(const [], const Offset(800, 600)), isNull);
    });

    test('a point away from every stroke has no ink', () {
      final strokes = [
        _stroke(3, 1, const [Offset(100, 100), Offset(200, 100)]),
      ];
      expect(ColorDropper.inkAt(strokes, const Offset(150, 300)), isNull);
    });

    test('a stroke answers with its palette index', () {
      final strokes = [
        _stroke(7, 1, const [Offset(100, 100), Offset(200, 100)]),
      ];
      expect(ColorDropper.inkAt(strokes, const Offset(150, 100)), 7);
    });

    test('the topmost stroke wins where two overlap, and each keeps its '
        'own ground', () {
      final strokes = [
        _stroke(0, 2, const [Offset(100, 100), Offset(300, 100)]),
        _stroke(6, 2, const [Offset(200, 100), Offset(200, 300)]),
      ];
      // The crossing: the later, blue stroke is drawn over the red one.
      expect(ColorDropper.inkAt(strokes, const Offset(200, 100)), 6);
      // Red alone at its far end, blue alone at its far end.
      expect(ColorDropper.inkAt(strokes, const Offset(110, 100)), 0);
      expect(ColorDropper.inkAt(strokes, const Offset(200, 290)), 6);
    });

    test('the order of the list is the order of drawing, not of colour', () {
      const a = [Offset(100, 100), Offset(300, 100)];
      const b = [Offset(200, 50), Offset(200, 150)];
      expect(
        ColorDropper.inkAt([
          _stroke(1, 2, a),
          _stroke(2, 2, b),
        ], const Offset(200, 100)),
        2,
      );
      expect(
        ColorDropper.inkAt([
          _stroke(2, 2, b),
          _stroke(1, 2, a),
        ], const Offset(200, 100)),
        1,
      );
    });

    test('an eraser on top of a stroke leaves no ink', () {
      final strokes = [
        _stroke(4, 2, const [Offset(100, 100), Offset(300, 100)]),
        _eraser(2, const [Offset(200, 80), Offset(200, 120)]),
      ];
      expect(ColorDropper.inkAt(strokes, const Offset(200, 100)), isNull);
      // Beside the eraser the pencil is still there.
      expect(ColorDropper.inkAt(strokes, const Offset(120, 100)), 4);
    });

    test('a stroke drawn over an eraser shows through again', () {
      final strokes = [
        _stroke(4, 2, const [Offset(100, 100), Offset(300, 100)]),
        _eraser(2, const [Offset(200, 100)]),
        _stroke(9, 0, const [Offset(200, 100)]),
      ];
      expect(ColorDropper.inkAt(strokes, const Offset(200, 100)), 9);
      // Inside the eraser's reach but outside the small dot over it.
      expect(ColorDropper.inkAt(strokes, const Offset(212, 100)), isNull);
    });

    test('an eraser that misses the point is not consulted', () {
      final strokes = [
        _stroke(4, 2, const [Offset(100, 100), Offset(300, 100)]),
        _eraser(0, const [Offset(500, 500), Offset(600, 500)]),
      ];
      expect(ColorDropper.inkAt(strokes, const Offset(200, 100)), 4);
    });
  });

  group('covers', () {
    test('a tap is a dot of the pencil radius, edge included', () {
      final dot = _stroke(0, 1, const [Offset(100, 100)]);
      expect(ColorDropper.covers(dot, const Offset(100, 100)), isTrue);
      expect(
        ColorDropper.covers(dot, const Offset(100 + _mediumRadius, 100)),
        isTrue,
      );
      expect(
        ColorDropper.covers(dot, const Offset(100 + _mediumRadius + 0.01, 100)),
        isFalse,
      );
      // Round, not square: the corner of the bounding box is outside.
      expect(
        ColorDropper.covers(
          dot,
          const Offset(100 + _mediumRadius, 100 + _mediumRadius),
        ),
        isFalse,
      );
    });

    test('a line is as wide as its pencil, no wider', () {
      const line = [Offset(100, 100), Offset(300, 100)];
      final thin = _stroke(0, 0, line);
      final thick = _stroke(0, 2, line);

      // 10 units off the line: outside the thin pencil's 4, inside the thick
      // one's 16.
      const off = Offset(200, 110);
      expect(ColorDropper.covers(thin, off), isFalse);
      expect(ColorDropper.covers(thick, off), isTrue);
      expect(
        ColorDropper.covers(thin, const Offset(200, 100 + _thinRadius)),
        isTrue,
      );
      expect(
        ColorDropper.covers(thin, const Offset(200, 100 + _thinRadius + 0.01)),
        isFalse,
      );
    });

    test('the ends are round caps: covered beyond the last point by the '
        'radius, and not past it', () {
      final line = _stroke(0, 1, const [Offset(100, 100), Offset(300, 100)]);
      expect(
        ColorDropper.covers(line, const Offset(300 + _mediumRadius, 100)),
        isTrue,
      );
      expect(
        ColorDropper.covers(line, const Offset(100 - _mediumRadius, 100)),
        isTrue,
      );
      expect(
        ColorDropper.covers(line, const Offset(300 + _mediumRadius + 0.5, 100)),
        isFalse,
      );
      // A square cap would cover the corner; a round one does not.
      expect(
        ColorDropper.covers(
          line,
          const Offset(300 + _mediumRadius, 100 + _mediumRadius),
        ),
        isFalse,
      );
    });

    test('follows the smoothed curve the painter draws, not the polyline '
        'through the samples', () {
      // An L: right along the top, then down. `paintStroke` rounds the
      // corner, so the sample at (100, 0) is itself never painted.
      const corner = [Offset(0, 0), Offset(100, 0), Offset(100, 100)];
      final thin = _stroke(0, 0, corner);
      final thick = _stroke(0, 2, corner);

      // The curve's own midpoint is on it.
      expect(ColorDropper.covers(thin, const Offset(87.5, 12.5)), isTrue);
      // The corner sample is about 17.7 from the curve: past the thick
      // pencil's 16, which a polyline test would have called covered.
      expect(ColorDropper.covers(thick, const Offset(100, 0)), isFalse);
      // The final straight run to the last point is covered all the way.
      expect(ColorDropper.covers(thin, const Offset(100, 90)), isTrue);
      expect(ColorDropper.covers(thin, const Offset(100, 100)), isTrue);
    });

    test('a point on the sheet\'s corner is covered by a stroke there', () {
      final dot = _stroke(0, 1, const [Offset.zero]);
      final far = _stroke(0, 1, const [Offset(1600, 1200)]);
      expect(ColorDropper.covers(dot, Offset.zero), isTrue);
      expect(ColorDropper.covers(dot, const Offset(1600, 1200)), isFalse);
      expect(ColorDropper.covers(far, const Offset(1600, 1200)), isTrue);
      expect(ColorDropper.covers(far, const Offset(1595, 1195)), isTrue);
    });

    test('a stroke with no points covers nothing', () {
      expect(
        ColorDropper.covers(_stroke(0, 3, const []), const Offset(0, 0)),
        isFalse,
      );
    });

    test('a stroke that stands still still covers its dot', () {
      // Two identical samples make a zero-length segment: no division by
      // zero, and still a dot.
      final still = _stroke(0, 1, const [Offset(50, 50), Offset(50, 50)]);
      expect(ColorDropper.covers(still, const Offset(55, 50)), isTrue);
      expect(ColorDropper.covers(still, const Offset(70, 50)), isFalse);
    });
  });

  group('backdropColorAt', () {
    // A 2 x 2 photo: red, green / blue, half-transparent white.
    final pixels = ByteData.sublistView(
      Uint8List.fromList([
        255, 0, 0, 255, //
        0, 255, 0, 255,
        0, 0, 255, 255,
        255, 255, 255, 128,
      ]),
    );
    // 800 x 600 on the 1600 x 1200 sheet sits at (400, 300) to (1200, 900).
    const stored = Size(800, 600);

    Color? at(Offset point, {Size size = stored}) =>
        ColorDropper.backdropColorAt(
          rgba: pixels,
          pixelWidth: 2,
          pixelHeight: 2,
          sheetSize: size,
          point: point,
        );

    test('maps a sheet point to the pixel under it, centred on the sheet', () {
      expect(at(const Offset(401, 301)), const Color(0xFFFF0000));
      expect(at(const Offset(1100, 301)), const Color(0xFF00FF00));
      expect(at(const Offset(401, 800)), const Color(0xFF0000FF));
      expect(at(const Offset(1100, 800)), const Color(0x80FFFFFF));
    });

    test('the photo\'s own edges are inside it, one pixel in', () {
      expect(at(const Offset(400, 300)), const Color(0xFFFF0000));
      expect(at(const Offset(1200, 900)), const Color(0x80FFFFFF));
    });

    test('a point outside the photo has no photo colour', () {
      expect(at(const Offset(399.9, 500)), isNull);
      expect(at(const Offset(1200.1, 500)), isNull);
      expect(at(const Offset(800, 299.9)), isNull);
      expect(at(const Offset(800, 900.1)), isNull);
      expect(at(const Offset(0, 0)), isNull);
    });

    test('a photo as large as the sheet covers all of it', () {
      expect(
        at(const Offset(0, 0), size: const Size(sheetWidth, sheetHeight)),
        const Color(0xFFFF0000),
      );
      expect(
        at(
          const Offset(sheetWidth, sheetHeight),
          size: const Size(sheetWidth, sheetHeight),
        ),
        const Color(0x80FFFFFF),
      );
    });
  });
}
