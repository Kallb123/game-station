// The puzzle source's tests.
//
// Generation is faked in all but one test, by a [RecordingGenerator] that counts
// its calls and finishes when the test says so. That is what makes "one flight
// per id" and "a cache hit calls nothing" assertions about the source rather
// than about how fast a real generate happens to be. The exception is the last
// group, which runs a real puzzle through a real isolate: everything else here
// would pass just as well against a source that never spawned one.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/progress_repository.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';
import 'package:game_station/features/sudoku/data/puzzle_record.dart';
import 'package:game_station/features/sudoku/data/puzzle_source.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

void main() {
  final id = PuzzleId.parse('sudoku:6x6:easy:0');
  final other = PuzzleId.parse('sudoku:6x6:easy:1');
  final record = PuzzleRecord.of(generateSudoku(id));

  DateTime clock() => DateTime.utc(2026, 8, 12, 9);

  SaveData saveWith({Map<String, String> cache = const {}}) =>
      SaveData.initial(createdAt: clock()).copyWith(puzzleCache: cache);

  ProgressRepository repositoryOver(SaveData save) {
    final repository = ProgressRepository(
      MemorySaveStore(initial: save),
      initial: save,
      now: clock,
    );
    addTearDown(repository.dispose);
    return repository;
  }

  group('the cache', () {
    test('a hit resolves without generating', () async {
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith(cache: {id.value: record.encode()})),
        generator: generator.generate,
      );

      expect(await source.load(id), record);
      expect(generator.calls, isEmpty);
    });

    test('a generated puzzle is cached for the next launch', () async {
      final repository = repositoryOver(saveWith());
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repository,
        generator: generator.generate,
      );

      generator.finish(id, record.encode());
      expect(await source.load(id), record);

      expect(repository.data.puzzleCache, {id.value: record.encode()});
    });

    test('an entry that will not decode is regenerated, not shown', () async {
      // What a truncated write or a hand edit leaves behind. Nothing is drawn
      // and nothing is reported: the id names the puzzle, so the regenerated
      // one is the one the entry was supposed to hold (`AGENTS.md`).
      final repository = repositoryOver(
        saveWith(cache: {id.value: 'not a puzzle'}),
      );
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repository,
        generator: generator.generate,
      );

      generator.finish(id, record.encode());
      expect(await source.load(id), record);

      expect(generator.calls, [id.value]);
      expect(repository.data.puzzleCache, {id.value: record.encode()});
    });

    test('an entry from an older generator is never served', () async {
      // The drop happens once, at load, rather than per entry
      // (`PLAN-phase-3.md` §4.1) — so what this asserts is that the source
      // reads the cache through the repository and inherits it.
      final stale = saveWith(
        cache: {id.value: record.encode()},
      ).copyWith(generatorVersion: generatorVersion - 1);
      final repository = ProgressRepository.fromLoad(
        MemorySaveStore(initial: stale),
        SaveLoad(stale),
        now: clock,
      );
      addTearDown(repository.dispose);
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repository,
        generator: generator.generate,
      );

      generator.finish(id, record.encode());
      await source.load(id);

      expect(generator.calls, [id.value]);
      expect(repository.data.generatorVersion, generatorVersion);
    });
  });

  group('one flight per id', () {
    test('two concurrent loads of one id generate once', () async {
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith()),
        generator: generator.generate,
      );

      final first = source.load(id);
      final second = source.load(id);
      generator.finish(id, record.encode());

      expect(await first, record);
      expect(await second, record);
      expect(generator.calls, [id.value]);
    });

    test('two loads of different ids generate twice', () async {
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith()),
        generator: generator.generate,
      );

      final both = Future.wait([source.load(id), source.load(other)]);
      generator
        ..finish(id, record.encode())
        ..finish(other, PuzzleRecord.of(generateSudoku(other)).encode());
      await both;

      expect(generator.calls, [id.value, other.value]);
    });

    test('a finished flight is forgotten', () async {
      final repository = repositoryOver(saveWith());
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repository,
        generator: generator.generate,
      );

      generator.finish(id, record.encode());
      await source.load(id);
      // The entry the first load cached is put out of the way, so that the
      // second load has to reach the generator to answer at all: a flight left
      // in the map would answer from it instead, and the map would grow for the
      // life of the app.
      repository.cachePuzzle(id, 'not a puzzle');

      expect(await source.load(id), record);
      expect(generator.calls, [id.value, id.value]);
    });

    test('a failed generation is not remembered', () async {
      // The trap: an entry left behind by a failure would serve the same
      // exception to every later load, so a child who tapped *Play* twice would
      // get an error the second time however healthy the app was by then.
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith()),
        generator: generator.generate,
      );

      generator.fail(id, StateError('the isolate died'));
      await expectLater(source.load(id), throwsStateError);

      generator.finish(id, record.encode());
      expect(await source.load(id), record);
      expect(generator.calls, [id.value, id.value]);
    });

    test('a generator that throws synchronously is not remembered', () async {
      // Same trap, but thrown before the first suspension, which is where a
      // `finally` in the loading body would run before the flight was recorded.
      var thrown = 0;
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith()),
        generator: (_) {
          thrown++;
          throw StateError('no isolate to spawn');
        },
      );

      await expectLater(source.load(id), throwsStateError);
      await expectLater(source.load(id), throwsStateError);

      expect(thrown, 2);
    });
  });

  group('prewarm', () {
    test('lands in the cache without anyone awaiting it', () async {
      final repository = repositoryOver(saveWith());
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repository,
        generator: generator.generate,
      );

      source.prewarm(id);
      generator.finish(id, record.encode());
      await pumpEventQueue();

      expect(repository.data.puzzleCache, {id.value: record.encode()});
    });

    test('and the tap that follows it share one generation', () async {
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith()),
        generator: generator.generate,
      );

      source.prewarm(id);
      final loaded = source.load(id);
      generator.finish(id, record.encode());

      expect(await loaded, record);
      expect(generator.calls, [id.value]);
    });

    test('generates nothing for a puzzle already cached', () {
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith(cache: {id.value: record.encode()})),
        generator: generator.generate,
      );

      source.prewarm(id);

      expect(generator.calls, isEmpty);
    });

    test('a failure is swallowed rather than left to the zone', () async {
      // An unhandled error from a fire-and-forget future fails the test it
      // happens in, and in the app it would reach the zone with nothing but a
      // pre-warm behind it. This test passes by not failing.
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repositoryOver(saveWith()),
        generator: generator.generate,
      );

      source.prewarm(id);
      generator.fail(id, StateError('the isolate died'));
      await pumpEventQueue();

      // And the failure did not stick: the tap that follows still generates.
      generator.finish(id, record.encode());
      expect(await source.load(id), record);
    });
  });

  group('dispose', () {
    test('a generation that lands afterwards writes nothing', () async {
      // A generation cannot be cancelled, so this is the ordinary case of a
      // pre-warm outliving the screen that started it. The repository is
      // disposed with the scope, and notifying a disposed [ChangeNotifier]
      // fails an assertion — which is a crash in front of a child.
      final repository = repositoryOver(saveWith());
      final generator = RecordingGenerator();
      final source = IsolatePuzzleSource(
        repository,
        generator: generator.generate,
      );

      final loaded = source.load(id);
      source.dispose();
      generator.finish(id, record.encode());

      expect(await loaded, record);
      expect(repository.data.puzzleCache, isEmpty);
    });
  });

  group('the real isolate', () {
    test('returns the puzzle this build generates, decodable', () async {
      final repository = repositoryOver(saveWith());
      final source = IsolatePuzzleSource(repository);

      final loaded = await source.load(id);

      // Compared against a local generation rather than against a stored
      // string: what this asserts is that the isolate ran the same generator,
      // and the engine's goldens are what assert the grid itself.
      expect(loaded, record);
      expect(repository.data.puzzleCache, {id.value: record.encode()});
    });
  });
}

