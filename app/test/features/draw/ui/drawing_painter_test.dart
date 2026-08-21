// [DrawingPainter], tested against `TestRecordingCanvas` rather than a
// widget tree or a golden image: `matchesGoldenFile` differs between Skia and
// Impeller and between platforms, so a golden here would fail on somebody's
// machine for a reason that is not the code (`PLAN-phase-8.md` §4.3). This is
// PR 2's own done-criterion list: at most 51 strokes plus one image on a
// 500-stroke drawing, a tap painting a circle, and no repaint on a rebuild
// that changed nothing.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';
import 'package:zibo_games/features/draw/ui/drawing_painter.dart';

const Color _paperColor = Color(0xFFFFFFFF);

Color _colorOf(int colorIndex) => const Color(0xFF3A66C4);

double _widthOf(int sizeIndex) => 16;

/// A real [ui.Image] of [width] x [height] — the painter only ever passes it
/// to `drawImageRect` without reading its pixels, so its content does not
/// matter.
Future<ui.Image> _tinyImage({int width = 1, int height = 1}) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    Uint8List(width * height * 4),
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// A backdrop whose decoded image is [width] x [height] pixels and which
/// stands for [sheetSize] sheet units — the two differ for a gallery
/// thumbnail, which decodes the photo at a fraction of its stored size
/// (`draw_gallery_screen.dart`).
Future<SheetBackdrop> _backdrop({
  int width = 1,
  int height = 1,
  Size? sheetSize,
}) async => SheetBackdrop(
  image: await _tinyImage(width: width, height: height),
  sheetSize: sheetSize ?? Size(width.toDouble(), height.toDouble()),
);

Stroke _tap(double x) =>
    Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset(x, 0)]);

Stroke _drag(double x) => Stroke(
  colorIndex: 0,
  sizeIndex: 0,
  points: [Offset(x, 0), Offset(x + 10, 0), Offset(x + 20, 0)],
);

DrawingPainter _painter({
  ui.Image? baked,
  SheetBackdrop? backdrop,
  List<Stroke> liveStrokes = const [],
  Stroke? current,
}) => DrawingPainter(
  baked: baked,
  backdrop: backdrop,
  liveStrokes: liveStrokes,
  current: current,
  paperColor: _paperColor,
  colorOf: _colorOf,
  widthOf: _widthOf,
);

