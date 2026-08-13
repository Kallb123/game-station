// The Sudoku data providers' tests.
//
// Small, because the provider is small — but the override is what every widget
// test from PR 5 onwards depends on, and a provider that could not be
// overridden would be found out thirty tests later.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/providers.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/features/sudoku/data/providers.dart';
import 'package:game_station/features/sudoku/data/puzzle_source.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../puzzle_fixtures.dart';

void main() {
  final id = PuzzleId.parse('sudoku:6x6:easy:0');

  Future<ProviderContainer> containerOver(
    SaveStore store, {
    List<Override> overrides = const [],
  }) async {
    final container = ProviderContainer(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(await store.load()),
        ...overrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('the default source is the one that uses an isolate', () async {
    final container = await containerOver(MemorySaveStore());

    expect(container.read(puzzleSourceProvider), isA<IsolatePuzzleSource>());
  });

  test(
    'a generation still running when the scope goes writes nothing',
    () async {
      // The real source, because what is being tested is the `ref.onDispose`
      // wiring: the repository goes down with the scope, and a cache write to a
      // disposed [ChangeNotifier] fails an assertion rather than being ignored.
      final container = await containerOver(MemorySaveStore());
      final repository = container.read(progressRepositoryProvider);
      final loaded = container.read(puzzleSourceProvider).load(id);

      container.dispose();

      expect(await loaded, fixtureRecord(id));
      expect(repository.data.puzzleCache, isEmpty);
    },
  );

  test('a fake replaces it wholesale', () async {
    final fake = FakePuzzleSource();
    final container = await containerOver(
      MemorySaveStore(),
      overrides: [puzzleSourceProvider.overrideWithValue(fake)],
    );

    final record = await container.read(puzzleSourceProvider).load(id);

    expect(record, fixtureRecord(id));
    expect(fake.loads, [id]);
  });

  test('a saved move does not replace the source', () async {
    // The in-flight map lives on the instance, so a provider that rebuilt on
    // every `notifyListeners` would drop it — and the pre-warm the menu started
    // would be generated a second time by the tap that follows.
    final container = await containerOver(MemorySaveStore());
    final source = container.read(puzzleSourceProvider);

    container.read(progressRepositoryProvider).renameProfile('p1', 'Ana');

    expect(container.read(puzzleSourceProvider), same(source));
  });
}
