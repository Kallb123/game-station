// [DrawSheetScreen]'s pointer handling: the §4.2 sampling rule that turns a
// dense pointer stream into a bounded stroke, and the tap-to-dot case
// (`PLAN-phase-8.md` §6, PR 2's done criteria) — plus PR 3's tool row wired
// to it: picking a size or a colour is what the next stroke draws with, and
// New sheet swaps in a blank picture without touching a caller-supplied
// controller's own strokes.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/drawing_controller.dart';
import 'package:zibo_games/features/draw/ui/draw_sheet_screen.dart';
import 'package:zibo_games/features/draw/ui/drawing_painter.dart';
import 'package:zibo_games/features/draw/ui/tool_row.dart';

/// A tiny, real, decodable PNG — enough for `DrawingController(backdrop:)`
/// to have something `decodeSheetImage` can actually decode.
Future<Uint8List> _tinyPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 10, 10),
    Paint()..color = const Color(0xFF336699),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(10, 10);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

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

  testWidgets('picking a size and a colour from the tool row is what the '
      'next stroke draws with', (tester) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    await tester.tap(find.byKey(ToolRow.sizeKey(2)));
    await tester.tap(find.byKey(ToolRow.colorKey(5)));
    await tester.pump();
    await tester.tapAt(canvas.center);
    await tester.pump();

    expect(controller.strokes.single.sizeIndex, 2);
    expect(controller.strokes.single.colorIndex, 5);
  });

  testWidgets('picking the eraser draws an erasing stroke, and picking a '
      'colour again leaves it', (tester) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    await tester.tap(find.byKey(ToolRow.eraserKey));
    await tester.pump();
    await tester.tapAt(canvas.center);
    await tester.pump();
    expect(controller.strokes.single.isEraser, isTrue);

    await tester.tap(find.byKey(ToolRow.colorKey(0)));
    await tester.pump();
    await tester.tapAt(canvas.center);
    await tester.pump();
    expect(controller.strokes.last.isEraser, isFalse);
  });

  testWidgets('undo and redo on the tool row act on the drawing', (
    tester,
  ) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    await tester.tapAt(canvas.center);
    await tester.pump();
    expect(controller.strokes, hasLength(1));

    await tester.tap(find.byKey(ToolRow.undoKey));
    await tester.pump();
    expect(controller.strokes, isEmpty);

    await tester.tap(find.byKey(ToolRow.redoKey));
    await tester.pump();
    expect(controller.strokes, hasLength(1));
  });

  testWidgets('New sheet starts blank without touching the given '
      'controller\'s own strokes', (tester) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    await tester.tapAt(canvas.center);
    await tester.pump();
    expect(controller.strokes, hasLength(1));

    await tester.tap(find.byKey(ToolRow.newSheetKey));
    await tester.pumpAndSettle();

    // The screen now shows an empty sheet...
    await tester.tapAt(canvas.center);
    await tester.pump();
    final onScreenNow =
        tester.widgetList<CustomPaint>(_canvasFinder).single.painter!
            as DrawingPainter;
    expect(onScreenNow.liveStrokes, hasLength(1));

    // ...and the controller the caller handed in still has exactly the one
    // stroke it had before New sheet was tapped.
    expect(controller.strokes, hasLength(1));
  });

  group('the import photo action', () {
    testWidgets('is absent when onImportPhoto is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DrawSheetScreen(controller: DrawingController())),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add a photo'), findsNothing);
    });

    testWidgets('calls onImportPhoto when tapped', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DrawSheetScreen(
            controller: DrawingController(),
            onImportPhoto: () => calls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Add a photo'));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('disappears once the drawing already has a backdrop', (
      tester,
    ) async {
      final controller = DrawingController(backdrop: await _tinyPng());
      await tester.pumpWidget(
        MaterialApp(
          home: DrawSheetScreen(controller: controller, onImportPhoto: () {}),
        ),
      );
      // The backdrop is decoded asynchronously in initState
      // (`draw_sheet_screen.dart`'s own `_decodeBackdrop`), so this needs
      // to settle rather than a bare pump.
      await tester.pumpAndSettle();

      expect(find.byTooltip('Add a photo'), findsNothing);
    });
  });
}