Iterable<RecordedInvocation> _calls(TestRecordingCanvas canvas, Symbol name) =>
    canvas.invocations.where((call) => call.invocation.memberName == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a 500-stroke drawing paints at most 51 strokes plus one image',
    () async {
      final baked = await _tinyImage();
      final liveStrokes = List.generate(50, (i) => _drag(i.toDouble()));
      final canvas = TestRecordingCanvas();

      _painter(
        baked: baked,
        liveStrokes: liveStrokes,
        current: _tap(999),
      ).paint(canvas, const Size(1600, 1200));

      final strokeCalls =
          _calls(canvas, #drawPath).length + _calls(canvas, #drawCircle).length;
      expect(strokeCalls, 51);
      expect(_calls(canvas, #drawImageRect).length, 1);
    },
  );

  test('nothing baked yet paints no image, only strokes', () {
    final canvas = TestRecordingCanvas();

    _painter(
      liveStrokes: [_drag(0), _drag(1)],
    ).paint(canvas, const Size(1600, 1200));

    expect(_calls(canvas, #drawImageRect), isEmpty);
    expect(_calls(canvas, #drawPath).length, 2);
  });

  test('a one-point stroke paints a circle, not a path', () {
    final canvas = TestRecordingCanvas();

    _painter(current: _tap(5)).paint(canvas, const Size(1600, 1200));

    expect(_calls(canvas, #drawCircle).length, 1);
    expect(_calls(canvas, #drawPath), isEmpty);
  });

  test('the paper is painted before an eraser stroke, which clears it', () {
    final eraser = Stroke(
      colorIndex: Stroke.eraserColorIndex,
      sizeIndex: 0,
      points: const [Offset(0, 0), Offset(10, 0)],
    );
    final canvas = TestRecordingCanvas();

    _painter(current: eraser).paint(canvas, const Size(1600, 1200));

    final paperIndex = canvas.invocations.indexWhere(
      (call) => call.invocation.memberName == #drawRect,
    );
    final eraseIndex = canvas.invocations.indexWhere(
      (call) => call.invocation.memberName == #drawPath,
    );
    expect(paperIndex, greaterThanOrEqualTo(0));
    expect(eraseIndex, greaterThan(paperIndex));

    final paint =
        canvas.invocations[eraseIndex].invocation.positionalArguments[1]
            as Paint;
    expect(paint.blendMode, BlendMode.clear);
  });

  test('shouldRepaint is false when nothing that matters changed', () async {
    final baked = await _tinyImage();
    final before = _painter(
      baked: baked,
      liveStrokes: [_drag(0), _drag(1)],
      current: _drag(2),
    );
    // Different stroke content, same lengths — shouldRepaint compares counts
    // and identity, not the strokes themselves (`PLAN-phase-8.md` §4.3).
    final after = _painter(
      baked: baked,
      liveStrokes: [_drag(9), _drag(9)],
      current: _drag(2),
    );

    expect(after.shouldRepaint(before), isFalse);
  });

  test('shouldRepaint is true when the baked image changes', () async {
    final before = _painter(baked: await _tinyImage());
    final after = _painter(baked: await _tinyImage());

    expect(after.shouldRepaint(before), isTrue);
  });

  test('shouldRepaint is true when the live stroke count changes', () {
    final before = _painter(liveStrokes: [_drag(0)]);
    final after = _painter(liveStrokes: [_drag(0), _drag(1)]);

    expect(after.shouldRepaint(before), isTrue);
  });

  test('a backdrop is drawn before the baked image, once', () async {
    final backdrop = await _backdrop();
    final baked = await _tinyImage();
    final canvas = TestRecordingCanvas();

    _painter(
      backdrop: backdrop,
      baked: baked,
    ).paint(canvas, const Size(1600, 1200));

    final imageIndices = canvas.invocations
        .asMap()
        .entries
        .where((entry) => entry.value.invocation.memberName == #drawImageRect)
        .map((entry) => entry.key)
        .toList();
    expect(imageIndices, hasLength(2), reason: 'the backdrop, then the bake');
    expect(imageIndices[0], lessThan(imageIndices[1]));
  });

  test('no backdrop draws no extra image', () {
    final canvas = TestRecordingCanvas();

    _painter().paint(canvas, const Size(1600, 1200));

    expect(_calls(canvas, #drawImageRect), isEmpty);
  });

  test('shouldRepaint is true when the backdrop changes', () async {
    final before = _painter(backdrop: await _backdrop());
    final after = _painter(backdrop: await _backdrop());

    expect(after.shouldRepaint(before), isTrue);
  });

  test('a backdrop decoded smaller than it was stored still fills its own '
      'sheet rectangle', () async {
    // What a gallery thumbnail hands the painter: a third of the photo's
    // pixels, standing for the full 1200 x 900 the sheet stored it at. The
    // destination rectangle has to come from that stored size and not from
    // the decoded image, or a thumbnail would show the photo at a third of
    // the size the sheet and the export show it in
    // (`draw_gallery_screen.dart`, `png_export.dart`).
    final canvas = TestRecordingCanvas();

    _painter(
      backdrop: await _backdrop(
        width: 400,
        height: 300,
        sheetSize: const Size(1200, 900),
      ),
    ).paint(canvas, const Size(1600, 1200));

    final call = _calls(canvas, #drawImageRect).single.invocation;
    expect(
      call.positionalArguments[1],
      const Rect.fromLTWH(0, 0, 400, 300),
      reason: 'the whole decoded image is the source',
    );
    expect(
      call.positionalArguments[2],
      const Rect.fromLTWH(200, 150, 1200, 900),
      reason: 'centered at its stored size, not at its decoded one',
    );
  });

  test('shouldRepaint is true when the live stroke grows a point', () {
    final before = _painter(
      current: const Stroke(
        colorIndex: 0,
        sizeIndex: 0,
        points: [Offset(0, 0)],
      ),
    );
    final after = _painter(
      current: const Stroke(
        colorIndex: 0,
        sizeIndex: 0,
        points: [Offset(0, 0), Offset(1, 0)],
      ),
    );

    expect(after.shouldRepaint(before), isTrue);
  });
}
