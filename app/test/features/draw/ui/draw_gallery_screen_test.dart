// [DrawGalleryScreen]'s own rules: New sheet is always the first tile,
// drawings sort newest first, a delete needs a confirmation and updates
// `bytesUsed`, and a corrupted file is missing from the grid without taking
// the rest of it down (`PLAN-phase-8.md` §6, PR 4's done criteria) — plus
// what a thumbnail shows of an imported photo, which is the screen's own
// decode rather than anything PR 4 shipped.
//
// Reached through the whole app, the same way `resume_test.dart` is: the
// gallery pushes a named route to open a drawing, which a bare `pumpWidget`
// has no table for. Every direct `DrawingRepository` call here runs inside
// `tester.runAsync` — a widget test's ambient zone fakes `Timer` and
// `scheduleMicrotask`, so a real `dart:io` future awaited outside of one
// never resolves; `settleDrawIO` (`app_harness.dart`) is the same fix for
// I/O the app itself starts, from inside a widget's own `Timer` callback.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/data/providers.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';
import 'package:zibo_games/features/draw/ui/drawing_painter.dart';

import '../../../app_harness.dart';

final Finder _thumbnailFinder = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is DrawingPainter,
);

Stroke _stroke() =>
    const Stroke(colorIndex: 0, sizeIndex: 0, points: [Offset(4, 4)]);

/// The [DrawingPainter] of every thumbnail, in grid order.
List<DrawingPainter> _painters(WidgetTester tester) => tester
    .widgetList<CustomPaint>(_thumbnailFinder)
    .map((paint) => paint.painter! as DrawingPainter)
    .toList();

