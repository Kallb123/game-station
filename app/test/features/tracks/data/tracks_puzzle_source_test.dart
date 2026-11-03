// The Tracks puzzle source's tests.
//
// Generation is faked throughout, by a [RecordingGenerator] that counts its
// calls and finishes when the test says so, so "one flight per id" and "a cache
// hit calls nothing" are assertions about the source rather than about how fast
// a generate happens to be. `compute` is never used here: the engine's own
// suite covers generation, and the call-site test covers that it is reached
// through an isolate.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/core/storage/progress_repository.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_record.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_source.dart';

import '../tracks_fixtures.dart';

void main() {
  final id = TracksPuzzleId.parse('tracks:5x5:easy:0');
  final record = TracksPuzzleRecord.of(puzzleFor(id.value));

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

  test('a cache hit resolves without generating', () async {
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repositoryOver(saveWith(cache: {id.value: record.encode()})),
      generator: generator.generate,
    );

    expect(await source.load(id), record);
    expect(generator.calls, isEmpty);
  });

  test('a miss generates once and caches under the tracks: key', () async {
    final repository = repositoryOver(saveWith());
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repository,
      generator: generator.generate,
    );

    generator.finish(id, record.encode());
    expect(await source.load(id), record);

    expect(generator.calls, [id.value]);
    expect(repository.data.puzzleCache, {id.value: record.encode()});
    expect(id.value, startsWith('tracks:'));
  });

  test('a load during a prewarm shares its flight', () async {
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repositoryOver(saveWith()),
      generator: generator.generate,
    );

    source.prewarm(id);
    final loaded = source.load(id);
    generator.finish(id, record.encode());

    expect(await loaded, record);
    expect(generator.calls, [id.value]);
  });

  test('a prewarm of a cached puzzle generates nothing', () {
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repositoryOver(saveWith(cache: {id.value: record.encode()})),
      generator: generator.generate,
    );

    source.prewarm(id);

    expect(generator.calls, isEmpty);
  });

  test('a corrupt cache entry is regenerated, not shown', () async {
    final repository = repositoryOver(
      saveWith(cache: {id.value: 'not a puzzle'}),
    );
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repository,
      generator: generator.generate,
    );

    generator.finish(id, record.encode());
    expect(await source.load(id), record);

    expect(generator.calls, [id.value]);
    expect(repository.data.puzzleCache, {id.value: record.encode()});
  });

  test('a failed generation is not remembered as a flight', () async {
    // An entry left behind by a failure would serve the same exception to every
    // later load, however healthy the app was by then.
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
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
    var thrown = 0;
    final source = IsolateTracksPuzzleSource(
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

  test('a prewarm failure is swallowed rather than left to the zone', () async {
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repositoryOver(saveWith()),
      generator: generator.generate,
    );

    source.prewarm(id);
    generator.fail(id, StateError('the isolate died'));
    await pumpEventQueue();

    generator.finish(id, record.encode());
    expect(await source.load(id), record);
  });

  test('a generation that lands after dispose writes nothing', () async {
    final repository = repositoryOver(saveWith());
    final generator = RecordingGenerator();
    final source = IsolateTracksPuzzleSource(
      repository,
      generator: generator.generate,
    );

    final loaded = source.load(id);
    source.dispose();
    generator.finish(id, record.encode());

    expect(await loaded, record);
    expect(repository.data.puzzleCache, isEmpty);
  });
}

/// A [TracksPuzzleGenerator] that records what it was asked for and answers
/// when the test says so, before or after the call.
class RecordingGenerator {
  /// Every id passed to [generate], in order, one entry per call.
  final List<String> calls = [];

  final Map<String, List<Completer<String>>> _waiting = {};
  final Map<String, Object> _answers = {};

  /// The [TracksPuzzleGenerator] to hand to the source.
  Future<String> generate(String id) {
    calls.add(id);
    final answer = _answers[id];
    if (answer is String) return Future<String>.value(answer);
    if (answer != null) return Future<String>.error(answer);

    final completer = Completer<String>();
    (_waiting[id] ??= []).add(completer);
    return completer.future;
  }

  /// Answers the generation of [id] with [encoded].
  void finish(TracksPuzzleId id, String encoded) => _answer(id.value, encoded);

  /// Fails the generation of [id] with [error]; a later [finish] replaces it.
  void fail(TracksPuzzleId id, Object error) => _answer(id.value, error);

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
