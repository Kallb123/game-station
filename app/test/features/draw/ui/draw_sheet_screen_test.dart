// [DrawSheetScreen]'s pointer handling: the §4.2 sampling rule that turns a
// dense pointer stream into a bounded stroke, and the tap-to-dot case
// (`PLAN-phase-8.md` §6, PR 2's done criteria).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/drawing_controller.dart';
import 'package:zibo_games/features/draw/ui/draw_sheet_screen.dart';
import 'package:zibo_games/features/draw/ui/drawing_painter.dart';

/// The sheet's own [CustomPaint], not the ones `Scaffold`'s `Material`
/// paints its shape with.
final Finder _canvasFinder = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is DrawingPainter,
);

/// Pumps [DrawSheetScreen] over [controller] at a fixed, generous viewport
/// and returns the canvas's rect in the test's coordinate space.
Future<Rect> _pumpAndFindCanvas(
  WidgetTester tester,
  DrawingController controller,
) async {
  tester.view.physicalSize = const Size(1800, 1500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(home: DrawSheetScreen(controller: controller)),
  );
  await tester.pumpAndSettle();

  final topLeft = tester.getTopLeft(_canvasFinder);
  final size = tester.getSize(_canvasFinder);
  return topLeft & size;
}

void main() {
  testWidgets(
    'a drag well past the sampling threshold appends one point per move',
    (tester) async {
      final controller = DrawingController();
      final canvas = await _pumpAndFindCanvas(tester, controller);

      // sheetWidth/steps sheet units per move — far past drawSampleDistance,
      // so nothing this drag sends is coalesced.
      const steps = 40;
      final stepPx = canvas.width / steps;

      final gesture = await tester.startGesture(
        canvas.topLeft + const Offset(1, 1),
      );
      for (var i = 0; i < steps; i++) {
        await gesture.moveBy(Offset(stepPx, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      expect(controller.strokes, hasLength(1));
      expect(controller.strokes.single.points, hasLength(steps + 1));
    },
  );

  testWidgets(
    'a drag of many sub-threshold moves is coalesced into fewer points',
    (tester) async {
      final controller = DrawingController();
      final canvas = await _pumpAndFindCanvas(tester, controller);

      // Each move covers roughly one sheet unit — well under the 2-unit
      // threshold — however many of them are sent: the sampling rule, not
      // the pointer stream, decides how many points land in the stroke
      // (`PLAN-phase-8.md` §4.2).
      const moves = 300;
      final tinyStepPx = canvas.width / 1600;

      final gesture = await tester.startGesture(
        canvas.topLeft + const Offset(1, 1),
      );
      for (var i = 0; i < moves; i++) {
        await gesture.moveBy(Offset(tinyStepPx, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();

      final points = controller.strokes.single.points;
      expect(points.length, lessThan(moves));
      for (var i = 1; i < points.length; i++) {
        expect(
          (points[i] - points[i - 1]).distance,
          greaterThan(drawSampleDistance - 0.05),
        );
      }
    },
  );

  testWidgets('a tap with no movement produces a one-point stroke', (
    tester,
  ) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    await tester.tapAt(canvas.center);
    await tester.pump();

    expect(controller.strokes, hasLength(1));
    expect(controller.strokes.single.points, hasLength(1));
  });

  testWidgets('a second pointer down mid-stroke is ignored', (tester) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    final first = await tester.startGesture(
      canvas.topLeft + const Offset(10, 10),
    );
    final second = await tester.startGesture(
      canvas.topLeft + const Offset(50, 50),
    );
    await first.moveBy(const Offset(20, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pump();

    // Only the first pointer's stroke exists: the second's down was ignored,
    // so it never opened one for the up event to close.
    expect(controller.strokes, hasLength(1));
  });
}
