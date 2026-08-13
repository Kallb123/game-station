// The repository's tests.
//
// Time is not faked: every test either awaits `flush()` or drives a store that
// only completes when the test says so (PLAN-phase-1.md §4.3). A test that
// pumped a 500 ms timer would be testing the timer.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/progress_repository.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

void main() {
  DateTime clock() => DateTime.utc(2026, 8, 12, 9);

  SaveData freshSave() => SaveData.initial(createdAt: clock());

  /// A repository over [store], with the debounce the app uses unless a test
  /// needs the timer to fire.
  ProgressRepository repositoryOver(
    SaveStore store, {
    SaveData? from,
    Duration debounce = const Duration(milliseconds: 500),
  }) {
    final repository = ProgressRepository(
      store,
      initial: from ?? freshSave(),
      debounce: debounce,
      now: clock,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  group('writing', () {
    test(
      'a burst of mutations costs one write, and the last one wins',
      () async {
        final store = MemorySaveStore(initial: freshSave());
        final repository = repositoryOver(store);

        for (var i = 0; i < 10; i++) {
          repository.updateSettings(
            repository.settings.copyWith(sound: i.isEven),
          );
        }
        await repository.flush();

        expect(store.writes, 1);
        expect((await store.load()).data.settings.sound, isFalse);
        expect(repository.isSaving, isFalse);
      },
    );

    test('a mutation that changes nothing writes nothing', () async {
      final store = MemorySaveStore(initial: freshSave());
      final repository = repositoryOver(store);

      repository.updateSettings(repository.settings);
      repository.renameProfile('p1', repository.activeProfile.name);
      await repository.flush();

      expect(store.writes, 0);
    });

    test('flush with nothing outstanding does not write', () async {
      final store = MemorySaveStore(initial: freshSave());

      await repositoryOver(store).flush();

      expect(store.writes, 0);
    });

    test('a mutation made during a write is written after it, once', () async {
      // The single-slot queue. Two writes overlapping is the one way the
      // atomic-write design still loses a save, so the assertion is both that
      // the second write happened and that there were only two.
      final store = _GatedStore();
      final repository = repositoryOver(store, debounce: Duration.zero);

      repository.updateSettings(const AppSettings(sound: false));
      await store.started.first;
      expect(store.writes, 1);

      repository.updateSettings(const AppSettings(music: true));
      repository.updateSettings(const AppSettings(haptics: false));
      await pumpEventQueue();
      expect(store.writes, 1, reason: 'no write starts beside one in flight');

      store.release();
      await repository.flush();

      expect(store.writes, 2);
      expect(store.last?.settings.haptics, isFalse);
    });

    test('a failed write is recorded, not thrown', () async {
      // The caller is a tap handler. An unhandled exception from one is a crash
      // in front of a child (PLAN-phase-1.md §7).
      final repository = repositoryOver(_FailingStore());

      repository.updateSettings(const AppSettings(sound: false));
      await repository.flush();

      expect(repository.lastWriteError, isA<Exception>());
    });

    test('a later successful write clears the recorded failure', () async {
      final store = _FailingStore();
      final repository = repositoryOver(store);
      repository.updateSettings(const AppSettings(sound: false));
      await repository.flush();

      store.failing = false;
      repository.updateSettings(const AppSettings(music: true));
      await repository.flush();

      expect(repository.lastWriteError, isNull);
    });

    test('mutations notify listeners', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      var notifications = 0;
      repository.addListener(() => notifications++);

      repository.updateSettings(const AppSettings(sound: false));
      repository.updateSettings(const AppSettings(sound: false));

      expect(notifications, 1, reason: 'the second mutation changes nothing');
    });

    test('the state survives a reload over the same store', () async {
      final store = MemorySaveStore(initial: freshSave());
      final first = repositoryOver(store);
      first.createProfile(name: 'Bo', avatar: AvatarId.owl);
      first.updateSettings(const AppSettings(theme: ThemeChoice.night));
      await first.flush();

      final reloaded = repositoryOver(store, from: (await store.load()).data);

      expect(reloaded.profiles.map((profile) => profile.name), [
        'Player 1',
        'Bo',
      ]);
      expect(reloaded.activeProfile.name, 'Bo');
      expect(reloaded.settings.theme, ThemeChoice.night);
    });
  });

  group('profiles', () {
    test('a new profile gets the next number and becomes active', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      final created = repository.createProfile(
        name: 'Bo',
        avatar: AvatarId.owl,
      );

      expect(created.id, 'p2');
      expect(created.createdAt.isUtc, isTrue);
      expect(repository.activeProfile.id, 'p2');
    });

    test('numbers are not reused after a delete', () async {
      // Reusing p2 would attach the deleted child's puzzle ids to the new one
      // if a stale reference ever survived.
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl);
      repository.createProfile(name: 'Cai', avatar: AvatarId.cat);

      repository.deleteProfile('p2');
      final created = repository.createProfile(
        name: 'Dee',
        avatar: AvatarId.dog,
      );

      expect(created.id, 'p4');
    });

    test('a name is trimmed and capped', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      final created = repository.createProfile(
        name: '   Bartholomew the Third   ',
        avatar: AvatarId.bear,
      );

      expect(created.name, 'Bartholomew');
      expect(created.name.length, lessThanOrEqualTo(maxProfileNameLength));
    });

    test('an emoji name is not cut in half', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      final created = repository.createProfile(
        name: '🦊🦊🦊🦊🦊🦊🦊🦊🦊🦊🦊🦊🦊🦊',
        avatar: AvatarId.fox,
      );

      expect(created.name.runes.length, maxProfileNameLength);
      expect(created.name.runes.every((rune) => rune == 0x1F98A), isTrue);
    });

    test('an empty name becomes Player n', () async {
      // A child who taps Create without typing gets a profile, not a red error.
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      final created = repository.createProfile(
        name: '   ',
        avatar: AvatarId.frog,
      );

      expect(created.name, 'Player 2');
    });

    test('renaming trims and falls back the same way', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl);

      repository.renameProfile('p2', '  Bo Jr  ');
      expect(repository.profiles.last.name, 'Bo Jr');

      repository.renameProfile('p2', '');
      expect(repository.profiles.last.name, 'Player 2');
    });

    test('the avatar can be changed without touching the name', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      repository.setProfileAvatar('p1', AvatarId.panda);

      expect(repository.activeProfile.avatar, AvatarId.panda);
      expect(repository.activeProfile.name, 'Player 1');
    });

    test('deleting the active profile selects another', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl);

      repository.deleteProfile('p2');

      expect(repository.activeProfile.id, 'p1');
      expect(repository.profiles, hasLength(1));
    });

    test('deleting an inactive profile leaves the selection alone', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl);

      repository.deleteProfile('p1');

      expect(repository.activeProfile.id, 'p2');
    });

    test('the last profile cannot be deleted', () async {
      // Refused here rather than only hidden in the UI: a save with no profiles
      // has no way back to a working app.
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      expect(() => repository.deleteProfile('p1'), throwsStateError);
      expect(repository.profiles, hasLength(1));
    });

    test('an unknown profile id is refused', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      expect(() => repository.selectProfile('p9'), throwsArgumentError);
      expect(() => repository.deleteProfile('p9'), throwsArgumentError);
      expect(() => repository.renameProfile('p9', 'Bo'), throwsArgumentError);
    });

    test('selecting a profile persists', () async {
      final store = MemorySaveStore(initial: freshSave());
      final repository = repositoryOver(store);
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl);

      repository.selectProfile('p1');
      await repository.flush();

      expect((await store.load()).data.activeProfileId, 'p1');
    });

    test('mistake feedback is set per profile', () async {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl);

      repository.setMistakeFeedback('p2', MistakeFeedback.atCompletion);

      expect(
        repository.profiles.firstWhere((p) => p.id == 'p1').mistakeFeedback,
        MistakeFeedback.immediate,
      );
      expect(
        repository.activeProfile.mistakeFeedback,
        MistakeFeedback.atCompletion,
      );
    });
  });

  group('sudoku', () {
    PuzzleId puzzleAt(int index, {Difficulty difficulty = Difficulty.easy}) =>
        PuzzleId(SudokuSpec.s9x9, difficulty, index);

    test('saveInProgress stores an entry and clearInProgress removes it', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      final id = puzzleAt(3);

      repository.saveInProgress(id, PuzzleInProgress(grid: '.' * 81));
      expect(
        repository.activeProfile.sudoku.inProgress[id.value]?.grid,
        '.' * 81,
      );

      repository.clearInProgress(id);
      expect(repository.activeProfile.sudoku.inProgress, isEmpty);
    });

    test('clearing an id with no entry changes nothing', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      var notifications = 0;
      repository.addListener(() => notifications++);

      repository.clearInProgress(puzzleAt(9));

      expect(notifications, 0);
    });

    test(
      'recordSolved clears the matching inProgress entry, in one mutation',
      () {
        final repository = repositoryOver(
          MemorySaveStore(initial: freshSave()),
        );
        final id = puzzleAt(5);
        repository.saveInProgress(id, PuzzleInProgress(grid: '.' * 81));

        var notifications = 0;
        repository.addListener(() => notifications++);
        repository.recordSolved(id, const SolvedPuzzle(timeMs: 60000));

        expect(
          notifications,
          1,
          reason:
              'a save cannot hold a puzzle both finished and in progress, '
              'even for the instant between two mutations',
        );
        expect(repository.activeProfile.sudoku.solved[id.value]?.timeMs, 60000);
        expect(repository.activeProfile.sudoku.inProgress, isEmpty);
      },
    );

    test('recordSolved keeps the faster of the times seen so far', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      repository.recordSolved(
        puzzleAt(1, difficulty: Difficulty.medium),
        const SolvedPuzzle(timeMs: 90000),
      );
      repository.recordSolved(
        puzzleAt(2, difficulty: Difficulty.medium),
        const SolvedPuzzle(timeMs: 40000),
      );
      repository.recordSolved(
        puzzleAt(3, difficulty: Difficulty.medium),
        const SolvedPuzzle(timeMs: 120000),
      );

      expect(repository.activeProfile.sudoku.bestTimeMs['9x9:medium'], 40000);
    });

    test('a burst of sudoku mutations costs one write', () async {
      final store = MemorySaveStore(initial: freshSave());
      final repository = repositoryOver(store);
      final id = puzzleAt(0);

      for (var i = 0; i < 5; i++) {
        repository.saveInProgress(
          id,
          PuzzleInProgress(grid: '.' * 81, elapsedMs: i * 1000),
        );
      }
      await repository.flush();

      expect(store.writes, 1);
    });
  });

  group('daily streak', () {
    // Day indices rather than real dates, so the arithmetic is exercised
    // without depending on `dayIndexFor`'s epoch elsewhere in the suite
    // (`PLAN-phase-3.md` §4.7).
    DateTime dayN(int n) => DateTime.utc(2026, 1, 1).add(Duration(days: n));

    ProgressRepository repositoryAt(DateTime Function() now) {
      final repository = ProgressRepository(
        MemorySaveStore(initial: freshSave()),
        initial: freshSave(),
        now: now,
      );
      addTearDown(repository.dispose);
      return repository;
    }

    test('solving the daily puzzle twice in one day changes nothing the '
        'second time', () {
      late DateTime today;
      final repository = repositoryAt(() => today);
      today = dayN(10);

      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 10),
        const SolvedPuzzle(timeMs: 1),
      );
      repository.recordSolved(
        PuzzleId(SudokuSpec.s6x6, Difficulty.hard, 10),
        const SolvedPuzzle(timeMs: 1),
      );

      expect(repository.activeProfile.sudoku.dailyStreak.current, 1);
    });

    test('solving it the next day increments the streak', () {
      late DateTime today;
      final repository = repositoryAt(() => today);

      today = dayN(10);
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 10),
        const SolvedPuzzle(timeMs: 1),
      );
      today = dayN(11);
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 11),
        const SolvedPuzzle(timeMs: 1),
      );

      expect(repository.activeProfile.sudoku.dailyStreak.current, 2);
      expect(repository.activeProfile.sudoku.dailyStreak.best, 2);
    });

    test('missing a day resets the streak but keeps the best', () {
      late DateTime today;
      final repository = repositoryAt(() => today);

      today = dayN(10);
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 10),
        const SolvedPuzzle(timeMs: 1),
      );
      today = dayN(11);
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 11),
        const SolvedPuzzle(timeMs: 1),
      );
      today = dayN(13); // Day 12 was skipped.
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 13),
        const SolvedPuzzle(timeMs: 1),
      );

      expect(repository.activeProfile.sudoku.dailyStreak.current, 1);
      expect(repository.activeProfile.sudoku.dailyStreak.best, 2);
    });

    test('solving a puzzle that is not the daily one leaves the streak '
        'untouched', () {
      late DateTime today;
      final repository = repositoryAt(() => today);

      today = dayN(10);
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, 10),
        const SolvedPuzzle(timeMs: 1),
      );
      today = dayN(11);
      repository.recordSolved(
        PuzzleId(SudokuSpec.s9x9, Difficulty.hard, 999),
        const SolvedPuzzle(timeMs: 1),
      );

      expect(repository.activeProfile.sudoku.dailyStreak.current, 1);
      expect(repository.activeProfile.sudoku.dailyStreak.lastDayIndex, 10);
    });
  });

  group('puzzle cache', () {
    PuzzleId puzzleAt(int index) =>
        PuzzleId(SudokuSpec.s9x9, Difficulty.easy, index);

    test('caches up to the cap with no eviction', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));

      for (var i = 0; i < puzzleCacheCap; i++) {
        repository.cachePuzzle(puzzleAt(i), 'record-$i');
      }

      expect(repository.data.puzzleCache, hasLength(puzzleCacheCap));
    });

    test('the least-recently-used entry is evicted over the cap', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      for (var i = 0; i < puzzleCacheCap; i++) {
        repository.cachePuzzle(puzzleAt(i), 'record-$i');
      }

      repository.cachePuzzle(puzzleAt(puzzleCacheCap), 'record-new');

      expect(repository.data.puzzleCache, hasLength(puzzleCacheCap));
      expect(
        repository.data.puzzleCache.containsKey(puzzleAt(0).value),
        isFalse,
        reason: 'the oldest untouched entry is the one dropped',
      );
      expect(
        repository.data.puzzleCache.containsKey(puzzleAt(puzzleCacheCap).value),
        isTrue,
      );
    });

    test('re-caching an id refreshes it, so it is not the next eviction', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      for (var i = 0; i < puzzleCacheCap; i++) {
        repository.cachePuzzle(puzzleAt(i), 'record-$i');
      }

      repository.cachePuzzle(puzzleAt(0), 'record-0-refreshed');
      repository.cachePuzzle(puzzleAt(puzzleCacheCap), 'record-new');

      expect(
        repository.data.puzzleCache.containsKey(puzzleAt(0).value),
        isTrue,
      );
      expect(
        repository.data.puzzleCache.containsKey(puzzleAt(1).value),
        isFalse,
        reason: 'index 1 is now the oldest untouched entry',
      );
    });

    test('eviction never drops an id the active profile is resuming', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      final pinned = puzzleAt(0);
      repository.saveInProgress(pinned, PuzzleInProgress(grid: '.' * 81));

      for (var i = 0; i < puzzleCacheCap; i++) {
        repository.cachePuzzle(puzzleAt(i), 'record-$i');
      }
      repository.cachePuzzle(puzzleAt(puzzleCacheCap), 'record-new');

      expect(repository.data.puzzleCache.containsKey(pinned.value), isTrue);
      expect(
        repository.data.puzzleCache.containsKey(puzzleAt(1).value),
        isFalse,
        reason: 'the pin skips to the next-oldest unpinned entry',
      );
    });

    test('a pin in another profile still protects the entry', () {
      final repository = repositoryOver(MemorySaveStore(initial: freshSave()));
      repository.createProfile(name: 'Bo', avatar: AvatarId.owl); // Now active.
      final pinned = puzzleAt(0);
      repository.saveInProgress(pinned, PuzzleInProgress(grid: '.' * 81));
      repository.selectProfile(
        'p1',
      ); // The pin stays on p2, not the active one.

      for (var i = 0; i < puzzleCacheCap; i++) {
        repository.cachePuzzle(puzzleAt(i), 'record-$i');
      }
      repository.cachePuzzle(puzzleAt(puzzleCacheCap), 'record-new');

      expect(repository.data.puzzleCache.containsKey(pinned.value), isTrue);
    });
  });

  group('fromLoad', () {
    test(
      'a stale generator version drops the cache and adopts the current one',
      () {
        final stale = freshSave().copyWith(
          generatorVersion: generatorVersion + 1000,
          puzzleCache: {'sudoku:9x9:easy:0': 'stale'},
        );
        final repository = ProgressRepository.fromLoad(
          MemorySaveStore(initial: stale),
          SaveLoad(stale),
          now: clock,
        );
        addTearDown(repository.dispose);

        expect(repository.data.puzzleCache, isEmpty);
        expect(repository.data.generatorVersion, generatorVersion);
      },
    );

    test('a matching generator version keeps the cache as it was', () {
      final current = freshSave().copyWith(
        puzzleCache: {'sudoku:9x9:easy:0': 'clues'},
      );
      final repository = ProgressRepository.fromLoad(
        MemorySaveStore(initial: current),
        SaveLoad(current),
        now: clock,
      );
      addTearDown(repository.dispose);

      expect(repository.data.puzzleCache, {'sudoku:9x9:easy:0': 'clues'});
    });
  });

  group('round trip', () {
    test(
      'mistake feedback, a cached record and the streak survive a reload',
      () async {
        final store = MemorySaveStore(initial: freshSave());
        final repository = repositoryOver(store);
        final today = dayIndexFor(clock());
        final dailyId = PuzzleId(SudokuSpec.s9x9, Difficulty.easy, today);

        repository.setMistakeFeedback('p1', MistakeFeedback.atCompletion);
        repository.cachePuzzle(dailyId, 'clues|solution');
        repository.recordSolved(dailyId, const SolvedPuzzle(timeMs: 1));
        await repository.flush();

        final reloaded = (await store.load()).data;
        expect(reloaded.schemaVersion, currentSchemaVersion);
        expect(
          reloaded.activeProfile.mistakeFeedback,
          MistakeFeedback.atCompletion,
        );
        expect(reloaded.puzzleCache[dailyId.value], 'clues|solution');
        expect(reloaded.activeProfile.sudoku.dailyStreak.current, 1);
        expect(reloaded.activeProfile.sudoku.dailyStreak.lastDayIndex, today);
      },
    );
  });

  group('over a real directory', () {
    // The PR's done-criterion, end to end: mutate, flush, and read the result
    // back through a second store — which is what a force-quit and a relaunch
    // amount to. Everything above uses MemorySaveStore, so without this the
    // debounce and the atomic write would never be tested together.
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('game_station_repo');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test(
      'a burst of mutations lands as one file, and the app reloads it',
      () async {
        final repository = repositoryOver(
          FileSaveStore(directory, now: clock),
          from: freshSave(),
        );

        repository.createProfile(name: 'Bo', avatar: AvatarId.owl);
        for (var i = 0; i < 10; i++) {
          repository.updateSettings(
            repository.settings.copyWith(
              theme: i.isEven ? ThemeChoice.day : ThemeChoice.night,
            ),
          );
        }
        await repository.flush();

        final relaunched = await FileSaveStore(directory, now: clock).load();

        expect(relaunched.recovery, isNull);
        expect(relaunched.data, repository.data);
        expect(relaunched.data.settings.theme, ThemeChoice.night);
        expect(relaunched.data.activeProfile.name, 'Bo');
        // The temp file is the interrupted-write marker; a completed flush must
        // not leave one behind for the next launch to find and delete.
        expect(File('${directory.path}/$tempFileName').existsSync(), isFalse);
      },
    );
  });

  group('dispose', () {
    test('starts a scheduled write rather than dropping it', () async {
      // Losing the last thing a child did because the screen closed first is
      // the failure this covers.
      final store = MemorySaveStore(initial: freshSave());
      final repository = ProgressRepository(
        store,
        initial: freshSave(),
        now: clock,
      );

      repository.updateSettings(const AppSettings(sound: false));
      repository.dispose();
      await pumpEventQueue();

      expect(store.writes, 1);
      expect((await store.load()).data.settings.sound, isFalse);
    });
  });
}

/// A store whose writes only finish when the test lets them.
class _GatedStore implements SaveStore {
  final StreamController<void> _started = StreamController<void>.broadcast();
  final Completer<void> _gate = Completer<void>();
  bool _open = false;

  int writes = 0;
  SaveData? last;

  /// Fires as each write begins.
  Stream<void> get started => _started.stream;

  /// Lets the write in flight finish, and every write after it.
  void release() {
    _open = true;
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<SaveLoad> load() async =>
      SaveLoad(SaveData.initial(createdAt: DateTime.utc(2026)));

  @override
  Future<void> write(SaveData data) async {
    writes++;
    last = data;
    _started.add(null);
    if (!_open) await _gate.future;
  }
}

/// A store whose writes fail, standing in for a full or read-only disk.
class _FailingStore implements SaveStore {
  bool failing = true;

  @override
  Future<SaveLoad> load() async =>
      SaveLoad(SaveData.initial(createdAt: DateTime.utc(2026)));

  @override
  Future<void> write(SaveData data) async {
    if (failing) throw Exception('no space left on device');
  }
}
