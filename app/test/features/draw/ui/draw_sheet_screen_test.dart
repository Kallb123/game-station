// [DrawSheetScreen]'s pointer handling: the §4.2 sampling rule that turns a
// dense pointer stream into a bounded stroke, and the tap-to-dot case
// (`PLAN-phase-8.md` §6, PR 2's done criteria) — plus PR 3's tool row wired
// to it: picking a size or a colour is what the next stroke draws with, and
// New sheet swaps in a blank picture without touching a caller-supplied
// controller's own strokes.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart' show PadSide;
import 'package:zibo_games/core/ui/theme.dart';
import 'package:zibo_games/core/ui/tokens.dart';
import 'package:zibo_games/features/draw/model/drawing_controller.dart';
import 'package:zibo_games/features/draw/model/palette.dart';
import 'package:zibo_games/features/draw/ui/draw_sheet_screen.dart';
import 'package:zibo_games/features/draw/ui/drawing_painter.dart';
import 'package:zibo_games/features/draw/ui/tool_row.dart';

/// Pumps and settles, then gives real async work — a real image codec's
/// isolate round trip, in particular — a real slice of wall-clock time to
/// finish and drains it back in, the same reasoning `app_harness.dart`'s
/// `settleDrawIO` gives for real disk I/O: a widget test's fake clock
/// advances `Timer`s synchronously without letting the real event loop run,
/// so a decode started under `pumpAndSettle` alone never reports back.
Future<void> _settleRealAsync(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}

/// A tiny, real, decodable PNG — enough for `DrawingController(backdrop:)`
/// to have something `decodeBackdrop` can actually decode. Encoding to PNG
/// is itself real async work, so every call site awaits it through
/// `tester.runAsync` rather than directly.
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

/// Wraps the pumped screen so [_rasterise] has a boundary to capture, and
/// puts the capture's origin at the screen's own top left — which makes the
/// image's pixel coordinates the same ones the finders report.
const _screenBoundaryKey = ValueKey<String>('screen-boundary');

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
    MaterialApp(
      home: RepaintBoundary(
        key: _screenBoundaryKey,
        child: DrawSheetScreen(controller: controller),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final topLeft = tester.getTopLeft(_canvasFinder);
  final size = tester.getSize(_canvasFinder);
  return topLeft & size;
}

/// Rasterises the whole pumped screen, so a test can ask what a child
/// actually sees rather than what the widget tree claims. Returns the pixels
/// with the row width they are laid out in, which [_pixelAt] needs and only
/// the capture itself knows.
///
/// Through `runAsync` for the same reason `_settleRealAsync` exists, and the
/// same reason `matchesGoldenFile` does it: rasterising is real work off the
/// fake clock, so a plain `await` here waits on a future the widget test's
/// zone never completes, and the test hangs rather than fails.
Future<(ByteData, int)> _rasterise(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_screenBoundaryKey),
  );
  final captured = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      return (bytes!, image.width);
    } finally {
      image.dispose();
    }
  });
  return captured!;
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