/// A [PuzzleGenerator] that records what it was asked for and answers when the
/// test says so.
///
/// An answer given before the call is remembered for it and for every later
/// one; an answer given after the call completes whatever is waiting. Both
/// orders are needed: "two loads of one id generate once" is only a real
/// assertion while the first generation is still running, and most of the rest
/// read better as arrange-then-act.
class RecordingGenerator {
  /// Every id passed to [generate], in order, one entry per call.
  final List<String> calls = [];

  /// Calls waiting for an answer that has not been given yet.
  final Map<String, List<Completer<String>>> _waiting = {};

  /// The answer each id resolves to: an encoded record, or an error to throw.
  final Map<String, Object> _answers = {};

  /// The [PuzzleGenerator] to hand to the source.
  Future<String> generate(String id) {
    calls.add(id);
    final answer = _answers[id];
    if (answer is String) return Future<String>.value(answer);
    if (answer != null) return Future<String>.error(answer);

    final completer = Completer<String>();
    (_waiting[id] ??= []).add(completer);
    return completer.future;
  }

  /// Answers the generation of [id] with [encoded], before or after it is
  /// asked for.
  void finish(PuzzleId id, String encoded) => _answer(id.value, encoded);

  /// Fails the generation of [id] with [error]. A later [finish] replaces it,
  /// which is how a retry after a failure is arranged.
  void fail(PuzzleId id, Object error) => _answer(id.value, error);

  void _answer(String id, Object answer) {
    _answers[id] = answer;
    for (final completer
        in _waiting.remove(id) ?? const <Completer<String>>[]) {
      if (answer is String) {
        completer.complete(answer);
      } else {
        completer.completeError(answer);
      }
    }
  }
}
