// Where a screen gets a puzzle from.
//
// Generation is 65 ms at the median for a 9x9 Hard and about half a second at
// the tail (`PLAN.md` §3.5), which is eight frames and thirty frames: it cannot
// happen on the isolate that draws. Every generation therefore goes through
// [compute], and the only call to `generateSudoku` in `app/lib` is the entry
// point below — asserted by a test rather than by this comment, because a
// second call site added later would still compile.
//
// In front of the isolate sits the save's `puzzleCache`, which makes a revisit
// instant, and a map of in-flight loads, which makes the pre-warm and the tap
// that follows it two seconds later cost one generation rather than two.

import 'package:flutter/foundation.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/progress_repository.dart';
import 'puzzle_record.dart';

/// Where a screen gets a puzzle from (`PLAN-phase-3.md` §4.2).
///
/// An interface with two implementations, so that every widget test runs
/// against fixtures: generating a real puzzle in each of thirty widget tests
/// would put seconds on `flutter test` and cover nothing the engine's own suite
/// does not already cover.
abstract interface class PuzzleSource {
  /// The puzzle [id] names, from the cache if it is there and from a
  /// background isolate if it is not.
  Future<PuzzleRecord> load(PuzzleId id);

  /// Starts loading [id] so that a later [load] finds it cached.
  ///
  /// Returns nothing and never throws: nothing is waiting for a pre-warm, and
  /// a child who never taps the puzzle it warmed should not learn that it
  /// failed.
  void prewarm(PuzzleId id);
}

/// What [IsolatePuzzleSource] calls for a puzzle it has not got: the canonical
/// id string in, the encoded record out.
///
/// Primitives both ways, because they cross an isolate boundary. It is a
/// parameter so that a test can count generations and control when one
/// finishes; the app never passes it.
typedef PuzzleGenerator = Future<String> Function(String id);

/// Generates the puzzle [id] names on a background isolate.
///
/// [compute] spawns an isolate per call, which costs a few milliseconds
/// against a 65 ms generate. A pooled long-lived worker would save that, and
/// was rejected (`PLAN-phase-3.md` §3): a child starts a puzzle every few
/// minutes, so there is nothing to pool for.
Future<String> generateOnIsolate(String id) =>
    compute(_generateRecord, id, debugLabel: 'generate $id');

/// The isolate entry point, and the one place in `app/lib` that generates.
String _generateRecord(String id) =>
    PuzzleRecord.of(generateSudoku(PuzzleId.parse(id))).encode();

/// The real [PuzzleSource]: the save's cache in front of a generation isolate.
class IsolatePuzzleSource implements PuzzleSource {
  /// Reads and writes its cache through [repository], so a generated puzzle
  /// survives a relaunch and is evicted by the rules that keep the save small
  /// (`PLAN-phase-3.md` §4.8).
  IsolatePuzzleSource(this._repository, {this.generator = generateOnIsolate});

  final ProgressRepository _repository;

  /// What this asks for a puzzle it has not got. The app leaves it at
  /// [generateOnIsolate]; a test passes one it can count and hold open.
  final PuzzleGenerator generator;

  /// The loads that have started and not finished, by id.
  ///
  /// One flight per id: the daily card pre-warms its puzzle when the menu
  /// opens, and the child taps *Play* while that is still running.
  final Map<String, Future<PuzzleRecord>> _flights = {};

  bool _disposed = false;

  /// Stops this writing to its repository.
  ///
  /// A generation cannot be cancelled ([prewarm]), so one outlives the scope
  /// that started it whenever the scope goes first — and a [ProgressRepository]
  /// notifying its listeners after it was disposed is an assertion failure, in
  /// front of a child. The provider calls this from `ref.onDispose`; the puzzle
  /// itself still arrives for whoever awaited it.
  void dispose() => _disposed = true;

  @override
  Future<PuzzleRecord> load(PuzzleId id) {
    final cached = _cached(id);
    // A completed future rather than an `async` method, so a cache hit resolves
    // before the play screen's spinner delay has anything to time
    // (`PLAN-phase-3.md` §4.2).
    if (cached != null) return Future<PuzzleRecord>.value(cached);
    return _flights[id.value] ?? _start(id);
  }

  @override
  void prewarm(PuzzleId id) {
    if (_cached(id) != null || _flights.containsKey(id.value)) return;
    // Not cancellable, because [compute] is not: an abandoned pre-warm finishes
    // and lands in the cache, which is what the cache wanted anyway. The result
    // is ignored, failure included — a later [load] retries and has a screen to
    // report to, and an unhandled error from a fire-and-forget future would
    // reach the zone instead.
    _start(id).ignore();
  }

  Future<PuzzleRecord> _start(PuzzleId id) {
    final flight = _generateAndCache(id);
    _flights[id.value] = flight;
    // Cleared here rather than in a `finally` inside the body: a generator that
    // throws before its first suspension runs that `finally` synchronously,
    // which would remove the entry before the line above added it and leave the
    // failure cached as a flight forever.
    flight.whenComplete(() => _flights.remove(id.value)).ignore();
    return flight;
  }

  Future<PuzzleRecord> _generateAndCache(PuzzleId id) async {
    final encoded = await generator(id.value);
    final record = PuzzleRecord.decode(id.spec, encoded);
    if (!_disposed) _repository.cachePuzzle(id, encoded);
    return record;
  }

  /// The cached record for [id], or null when there is none and when the one
  /// there is will not decode.
  ///
  /// A cache written by an older generator is not a case here: the repository
  /// drops the whole cache at load when the version moved
  /// (`PLAN-phase-3.md` §4.1), so anything still in it was made by this build.
  PuzzleRecord? _cached(PuzzleId id) {
    final encoded = _repository.data.puzzleCache[id.value];
    if (encoded == null) return null;
    try {
      return PuzzleRecord.decode(id.spec, encoded);
    } on FormatException {
      // A hand-edited or truncated save is not something to put in front of a
      // child (`AGENTS.md`). Regenerating costs a spinner and produces the same
      // puzzle, because the id is the puzzle.
      return null;
    }
  }
}
