// Shared setup for the tests that run the whole app.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.
//
// Everything here goes through a [MemorySaveStore], which holds the save as
// encoded text: a widget test therefore exercises the real codec and the real
// repository, and only the filesystem is missing.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/app.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';

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
/// isolate, in a widget test (`PLAN-phase-3.md` §4.2).
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
        ...overrides,
      ],
    ),
    child: const GameStationApp(),
  );
  addTearDown(root.container.dispose);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(root);
  await tester.pumpAndSettle();
  return root.container;
}
