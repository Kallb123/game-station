// [DrawSheetRoute]'s own gating over the import action — both
// `settings.allowPhotoImport` and the picker's own `available` have to say
// yes — and the round trip of a picked backdrop through the autosave into
// [DrawingRepository] (`PLAN-phase-8.md` §6 PR 6's own done-criteria: "the
// import control is absent when `allowPhotoImport` is false and when the
// channel reports unavailable, asserted with a fake channel").
//
// The fake here is [PhotoImport] itself, overridden through
// `photoImportProvider`, rather than a mocked `MethodChannel` —
// `photo_import_test.dart` already covers `ChannelPhotoImport` reading a
// fake channel; what this file is testing is `DrawSheetRoute`'s own gating
// and persistence logic sitting above that channel.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/photo_import.dart';
import 'package:zibo_games/features/draw/data/providers.dart';

import '../../app_harness.dart';

class _FakePhotoImport implements PhotoImport {
  _FakePhotoImport({this.availableAnswer = true, this.pickAnswer});

  final bool availableAnswer;
  final Uint8List? pickAnswer;
  int pickCalls = 0;

  @override
  Future<bool> get available async => availableAnswer;

  @override
  Future<Uint8List?> pick() async {
    pickCalls++;
    return pickAnswer;
  }
}

/// A tiny, real, decodable PNG — what a picked photo has to be for
/// `downscaleToSheet`'s caller, `DrawingController.setBackdrop` and the
/// codec round trip to all have something real to work with.
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

Future<void> _openNewSheet(WidgetTester tester) async {
  await tester.tap(find.text('Draw'));
  await settleDrawIO(tester);
  await tester.tap(find.bySemanticsLabel('New sheet'));
  await settleDrawIO(tester);
}

void main() {
  // A fixed, generous viewport, the same as `resume_test.dart` and
  // `draw_sheet_screen_test.dart` use for the sheet.
  Future<void> setViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'absent when allowPhotoImport is off, even though the picker is available',
    (tester) async {
      await setViewport(tester);
      final overrides = [
        drawTempRepositoryOverride(),
        photoImportProvider.overrideWithValue(_FakePhotoImport()),
      ];
      await pumpApp(
        tester,
        // The default: allowPhotoImport is false (`save_data.dart`).
        store: MemorySaveStore(initial: freshSave()),
        overrides: overrides,
      );

      await _openNewSheet(tester);

      expect(find.byTooltip('Add a photo'), findsNothing);
    },
  );

  testWidgets(
    'absent when the picker reports itself unavailable, even with the '
    'setting on',
    (tester) async {
      await setViewport(tester);
      final overrides = [
        drawTempRepositoryOverride(),
        photoImportProvider.overrideWithValue(
          _FakePhotoImport(availableAnswer: false),
        ),
      ];
      await pumpApp(
        tester,
        store: MemorySaveStore(
          initial: freshSave(
            settings: const AppSettings(allowPhotoImport: true),
          ),
        ),
        overrides: overrides,
      );

      await _openNewSheet(tester);

      expect(find.byTooltip('Add a photo'), findsNothing);
    },
  );

  testWidgets(
    'shown when both say yes, and a pick lands on disk as the backdrop',
    (tester) async {
      await setViewport(tester);
      // Encoding a PNG is real async work — an isolate round trip a bare
      // `await` never reports back from inside a widget test's fake clock
      // (`draw_sheet_screen_test.dart`'s own `_settleRealAsync` gives the
      // full reasoning).
      final photoBytes = await tester.runAsync(_tinyPng);
      final fake = _FakePhotoImport(
        availableAnswer: true,
        pickAnswer: photoBytes,
      );
      final overrides = [
        drawTempRepositoryOverride(),
        photoImportProvider.overrideWithValue(fake),
      ];
      final store = MemorySaveStore(
        initial: freshSave(settings: const AppSettings(allowPhotoImport: true)),
      );
      final container = await pumpApp(
        tester,
        store: store,
        overrides: overrides,
      );

      await _openNewSheet(tester);
      expect(find.byTooltip('Add a photo'), findsOneWidget);

      await tester.tap(find.byTooltip('Add a photo'));
      await settleDrawIO(tester);

      expect(fake.pickCalls, 1);
      expect(
        find.byTooltip('Add a photo'),
        findsNothing,
        reason: 'nothing left to import over the backdrop that just landed',
      );

      // Past the autosave debounce, and settled for real disk I/O.
      await tester.pump(const Duration(milliseconds: 600));
      await settleDrawIO(tester);

      final repository = container.read(drawingRepositoryProvider);
      final profileId = container.read(activeProfileProvider).id;
      final drawings = await repository.listDecodable(profileId);

      expect(drawings, hasLength(1));
      expect(
        drawings.single.backdrop,
        isNotNull,
        reason: 'a backdrop alone, with no stroke yet, is still worth saving',
      );
    },
  );
}