/// A real, decodable PNG of [width] x [height] — the shape a stored backdrop
/// has, since `photo_import.dart` re-encodes every import as one. Encoding is
/// real async work, so every call site runs it through `tester.runAsync`.
Future<Uint8List> _solidPng(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..color = const Color(0xFF00AA55),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Rasterises the only thumbnail on screen and returns its pixels with the row
/// width [_pixelAt] needs.
///
/// `GridView` wraps each of its children in a repaint boundary
/// (`addRepaintBoundaries` defaults to true) and `find.ancestor` walks
/// outwards, so the first match above the thumbnail is that one tile and
/// nothing wider — no key of this test's own has to be threaded through the
/// app to capture it. Through `runAsync` for the reason `settleDrawIO` exists:
/// rasterising is real work off the fake clock.
Future<(ByteData, int)> _rasteriseThumbnail(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find
        .ancestor(of: _thumbnailFinder, matching: find.byType(RepaintBoundary))
        .first,
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

Drawing _drawing(String id, DateTime createdAt, int strokeCount) => Drawing(
  id: id,
  createdAt: createdAt,
  strokes: List.generate(strokeCount, (_) => _stroke()),
);

void main() {
  late Directory tempDir;
  late DrawingRepository repository;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('zibo_games_gallery_test');
    repository = DrawingRepository(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Writes [drawing] under [profileId] for real, before any widget exists
  /// to pump a fake clock — see this file's own doc comment for why that
  /// needs `runAsync`.
  Future<void> seed(WidgetTester tester, String profileId, Drawing drawing) =>
      tester.runAsync(() => repository.save(profileId, drawing));

  Future<ProviderContainer> openGallery(
    WidgetTester tester,
    SaveStore store,
  ) async {
    final container = await pumpApp(
      tester,
      store: store,
      overrides: [drawingRepositoryProvider.overrideWithValue(repository)],
    );
    await tester.tap(find.text('Draw'));
    await settleDrawIO(tester);
    return container;
  }

  testWidgets('New sheet is the first tile even with no drawings yet', (
    tester,
  ) async {
    await openGallery(tester, MemorySaveStore(initial: freshSave()));

    expect(find.bySemanticsLabel('New sheet'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Drawing, made')), findsNothing);
  });

  testWidgets('drawings are shown newest first', (tester) async {
    await seed(tester, 'p1', _drawing('d1', DateTime.utc(2026, 1, 1), 1));
    // A different profile's drawing must never show here, even sharing an id.
    await seed(tester, 'p2', _drawing('d1', DateTime.utc(2026, 1, 5), 9));
    await seed(tester, 'p1', _drawing('d2', DateTime.utc(2026, 1, 3), 2));
    await seed(tester, 'p1', _drawing('d3', DateTime.utc(2026, 1, 5), 3));

    await openGallery(tester, MemorySaveStore(initial: freshSave()));

    // The New sheet tile paints nothing through `DrawingPainter`, so every
    // match here is one of this profile's three drawings, in grid order.
    final strokeCounts = tester
        .widgetList<CustomPaint>(_thumbnailFinder)
        .map((paint) => (paint.painter! as DrawingPainter).liveStrokes.length)
        .toList();
    expect(
      strokeCounts,
      [3, 2, 1],
      reason: 'd3 (newest) first, d1 (oldest) last, and p2’s d1 is absent',
    );
  });

  testWidgets(
    'opening a drawing and coming back shows it updated in the gallery',
    (tester) async {
      await seed(tester, 'p1', _drawing('d1', DateTime.utc(2026, 1, 1), 1));

      await openGallery(tester, MemorySaveStore(initial: freshSave()));
      expect(
        (tester.widgetList<CustomPaint>(_thumbnailFinder).single.painter!
                as DrawingPainter)
            .liveStrokes,
        hasLength(1),
      );

      await tester.tap(find.bySemanticsLabel(RegExp('^Drawing, made')));
      await settleDrawIO(tester);

      // Adds a second stroke to the reopened drawing and lets it autosave.
      final canvas =
          tester.getTopLeft(_thumbnailFinder) &
          tester.getSize(_thumbnailFinder);
      await tester.tapAt(canvas.center);
      await tester.pump(const Duration(milliseconds: 600));
      await settleDrawIO(tester);

      await tester.tap(find.byTooltip('Back'));
      await settleDrawIO(tester);

      expect(
        (tester.widgetList<CustomPaint>(_thumbnailFinder).single.painter!
                as DrawingPainter)
            .liveStrokes,
        hasLength(2),
        reason: 'the reload after popping shows the drawing as it now is',
      );
    },
  );

  testWidgets('a long press asks before deleting, and Keep changes nothing', (
    tester,
  ) async {
    await seed(tester, 'p1', _drawing('d1', DateTime.utc(2026, 1, 1), 1));
    await openGallery(tester, MemorySaveStore(initial: freshSave()));

    await tester.longPress(find.bySemanticsLabel(RegExp('^Drawing, made')));
    await tester.pumpAndSettle();
    expect(find.text('Delete this drawing?'), findsOneWidget);

    await tester.tap(find.text('Keep'));
    await settleDrawIO(tester);

    expect(find.bySemanticsLabel(RegExp('^Drawing, made')), findsOneWidget);
    final stillThere = await tester.runAsync(() => repository.load('p1', 'd1'));
    expect(stillThere, isNotNull);
  });

  testWidgets(
    'confirming a delete removes the file and drops it from bytesUsed',
    (tester) async {
      await seed(tester, 'p1', _drawing('d1', DateTime.utc(2026, 1, 1), 1));
      final store = MemorySaveStore(initial: freshSave());
      final container = await openGallery(tester, store);
      container
          .read(progressRepositoryProvider)
          .recordDrawingSaved(
            drawingId: 'd1',
            isNew: true,
            totalBytes: repository.profileBytes('p1'),
          );

      await tester.longPress(find.bySemanticsLabel(RegExp('^Drawing, made')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await settleDrawIO(tester);

      expect(find.bySemanticsLabel(RegExp('^Drawing, made')), findsNothing);
      final gone = await tester.runAsync(() => repository.load('p1', 'd1'));
      expect(gone, isNull);
      expect(
        container.read(progressRepositoryProvider).activeProfile.draw.bytesUsed,
        0,
      );
      // Lands the `save.json` write `recordDrawingSaved`/`recordDrawingDeleted`
      // scheduled — otherwise it fires after the tree comes down and the
      // binding's own pending-timer check fails the test on its own.
      await container.read(progressRepositoryProvider).flush();
    },
  );

  testWidgets('an imported photo shows in the thumbnail, decoded smaller', (
    tester,
  ) async {
    final photo = (await tester.runAsync(() => _solidPng(900, 600)))!;
    await seed(
      tester,
      'p1',
      Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026, 1, 1),
        strokes: [_stroke()],
        backdrop: photo,
      ),
    );
    await seed(tester, 'p1', _drawing('d2', DateTime.utc(2026, 1, 2), 1));

    await openGallery(tester, MemorySaveStore(initial: freshSave()));

    // d2 is the newer of the two, so it is the first tile, and it has no
    // photo to show.
    final painters = _painters(tester);
    expect(painters.first.backdrop, isNull);

    final shown = painters.last.backdrop;
    expect(shown, isNotNull, reason: 'd1’s photo is part of its thumbnail');
    expect(
      shown!.sheetSize,
      const Size(900, 600),
      reason:
          'the sheet-space placement is the stored size, so the '
          'thumbnail crops and centres the photo the way the sheet does',
    );
    expect(
      Size(shown.image.width.toDouble(), shown.image.height.toDouble()),
      const Size(300, 200),
      reason:
          'a third of the stored resolution: a tile cannot show more, '
          'and the full photo would be 9 times the pixels in memory',
    );
  });

  testWidgets('the photo is what a tile paints, not only what it holds', (
    tester,
  ) async {
    // The pixels, not the painter's arguments: a decoded photo that reached
    // the tile but landed in the wrong rectangle, or behind the paper, is
    // still a thumbnail a child cannot recognise their drawing in.
    const photoColor = Color(0xFF00AA55);
    final photo = (await tester.runAsync(() => _solidPng(900, 600)))!;
    await seed(
      tester,
      'p1',
      Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026, 1, 1),
        strokes: [_stroke()],
        backdrop: photo,
      ),
    );

    await openGallery(tester, MemorySaveStore(initial: freshSave()));
    final (pixels, width) = await _rasteriseThumbnail(tester);
    final height = pixels.lengthInBytes ~/ 4 ~/ width;

    expect(
      _pixelAt(pixels, width, x: width ~/ 2, y: height ~/ 2),
      photoColor,
      reason: 'the middle of the tile is the middle of the photo',
    );
    // 900 x 600 of the sheet's 1600 x 1200 leaves paper around the photo, so a
    // tile painted entirely in the photo's colour would mean it had been
    // stretched to fill rather than centred at its stored size.
    expect(_pixelAt(pixels, width, x: 2, y: height ~/ 2), isNot(photoColor));
  });

  testWidgets('a photo that will not decode leaves the strokes showing', (
    tester,
  ) async {
    await seed(
      tester,
      'p1',
      Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026, 1, 1),
        strokes: [_stroke()],
        // Not an image at all: a truncated write, or a file edited by hand.
        backdrop: Uint8List.fromList([1, 2, 3, 4]),
      ),
    );

    await openGallery(tester, MemorySaveStore(initial: freshSave()));

    expect(find.bySemanticsLabel(RegExp('^Drawing, made')), findsOneWidget);
    final painter = _painters(tester).single;
    expect(painter.backdrop, isNull);
    expect(
      painter.liveStrokes,
      hasLength(1),
      reason: 'the drawing still shows',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a delete keeps the photo of the drawing that survives it', (
    tester,
  ) async {
    // The reload after a delete disposes the decoded photos of drawings that
    // are gone, and has to leave the rest alone: dropping one that is still
    // listed costs a second decode of a picture the screen already has, and
    // disposing one still in the map leaves a tile painting a disposed
    // `ui.Image`, which throws out of the paint phase. The same decoded
    // instance being there afterwards rules out both.
    final photo = (await tester.runAsync(() => _solidPng(900, 600)))!;
    await seed(
      tester,
      'p1',
      Drawing(
        id: 'd1',
        createdAt: DateTime.utc(2026, 1, 1),
        strokes: [_stroke()],
        backdrop: photo,
      ),
    );
    await seed(tester, 'p1', _drawing('d2', DateTime.utc(2026, 1, 2), 1));

    final container = await openGallery(
      tester,
      MemorySaveStore(initial: freshSave()),
    );
    final decoded = _painters(tester).last.backdrop;
    expect(decoded, isNotNull);

    // d2, the newer and photo-less one, is the first drawing tile.
    await tester.longPress(
      find.bySemanticsLabel(RegExp('^Drawing, made')).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settleDrawIO(tester);

    expect(
      _painters(tester).single.backdrop,
      same(decoded),
      reason: 'd1’s photo is neither disposed nor decoded a second time',
    );
    expect(tester.takeException(), isNull);
    await container.read(progressRepositoryProvider).flush();
  });

  testWidgets(
    'a drawing corrupted on purpose is missing from the grid, with no '
    'error card',
    (tester) async {
      await seed(tester, 'p1', _drawing('d1', DateTime.utc(2026, 1, 1), 1));
      await tester.runAsync(
        () async => File(
          '${tempDir.path}/drawings/p1/d2.json',
        ).writeAsStringSync('{not valid json'),
      );

      await openGallery(tester, MemorySaveStore(initial: freshSave()));

      expect(find.bySemanticsLabel(RegExp('^Drawing, made')), findsOneWidget);
      expect(find.textContaining('error', findRichText: true), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
