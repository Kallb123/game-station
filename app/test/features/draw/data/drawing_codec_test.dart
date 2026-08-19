// The codec's tests: round trip, the point-rounding budget, and the same
// strict-about-types rule `save_codec_test.dart` holds the save file to.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/data/drawing_codec.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';

/// 200 strokes, each with a handful of points already at the codec's 1-decimal
/// precision, so encode-then-decode is exact rather than approximate.
Drawing _bigDrawing() => Drawing(
  id: 'd1',
  createdAt: DateTime.utc(2026, 8, 11, 10),
  strokes: [
    for (var s = 0; s < 200; s++)
      Stroke(
        colorIndex: s % 12,
        sizeIndex: s % 4,
        points: [
          Offset(s * 1.5, s * 0.5),
          Offset(s * 1.5 + 0.1, s * 0.5 + 0.2),
        ],
      ),
  ],
);

void main() {
  group('round trip', () {
    test('a 200-stroke drawing round-trips to an equal Drawing', () {
      final original = _bigDrawing();

      expect(decodeDrawing(encodeDrawing(original)), original);
    });

    test('a drawing with a backdrop round trips', () {
      final drawing = Drawing(
        id: 'd2',
        createdAt: DateTime.utc(2026, 8, 12),
        strokes: const [
          Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset(1, 1)]),
        ],
        backdrop: Uint8List.fromList([0, 1, 2, 255]),
      );

      expect(decodeDrawing(encodeDrawing(drawing)), drawing);
    });

    test('an eraser stroke round trips its negative colour index', () {
      final drawing = Drawing(
        id: 'd3',
        createdAt: DateTime.utc(2026),
        strokes: const [
          Stroke(
            colorIndex: Stroke.eraserColorIndex,
            sizeIndex: 2,
            points: [Offset(3, 4)],
          ),
        ],
      );

      expect(decodeDrawing(encodeDrawing(drawing)), drawing);
    });

    test('a drawing with no strokes round trips', () {
      final drawing = Drawing(id: 'd4', createdAt: DateTime.utc(2026));

      expect(decodeDrawing(encodeDrawing(drawing)), drawing);
    });

    test('points are rounded to one decimal place', () {
      final drawing = Drawing(
        id: 'd5',
        createdAt: DateTime.utc(2026),
        strokes: const [
          Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset(1.2345, 6.789)]),
        ],
      );

      final decoded = decodeDrawing(encodeDrawing(drawing));

      expect(decoded.strokes.single.points.single, const Offset(1.2, 6.8));
    });
  });

  group('malformed input', () {
    test('text that is not JSON is a format error', () {
      expect(
        () => decodeDrawing('{oh no'),
        throwsA(isA<DrawingFormatException>()),
      );
    });

    test('a missing id is a format error', () {
      expect(
        () => decodeDrawing(
          jsonEncode({
            'createdAt': '2026-08-11T10:00:00Z',
            'strokes': <Object?>[],
          }),
        ),
        throwsA(isA<DrawingFormatException>()),
      );
    });

    test('an odd number of point coordinates is a format error', () {
      expect(
        () => decodeDrawing(
          jsonEncode({
            'id': 'd1',
            'createdAt': '2026-08-11T10:00:00Z',
            'strokes': [
              {
                'colorIndex': 0,
                'sizeIndex': 0,
                'points': [1, 2, 3],
              },
            ],
          }),
        ),
        throwsA(isA<DrawingFormatException>()),
      );
    });

    test('an empty points list is a format error', () {
      expect(
        () => decodeDrawing(
          jsonEncode({
            'id': 'd1',
            'createdAt': '2026-08-11T10:00:00Z',
            'strokes': [
              {'colorIndex': 0, 'sizeIndex': 0, 'points': <Object?>[]},
            ],
          }),
        ),
        throwsA(isA<DrawingFormatException>()),
      );
    });

    test('backdrop that is not valid base64 is a format error', () {
      expect(
        () => decodeDrawing(
          jsonEncode({
            'id': 'd1',
            'createdAt': '2026-08-11T10:00:00Z',
            'strokes': <Object?>[],
            'backdrop': 'not base64!!',
          }),
        ),
        throwsA(isA<DrawingFormatException>()),
      );
    });

    test('a non-string createdAt is a format error', () {
      expect(
        () => decodeDrawing(
          jsonEncode({'id': 'd1', 'createdAt': 1, 'strokes': <Object?>[]}),
        ),
        throwsA(isA<DrawingFormatException>()),
      );
    });
  });
}
