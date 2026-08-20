// [DrawGalleryScreen]'s own rules: New sheet is always the first tile,
// drawings sort newest first, a delete needs a confirmation and updates
// `bytesUsed`, and a corrupted file is missing from the grid without taking
// the rest of it down (`PLAN-phase-8.md` §6, PR 4's done criteria).
//
// Reached through the whole app, the same way `resume_test.dart` is: the
// gallery pushes a named route to open a drawing, which a bare `pumpWidget`
// has no table for. Every direct `DrawingRepository` call here runs inside
// `tester.runAsync` — a widget test's ambient zone fakes `Timer` and
// `scheduleMicrotask`, so a real `dart:io` future awaited outside of one
// never resolves; `settleDrawIO` (`app_harness.dart`) is the same fix for
// I/O the app itself starts, from inside a widget's own `Timer` callback.

import 'dart:io';

import 'package:flutter/material.dart';
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
