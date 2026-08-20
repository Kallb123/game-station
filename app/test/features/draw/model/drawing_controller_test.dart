// [DrawingController]'s invariants — the phase's real difficulty, and
// testable without a canvas (`PLAN-phase-8.md` §10). This is PR 1's own
// done-criterion list: undo then redo returns the identical stroke list, a
// new stroke after an undo empties the redo stack, and the 51st stroke bakes
// exactly once.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/drawing_controller.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';

Stroke _strokeAt(int n) => Stroke(
  colorIndex: n % 12,
  sizeIndex: n % 4,
  points: [Offset(n.toDouble(), 0)],
);

void main() {
  group('drawing strokes', () {
    test('beginStroke, extendStroke and endStroke produce one stroke', () {
      final controller = DrawingController();

      controller.beginStroke(
        colorIndex: 3,
        sizeIndex: 1,
        point: const Offset(0, 0),
      );
      controller.extendStroke(const Offset(1, 1));
      controller.extendStroke(const Offset(2, 2));
      controller.endStroke();

      expect(controller.strokes, [
        const Stroke(
          colorIndex: 3,
          sizeIndex: 1,
          points: [Offset(0, 0), Offset(1, 1), Offset(2, 2)],
        ),
      ]);
    });

    test('a tap — begin then end with no extend — is a one-point stroke', () {
      final controller = DrawingController();

      controller.beginStroke(
        colorIndex: 0,
        sizeIndex: 0,
        point: const Offset(5, 5),
      );
      controller.endStroke();

      expect(controller.strokes.single.points, [const Offset(5, 5)]);
    });

    test('endStroke with nothing open does nothing', () {
      final controller = DrawingController();

      controller.endStroke();

      expect(controller.strokes, isEmpty);
    });

    test('current reflects the stroke being drawn, and clears once closed', () {
      final controller = DrawingController();
      expect(controller.current, isNull);

      controller.beginStroke(
        colorIndex: 0,
        sizeIndex: 0,
        point: const Offset(0, 0),
      );
      expect(controller.current, isNotNull);

      controller.endStroke();
      expect(controller.current, isNull);
    });

    test('addStroke appends a complete stroke directly', () {
      final controller = DrawingController();
      const stroke = Stroke(colorIndex: 1, sizeIndex: 1, points: [Offset.zero]);

      controller.addStroke(stroke);

      expect(controller.strokes, [stroke]);
    });
  });

  group('undo and redo', () {
    test('undo then redo returns the identical stroke list', () {
      final controller = DrawingController();
      controller.addStroke(_strokeAt(0));
      controller.addStroke(_strokeAt(1));
      final before = controller.strokes;

      controller.undo();
      controller.redo();

      expect(controller.strokes, before);
    });

    test('undo moves the last stroke to redo', () {
      final controller = DrawingController()
        ..addStroke(_strokeAt(0))
        ..addStroke(_strokeAt(1));

      controller.undo();

      expect(controller.strokes, [_strokeAt(0)]);
      expect(controller.canRedo, isTrue);
    });

    test('a new stroke after an undo empties the redo stack', () {
      final controller = DrawingController()
        ..addStroke(_strokeAt(0))
        ..addStroke(_strokeAt(1));

      controller.undo();
      expect(controller.canRedo, isTrue);

      controller.addStroke(_strokeAt(2));

      expect(controller.canRedo, isFalse);
      expect(controller.strokes, [_strokeAt(0), _strokeAt(2)]);
    });

    test('canUndo and canRedo are false on an empty drawing', () {
      final controller = DrawingController();

      expect(controller.canUndo, isFalse);
      expect(controller.canRedo, isFalse);
    });

    test('undo and redo do nothing when their stack is empty', () {
      final controller = DrawingController()..addStroke(_strokeAt(0));

      controller.redo(); // nothing to redo
      expect(controller.strokes, [_strokeAt(0)]);

      controller.undo();
      controller.undo(); // nothing left to undo
      expect(controller.strokes, isEmpty);
    });
  });

  group('the bake horizon', () {
    test('fewer than 51 strokes never bakes', () {
      final controller = DrawingController();
      for (var i = 0; i < drawUndoHorizon; i++) {
        controller.addStroke(_strokeAt(i));
      }

      expect(controller.takeBaked(), isNull);
      expect(controller.canUndo, isTrue);
    });

    test('the 51st stroke triggers a bake callback exactly once', () {
      final controller = DrawingController();
      for (var i = 0; i < drawUndoHorizon; i++) {
        controller.addStroke(_strokeAt(i));
      }

      controller.addStroke(_strokeAt(drawUndoHorizon));

      expect(controller.takeBaked(), _strokeAt(0));
      // Reported once: the read clears it.
      expect(controller.takeBaked(), isNull);
    });

    test('a baked stroke is still part of the picture', () {
      final controller = DrawingController();
      for (var i = 0; i <= drawUndoHorizon; i++) {
        controller.addStroke(_strokeAt(i));
      }

      expect(controller.strokes.first, _strokeAt(0));
      expect(controller.strokes.length, drawUndoHorizon + 1);
    });

    test('undo cannot reach past the horizon once a stroke has baked', () {
      final controller = DrawingController();
      for (var i = 0; i <= drawUndoHorizon; i++) {
        controller.addStroke(_strokeAt(i));
      }

      for (var i = 0; i < drawUndoHorizon; i++) {
        controller.undo();
      }

      expect(controller.canUndo, isFalse);
      // The horizon's own stroke is still there — undo stopped, it did not
      // remove it.
      expect(controller.strokes, [_strokeAt(0)]);
    });

    test('liveStrokes holds at most the horizon, bakedStrokes the rest', () {
      final controller = DrawingController();
      for (var i = 0; i <= drawUndoHorizon; i++) {
        controller.addStroke(_strokeAt(i));
      }

      expect(controller.liveStrokes.length, drawUndoHorizon);
      expect(controller.bakedStrokes, [_strokeAt(0)]);
    });

    test(
      'resuming a drawing already past the horizon starts already baked',
      () {
        final saved = [
          for (var i = 0; i < drawUndoHorizon + 10; i++) _strokeAt(i),
        ];

        final controller = DrawingController(strokes: saved);

        expect(controller.bakedStrokes.length, 10);
        expect(controller.liveStrokes.length, drawUndoHorizon);
        expect(controller.strokes, saved);
        // Nothing was baked *by this session* yet.
        expect(controller.takeBaked(), isNull);
      },
    );
  });

  group('the backdrop', () {
    test('starts null', () {
      final controller = DrawingController();

      expect(controller.backdrop, isNull);
      expect(controller.takeNewBackdrop(), isNull);
    });

    test('setBackdrop sets it, reports it as new once, and notifies', () {
      final controller = DrawingController();
      var notified = 0;
      controller.addListener(() => notified++);
      final bytes = Uint8List.fromList([1, 2, 3]);

      controller.setBackdrop(bytes);

      expect(controller.backdrop, bytes);
      expect(notified, 1);
      expect(controller.takeNewBackdrop(), bytes);
      // Cleared by the read — the same outbox shape as takeBaked.
      expect(controller.takeNewBackdrop(), isNull);
    });

    test('a second setBackdrop does not replace an existing one', () {
      final controller = DrawingController();
      final first = Uint8List.fromList([1]);
      final second = Uint8List.fromList([2]);
      controller.setBackdrop(first);
      controller.takeNewBackdrop();

      controller.setBackdrop(second);

      expect(controller.backdrop, first);
      expect(controller.takeNewBackdrop(), isNull);
    });

    test('a resumed drawing starts with its backdrop already set, not new', () {
      final bytes = Uint8List.fromList([9, 9]);

      final controller = DrawingController(backdrop: bytes);

      expect(controller.backdrop, bytes);
      // Set through the constructor, not setBackdrop, so there is nothing
      // for the sheet screen's outbox-read to find.
      expect(controller.takeNewBackdrop(), isNull);
    });
  });
}
