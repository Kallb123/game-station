// Shared setup for the tests that run the whole app.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.
//
// Everything here goes through a [MemorySaveStore], which holds the save as
// encoded text: a widget test therefore exercises the real codec and the real
// repository, and only the filesystem is missing.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/app.dart';
import 'package:zibo_games/core/audio/app_audio.dart';
import 'package:zibo_games/core/audio/providers.dart';
import 'package:zibo_games/core/haptics.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/data/providers.dart';

/// A fixed clock, so nothing in a test depends on the day it runs.
DateTime testClock() => DateTime.utc(2026, 8, 12, 9);

/// The save a first launch would start from, with [settings] already chosen if
/// a test needs the state a relaunch would read rather than the state it can
/// reach by tapping.
SaveData freshSave({AppSettings? settings}) {
  final save = SaveData.initial(createdAt: testClock());
  return settings == null ? save : save.copyWith(settings: settings);
}

/// Starts the app over [store] and settles the first frame.
///
/// Returns the scope's container, so a test can read the repository and assert
/// what the app wrote rather than only what it drew.
///
/// [overrides] is where a test that reaches a Sudoku screen puts its
/// `puzzleSourceProvider`: without one the app generates for real, on an
/// isolate, in a widget test (`PLAN-phase-3.md` §4.2). It is also where a test
/// that asserts what would have played overrides `appAudioProvider` again,
/// with a `RecordingAudio` — the default below is a plain [SilentAudio], so no
/// widget test needs an audio device (`PLAN-phase-5.md` §4.2). `appHapticsProvider`
/// gets the same treatment with [SilentHaptics], so no widget test needs a
/// device to vibrate either (`PLAN-phase-5.md` §4.5).
///
/// Called a second time in the same test, it is a relaunch: the previous tree
/// comes down first. Without that, `pumpWidget` would update the element tree in
/// place — same root widget type — and the app would keep the navigator, and so
/// the route stack, of the run it was supposed to have replaced.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required SaveStore store,
  List<Override> overrides = const [],
}) async {
  final loaded = await store.load();
  final root = UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(loaded),
        appAudioProvider.overrideWithValue(const SilentAudio()),
        appHapticsProvider.overrideWithValue(const SilentHaptics()),
        ...overrides,
      ],
    ),
    child: const ZiboGamesApp(),
  );
  addTearDown(root.container.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(root);
  await tester.pumpAndSettle();
  return root.container;
}

/// A `drawingRepositoryProvider` override for a test that reaches the draw
/// feature, over a fresh temp directory it deletes when the test ends.
///
/// [DrawingRepository] is `dart:io`-only, unlike [SaveStore]'s
/// [MemorySaveStore] — a test that opens the gallery or the sheet has to
/// give it a real, if throwaway, directory, the same reasoning `main()`
/// gives for the fallback in its own doc comment.
Override drawTempRepositoryOverride() {
  final directory = Directory.systemTemp.createTempSync('zibo_games_draw_test');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return drawingRepositoryProvider.overrideWithValue(
    DrawingRepository(directory),
  );
}

/// Settles the fake frame clock, then gives any real `dart:io` work — a
/// drawing load, save or delete — a real slice of wall-clock time and drains
/// it back in.
///
/// A widget test's fake clock advances `Timer`s synchronously without
/// letting the real event loop run, so firing a debounced autosave starts
/// the real file write but does not wait for it: `tester.runAsync` is what
/// actually gives it time to run for real, and the `tester.pump()` after it
/// drains whatever of that completed back into the fake zone. One round is
/// not always enough for a multi-step write (`writeFileAtomically` opens,
/// writes, flushes, closes and renames), so this loops a few times rather
/// than once — every widget test that reaches the draw feature's disk needs
/// this in place of a bare `pumpAndSettle`.
Future<void> settleDrawIO(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 25)),
    );
    await tester.pump();
  }
}
