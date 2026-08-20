// Phase 8's own version of `features/sudoku/resume_test.dart`: a drawing
// survives a rebuild of the app from disk, over the real codec and the real
// repository — not just an in-memory hand-off (`PLAN-phase-8.md` §6, PR 4's
// done criteria).
//
// `save.json` lives in a [MemorySaveStore], the same as every other widget
// test, but a drawing cannot: [DrawingRepository] is `dart:io`-only, so this
// test gives it one real temp directory and reuses it across both launches,
// the same way the Sudoku test reuses one [MemorySaveStore]. `settleDrawIO`
// (`app_harness.dart`) is what waits for the real writes and reads that
// happen along the way — see its own doc comment for why a bare
// `pumpAndSettle` is not enough.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/data/providers.dart';
import 'package:zibo_games/features/draw/ui/drawing_painter.dart';

import '../../app_harness.dart';

final Finder _canvasFinder = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is DrawingPainter,
);

/// The sheet's canvas rect, in the test's coordinate space — the same finder
/// `draw_sheet_screen_test.dart` uses for the pure widget, reached here
/// through the whole app's navigation instead of a bare `pumpWidget`.
Rect _canvasRect(WidgetTester tester) {
  final topLeft = tester.getTopLeft(_canvasFinder);
  final size = tester.getSize(_canvasFinder);
  return topLeft & size;
}

/// Home, then the Draw card, as a child reaches it.
Future<void> _openGallery(WidgetTester tester) async {
  await tester.tap(find.text('Draw'));
  await settleDrawIO(tester);
}

void main() {
  testWidgets('a force-quit after drawing brings the same picture back', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tempDir = Directory.systemTemp.createTempSync(
      'zibo_games_draw_resume_test',
    );
    addTearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final repository = DrawingRepository(tempDir);
    final overrides = [drawingRepositoryProvider.overrideWithValue(repository)];

    final store = MemorySaveStore(initial: freshSave());
    await pumpApp(tester, store: store, overrides: overrides);
    await _openGallery(tester);

    await tester.tap(find.bySemanticsLabel('New sheet'));
    await settleDrawIO(tester);
    expect(_canvasFinder, findsOneWidget);

    // Two taps, two dots — a stroke each, and each a fact about the picture
    // that a resume must not lose.
    final canvas = _canvasRect(tester);
    await tester.tapAt(canvas.topLeft + const Offset(40, 40));
    await tester.pump();
    await tester.tapAt(canvas.bottomRight - const Offset(40, 40));
    await tester.pump();

    // Past the 500 ms autosave debounce (`draw_sheet_screen.dart`'s
    // `drawAutosaveDebounce`), which fires the (faked) `Timer` and starts
    // the real write — `settleDrawIO` is what actually waits for it.
    await tester.pump(const Duration(milliseconds: 600));
    await settleDrawIO(tester);

    final beforeFiles = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();
    expect(
      beforeFiles,
      hasLength(1),
      reason: 'the autosave landed on disk before the force-quit',
    );

    // The force-quit: every step, because `AppLifecycleListener` asserts on
    // a state change that skips one, the same as the Sudoku test.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settleDrawIO(tester);

    // The relaunch: brought back to `resumed` first, the same reasoning the
    // Sudoku test gives — a relaunch is a new process, and the test binding
    // draws no frames while the app is paused.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    await pumpApp(tester, store: store, overrides: overrides);
    await _openGallery(tester);

    // One tile for the new drawing, plus the New sheet tile.
    expect(find.bySemanticsLabel(RegExp('^Drawing, made')), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Drawing, made')));
    await settleDrawIO(tester);

    final painter =
        tester.widgetList<CustomPaint>(_canvasFinder).single.painter!
            as DrawingPainter;
    expect(
      painter.liveStrokes,
      hasLength(2),
      reason: 'both dots survived the round trip through disk',
    );
  });
}
