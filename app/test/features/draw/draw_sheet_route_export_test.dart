// [DrawSheetRoute]'s own gating over the export action — whether
// `GalleryExport.available` says yes. Export has no setting to gate on the
// way import does (`draw_sheet_route_import_test.dart`'s own tests): it is
// offered whenever the platform has somewhere to save to
// (`PLAN-phase-8.md` §4.6: "export stays available either way").
//
// This exists because a device pass surfaced that PR 5 built the whole
// export pipeline — `png_export.dart`, `GalleryExport`, the `gal` dependency —
// without ever wiring a button to it; export was invisible on a real build.
//
// **Not tested here: tapping the action through to a saved file.**
// `_exportPhoto` calls the real `exportDrawingToPng`, which does real
// image-codec encoding — the same isolate round trip
// `draw_sheet_route_import_test.dart`'s own header explains deadlocks a
// `testWidgets` test that also tries to settle afterward. `draw_sheet_screen_test.dart`'s
// "calls onExportPhoto when tapped" proves a tap reaches the callback, and
// `png_export_test.dart` proves the encode itself.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/gallery_export.dart';
import 'package:zibo_games/features/draw/data/providers.dart';

import '../../app_harness.dart';

class _FakeGalleryExport implements GalleryExport {
  _FakeGalleryExport({this.availableAnswer = true});

  final bool availableAnswer;

  @override
  Future<bool> get available async => availableAnswer;

  @override
  Future<void> savePng(Uint8List bytes, String name) async =>
      throw UnimplementedError('not exercised — see this file\'s own header');
}

Future<void> _openNewSheet(WidgetTester tester) async {
  await tester.tap(find.text('Draw'));
  await settleDrawIO(tester);
  await tester.tap(find.bySemanticsLabel('New sheet'));
  await settleDrawIO(tester);
}

void main() {
  // A fixed, generous viewport, the same as `draw_sheet_route_import_test.dart`.
  Future<void> setViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('shown once the platform answers available', (tester) async {
    await setViewport(tester);
    final overrides = [
      drawTempRepositoryOverride(),
      galleryExportProvider.overrideWithValue(_FakeGalleryExport()),
    ];
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: overrides,
    );

    await _openNewSheet(tester);

    expect(find.byTooltip('Save picture'), findsOneWidget);
  });

  testWidgets('absent when the platform reports itself unavailable', (
    tester,
  ) async {
    await setViewport(tester);
    final overrides = [
      drawTempRepositoryOverride(),
      galleryExportProvider.overrideWithValue(
        _FakeGalleryExport(availableAnswer: false),
      ),
    ];
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: overrides,
    );

    await _openNewSheet(tester);

    expect(find.byTooltip('Save picture'), findsNothing);
  });
}
