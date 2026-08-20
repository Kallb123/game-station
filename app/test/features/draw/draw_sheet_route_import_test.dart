// [DrawSheetRoute]'s own gating over the import action — both
// `settings.allowPhotoImport` and the picker's own `available` have to say
// yes (`PLAN-phase-8.md` §6 PR 6's own done-criterion: "the import control
// is absent when `allowPhotoImport` is false and when the channel reports
// unavailable, asserted with a fake channel").
//
// The fake here is [PhotoImport] itself, overridden through
// `photoImportProvider`, rather than a mocked `MethodChannel` —
// `photo_import_test.dart` already covers `ChannelPhotoImport` reading a
// fake channel; what this file is testing is `DrawSheetRoute`'s own gating
// logic sitting above that channel.
//
// **Not tested here: tapping the action through to a saved backdrop.**
// `setBackdrop` (`DrawingController`) starts a real image-codec decode
// (`DrawSheetScreen._decodeBackdrop`) the moment a picked photo lands, and a
// widget test that also needs `tester.runAsync` afterward for the
// autosave's real disk write — to drain the debounce Timer's write through
// `DrawingRepository` — deadlocks outright rather than merely running slow:
// `runAsync` cannot coexist with an independently-pending real `Future`
// from the codec's own isolate round trip. Every piece of this path is
// covered on its own instead: `draw_sheet_screen_test.dart`'s "disappears
// once the drawing already has a backdrop" exercises the same real decode
// in isolation and settles cleanly; "calls onImportPhoto when tapped"
// proves a tap reaches the callback; `drawing_controller_test.dart`'s
// backdrop group proves `setBackdrop`/`takeNewBackdrop`; and
// `resume_test.dart` proves the autosave-to-disk path for a stroke. The
// full assembly — tap, pick, decode, persist, all through the real app — is
// left to PR 7's device pass, the same gap `PLAN-phase-8.md` §7 already
// names for the native picker itself.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/photo_import.dart';
import 'package:zibo_games/features/draw/data/providers.dart';

import '../../app_harness.dart';

class _FakePhotoImport implements PhotoImport {
  _FakePhotoImport({this.availableAnswer = true});

  final bool availableAnswer;

  @override
  Future<bool> get available async => availableAnswer;

  @override
  Future<Uint8List?> pick() async =>
      throw UnimplementedError('not exercised — see this file\'s own header');
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

  testWidgets('shown when both allowPhotoImport and the picker are true', (
    tester,
  ) async {
    await setViewport(tester);
    final overrides = [
      drawTempRepositoryOverride(),
      photoImportProvider.overrideWithValue(
        _FakePhotoImport(availableAnswer: true),
      ),
    ];
    await pumpApp(
      tester,
      store: MemorySaveStore(
        initial: freshSave(settings: const AppSettings(allowPhotoImport: true)),
      ),
      overrides: overrides,
    );

    await _openNewSheet(tester);

    expect(find.byTooltip('Add a photo'), findsOneWidget);
  });
}