/// The paper the sheet is painted on, read off the screen's own theme rather
/// than restated here, so this stays true if the surface colour moves.
Color _paperColorOf(WidgetTester tester) =>
    Theme.of(tester.element(_canvasFinder)).colorScheme.surface;

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

  testWidgets('the sheet is framed by a border the size of the canvas itself', (
    tester,
  ) async {
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);

    final borderBox = find.ancestor(
      of: _canvasFinder,
      matching: find.byType(DecoratedBox),
    );
    expect(borderBox, findsOneWidget);
    final decoration =
        tester.widget<DecoratedBox>(borderBox).decoration as BoxDecoration;
    expect(decoration.border, isNotNull);

    // The border frames the exact sheet the child draws on, not some
    // larger chrome around it.
    final borderTopLeft = tester.getTopLeft(borderBox);
    final borderSize = tester.getSize(borderBox);
    expect(borderTopLeft, canvas.topLeft);
    expect(borderSize, canvas.size);
  });

  testWidgets('the border is actually painted, not covered by the paper', (
    tester,
  ) async {
    // A border in the tree is not a border on the screen: `DrawingPainter`
    // fills the whole canvas with the paper colour, so a decoration painted
    // behind it renders and is then covered over. Only the pixels answer
    // that, which is why this test reads them rather than the widget.
    final controller = DrawingController();
    final canvas = await _pumpAndFindCanvas(tester, controller);
    final (pixels, width) = await _rasterise(tester);

    // The same colour the screen resolves, off the same theme, rather than a
    // second copy of that derivation to keep in step with the first.
    final brightness = Theme.of(tester.element(_canvasFinder)).brightness;
    final borderColor = AppTheme.roleScheme(
      AppPalette.of(brightness).draw,
      brightness,
    ).outline;

    // One pixel inside each edge — inside the 2 dp band whichever side of a
    // whole pixel the sheet's own edge lands on.
    final y = canvas.center.dy.floor();
    final x = canvas.center.dx.floor();
    expect(
      _pixelAt(pixels, width, x: (canvas.left + 1).floor(), y: y),
      borderColor,
      reason: 'left edge',
    );
    expect(
      _pixelAt(pixels, width, x: (canvas.right - 1).floor(), y: y),
      borderColor,
      reason: 'right edge',
    );
    expect(
      _pixelAt(pixels, width, x: x, y: (canvas.top + 1).floor()),
      borderColor,
      reason: 'top edge',
    );
    expect(
      _pixelAt(pixels, width, x: x, y: (canvas.bottom - 1).floor()),
      borderColor,
      reason: 'bottom edge',
    );

    // ...and the sheet itself is still paper, so the border frames the
    // drawing area rather than tinting it.
    expect(_pixelAt(pixels, width, x: x, y: y), _paperColorOf(tester));
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
      final backdrop = await tester.runAsync(_tinyPng);
      final controller = DrawingController(backdrop: backdrop);
      await tester.pumpWidget(
        MaterialApp(
          home: DrawSheetScreen(controller: controller, onImportPhoto: () {}),
        ),
      );
      // The backdrop is decoded asynchronously in initState
      // (`draw_sheet_screen.dart`'s own `_decodeBackdrop`), so this needs
      // real settling, not just a settled fake clock.
      await _settleRealAsync(tester);

      expect(find.byTooltip('Add a photo'), findsNothing);
    });
  });

  group('the export photo action', () {
    testWidgets('is absent when onExportPhoto is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: DrawSheetScreen(controller: DrawingController())),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Save picture'), findsNothing);
    });

    testWidgets('calls onExportPhoto when tapped', (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: DrawSheetScreen(
            controller: DrawingController(),
            onExportPhoto: () => calls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Save picture'));
      await tester.pump();

      expect(calls, 1);
    });

    testWidgets('stays offered even once the drawing has a backdrop', (
      tester,
    ) async {
      // Unlike import, export has nothing to gate on the picture already
      // drawn — saving what is on screen is always a valid thing to ask for
      // (`PLAN-phase-8.md` §4.6: "export stays available either way").
      final backdrop = await tester.runAsync(_tinyPng);
      final controller = DrawingController(backdrop: backdrop);
      await tester.pumpWidget(
        MaterialApp(
          home: DrawSheetScreen(controller: controller, onExportPhoto: () {}),
        ),
      );
      await _settleRealAsync(tester);

      expect(find.byTooltip('Save picture'), findsOneWidget);
    });
  });

  group('in portrait', () {
    testWidgets('a short phone scrolls the band rather than taking the room '
        'out of the sheet', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(home: DrawSheetScreen(controller: DrawingController())),
      );
      await tester.pumpAndSettle();

      // Eighteen colours are four rows of swatches on a 360 dp-wide window,
      // and a 640 dp-tall one has no room for the fourth: the band is the
      // side that gives (`_minSheetShare`), because a canvas can be squeezed
      // and a 56 dp control cannot.
      final band = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(band.position.maxScrollExtent, greaterThan(0));

      // 160 dp is what a third of this window comes to once the header and
      // the padding have taken theirs — measured, and well above the 108 dp
      // the sheet is left with when the band takes what it likes.
      expect(
        tester.getSize(_canvasFinder).height,
        greaterThanOrEqualTo(160),
        reason: 'the sheet has been squeezed below its share',
      );

      // And the row the fold cuts off is still reachable: the swatch a child
      // scrolls to is the deepest skin tone, the last in the palette.
      await tester.drag(
        find.byKey(ToolRow.colorKey(0)),
        Offset(0, -band.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomLeft(
              find.byKey(ToolRow.colorKey(DrawPalette.colors.length - 1)),
            )
            .dy,
        lessThanOrEqualTo(640),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('in landscape', () {
    /// Pumps the sheet in a landscape window with its rail on [side].
    Future<void> pumpLandscape(WidgetTester tester, PadSide side) async {
      tester.view.physicalSize = const Size(800, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: DrawSheetScreen(controller: DrawingController(), padSide: side),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the rail sits on the side the profile names, beside the '
        'sheet rather than over it', (tester) async {
      await pumpLandscape(tester, PadSide.left);
      expect(
        tester.getTopRight(find.byType(ToolRow)).dx,
        lessThanOrEqualTo(tester.getTopLeft(_canvasFinder).dx),
      );

      await pumpLandscape(tester, PadSide.right);
      expect(
        tester.getTopLeft(find.byType(ToolRow)).dx,
        greaterThanOrEqualTo(tester.getTopRight(_canvasFinder).dx),
      );
    });

    testWidgets('a phone-sized window is within one swatch row of fitting, '
        'and every control is reachable', (tester) async {
      await pumpLandscape(tester, PadSide.right);

      // Two rows of six colours used to fit a 400 dp-tall window exactly.
      // The six skin tones cost a third row (`palette.dart`), and the rail's
      // scroll view — there since the panel was written, for windows shorter
      // than this one — carries the overhang. Asserted as under one row
      // rather than as a number: at most one row of swatches is then out of
      // view, and never a control that is not a colour.
      final rail = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(
        rail.position.maxScrollExtent,
        lessThan(AppTapTargets.min + AppSpacing.sm),
        reason: 'the rail overhangs a 400 dp window by more than a row',
      );

      // Six swatches wide, so the last row is the skin tones, and scrolling
      // to it brings the deepest of them fully into the window.
      expect(tester.getSize(find.byType(ToolRow)).width, ToolRow.railWidth);
      await tester.drag(
        find.byKey(ToolRow.colorKey(0)),
        Offset(0, -rail.position.maxScrollExtent),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .getBottomLeft(
              find.byKey(ToolRow.colorKey(DrawPalette.colors.length - 1)),
            )
            .dy,
        lessThanOrEqualTo(400),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
