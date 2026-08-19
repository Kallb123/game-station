// [Stroke] and [Drawing]'s value equality — what every codec and controller
// test below relies on to say "this round-tripped to the same thing".

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';

void main() {
  group('Stroke', () {
    test('two strokes with the same points are equal and hash alike', () {
      const a = Stroke(
        colorIndex: 2,
        sizeIndex: 1,
        points: [Offset(1, 1), Offset(2, 2)],
      );
      const b = Stroke(
        colorIndex: 2,
        sizeIndex: 1,
        points: [Offset(1, 1), Offset(2, 2)],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different point makes two strokes unequal', () {
      const a = Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset(1, 1)]);
      const b = Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset(1, 2)]);

      expect(a, isNot(b));
    });

    test('isEraser is true only for the eraser colour index', () {
      const pencil = Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset.zero]);
      const eraser = Stroke(
        colorIndex: Stroke.eraserColorIndex,
        sizeIndex: 0,
        points: [Offset.zero],
      );

      expect(pencil.isEraser, isFalse);
      expect(eraser.isEraser, isTrue);
    });
  });

  group('Drawing', () {
    test('two drawings with the same strokes and backdrop are equal', () {
      final a = Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026, 8, 11),
        strokes: const [
          Stroke(colorIndex: 1, sizeIndex: 1, points: [Offset(1, 1)]),
        ],
        backdrop: Uint8List.fromList([1, 2, 3]),
      );
      final b = Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026, 8, 11),
        strokes: const [
          Stroke(colorIndex: 1, sizeIndex: 1, points: [Offset(1, 1)]),
        ],
        backdrop: Uint8List.fromList([1, 2, 3]),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different backdrop makes two drawings unequal', () {
      final a = Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026),
        backdrop: Uint8List.fromList([1]),
      );
      final b = Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026),
        backdrop: Uint8List.fromList([2]),
      );

      expect(a, isNot(b));
    });

    test('copyWith changes only what it is given', () {
      final drawing = Drawing(id: 'd1', createdAt: DateTime.utc(2026));
      const stroke = Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset.zero]);

      final withStroke = drawing.copyWith(strokes: [stroke]);

      expect(withStroke.strokes, [stroke]);
      expect(withStroke.id, drawing.id);
      expect(withStroke.createdAt, drawing.createdAt);
    });
  });
}
