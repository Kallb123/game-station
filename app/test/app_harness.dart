// Shared setup for the tests that run the whole app.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.
//
// Everything here goes through a [MemorySaveStore], which holds the save as
// encoded text: a widget test therefore exercises the real codec and the real
// repository, and only the filesystem is missing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/app.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';

/// A fixed clock, so nothing in a test depends on the day it runs.
DateTime testClock() => DateTime.utc(2026, 8, 12, 9);

/// The save a first launch would start from.
SaveData freshSave() => SaveData.initial(createdAt: testClock());

/// Starts the app over [store] and settles the first frame.
///
/// Returns the scope's container, so a test can read the repository and assert
/// what the app wrote rather than only what it drew.
Future<ProviderContainer> pumpApp(
  WidgetTester tester, {
  required SaveStore store,
}) async {
  final loaded = await store.load();
  final root = UncontrolledProviderScope(
    container: ProviderContainer(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(loaded),
      ],
    ),
    child: const GameStationApp(),
  );
  addTearDown(root.container.dispose);

  await tester.pumpWidget(root);
  await tester.pumpAndSettle();
  return root.container;
}
