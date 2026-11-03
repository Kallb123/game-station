// Where the Tracks screen gets a puzzle from.
//
// The same arrangement as Sudoku's `puzzle_source.dart`
// (`PLAN-phase-9-tracks.md` §4.9): every generation goes through [compute], so
// it never runs on the isolate that draws, and the only call to `generateTracks`
// in `app/lib` is the entry point below — asserted by a test rather than by
// this comment, because a second call site added later would still compile.
//
// In front of the isolate sits the save's `puzzleCache`, shared with Sudoku, and
// a map of in-flight loads, which makes a pre-warm and the tap that follows it
// cost one generation rather than two.

import 'package:flutter/foundation.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/progress_repository.dart';
import 'tracks_puzzle_record.dart';

/// Where a screen gets a Tracks puzzle from.
///
/// An interface with two implementations, so that every widget test runs
/// against fixtures instead of generating a real puzzle per test.
abstract interface class TracksPuzzleSource {
  /// The puzzle [id] names, from the cache if it is there and from a
  /// background isolate if it is not.
  Future<TracksPuzzleRecord> load(TracksPuzzleId id);

  /// Starts loading [id] so that a later [load] finds it cached.
  ///
  /// Returns nothing and never throws: nothing is waiting for a pre-warm, and
  /// a child who never taps the puzzle it warmed should not learn that it
  /// failed.
  void prewarm(TracksPuzzleId id);
}

/// What [IsolateTracksPuzzleSource] calls for a puzzle it has not got: the
/// canonical id string in, the encoded record out.
///
/// Primitives both ways, because they cross an isolate boundary. It is a
/// parameter so that a test can count generations and control when one
/// finishes; the app never passes it.
typedef TracksPuzzleGenerator = Future<String> Function(String id);

/// Generates the puzzle [id] names on a background isolate.
///
/// One isolate per call, for the reason Sudoku's source gives: a child starts a
/// puzzle every few minutes, so there is nothing to pool for.
Future<String> generateTracksOnIsolate(String id) =>
    compute(_generateTracksRecord, id, debugLabel: 'generate $id');

/// The isolate entry point, and the one place in `app/lib` that generates
/// Tracks puzzles.
String _generateTracksRecord(String id) =>
    TracksPuzzleRecord.of(generateTracks(TracksPuzzleId.parse(id))).encode();

/// The real [TracksPuzzleSource]: the save's cache in front of a generation
/// isolate.
class IsolateTracksPuzzleSource implements TracksPuzzleSource {
  /// Reads and writes its cache through [repository], so a generated puzzle
  /// survives a relaunch and is evicted by the rules that keep the save small.
  IsolateTracksPuzzleSource(
    this._repository, {
    this.generator = generateTracksOnIsolate,
  });

  final ProgressRepository _repository;

  /// What this asks for a puzzle it has not got. The app leaves it at
  /// [generateTracksOnIsolate]; a test passes one it can count and hold open.
  final TracksPuzzleGenerator generator;

  /// The loads that have started and not finished, by id.
  final Map<String, Future<TracksPuzzleRecord>> _flights = {};

  bool _disposed = false;

  /// Stops this writing to its repository.
  ///
  /// A generation cannot be cancelled, so one outlives the scope that started
  /// it whenever the scope goes first, and a [ProgressRepository] notifying its
  /// listeners after it was disposed is an assertion failure in front of a
  /// child. The provider calls this from `ref.onDispose`; the puzzle itself
  /// still arrives for whoever awaited it.
  void dispose() => _disposed = true;

  @override
  Future<TracksPuzzleRecord> load(TracksPuzzleId id) {
    final cached = _cached(id);
    // A completed future rather than an `async` method, so a cache hit resolves
    // before the play screen's spinner delay has anything to time.
    if (cached != null) return Future<TracksPuzzleRecord>.value(cached);
    return _flights[id.value] ?? _start(id);
  }

  @override
  void prewarm(TracksPuzzleId id) {
    if (_cached(id) != null || _flights.containsKey(id.value)) return;
    // The result is ignored, failure included: a later [load] retries and has a
    // screen to report to, and an unhandled error from a fire-and-forget future
    // would reach the zone instead.
    _start(id).ignore();
  }

  Future<TracksPuzzleRecord> _start(TracksPuzzleId id) {
    final flight = _generateAndCache(id);
    _flights[id.value] = flight;
    // Cleared here rather than in a `finally` inside the body: a generator that
    // throws before its first suspension would run that `finally` before the
    // line above added the entry, and leave the failure cached as a flight
    // forever.
    flight.whenComplete(() => _flights.remove(id.value)).ignore();
    return flight;
  }

  Future<TracksPuzzleRecord> _generateAndCache(TracksPuzzleId id) async {
    final encoded = await generator(id.value);
    final record = TracksPuzzleRecord.decode(id, encoded);
    if (!_disposed) _repository.cacheTracksPuzzle(id, encoded);
    return record;
  }

  /// The cached record for [id], or null when there is none and when the one
  /// there is will not decode.
  TracksPuzzleRecord? _cached(TracksPuzzleId id) {
    final encoded = _repository.data.puzzleCache[id.value];
    if (encoded == null) return null;
    try {
      return TracksPuzzleRecord.decode(id, encoded);
    } on FormatException {
      // A hand-edited or truncated save is not something to put in front of a
      // child (`AGENTS.md`). Regenerating costs a spinner and produces the same
      // puzzle, because the id is the puzzle.
      return null;
    }
  }
}
