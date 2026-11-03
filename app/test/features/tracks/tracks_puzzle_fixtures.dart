// Fixtures shared by the Tracks data and screen tests.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.
//
// [FakeTracksPuzzleSource] is what `tracksPuzzleSourceProvider` is overridden
// with, so a screen gets a real puzzle without a real isolate
// (`PLAN-phase-9-tracks.md` §4.9). The puzzles behind it are the ones
// `tracks_fixtures.dart` generates once per run, because a fake that returned
// a made-up board would let a test pass against one no generator produces.

import 'package:puzzle_engine/puzzle_engine.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_record.dart';
import 'package:zibo_games/features/tracks/data/tracks_puzzle_source.dart';

import 'tracks_fixtures.dart';

/// The record for [id], generated on the first ask and remembered afterwards.
///
/// Keep test ids to Easy: thirty widget tests are what the memo exists for.
TracksPuzzleRecord fixtureTracksRecord(TracksPuzzleId id) =>
    _records[id.value] ??= TracksPuzzleRecord.of(puzzleFor(id.value));

final Map<String, TracksPuzzleRecord> _records = {};

/// A [TracksPuzzleSource] that answers from [fixtureTracksRecord] without an
/// isolate, a cache or a delay, and records what it was asked for.
class FakeTracksPuzzleSource implements TracksPuzzleSource {
  /// Answers from [records] where it has an entry, and from
  /// [fixtureTracksRecord] otherwise.
  FakeTracksPuzzleSource({this.records = const {}});

  /// The records this answers with, by puzzle id.
  final Map<String, TracksPuzzleRecord> records;

  /// Every id passed to [load], in order.
  final List<TracksPuzzleId> loads = [];

  /// Every id passed to [prewarm], in order.
  final List<TracksPuzzleId> prewarms = [];

  /// The record this source answers for [id].
  TracksPuzzleRecord recordFor(TracksPuzzleId id) =>
      records[id.value] ?? fixtureTracksRecord(id);

  @override
  Future<TracksPuzzleRecord> load(TracksPuzzleId id) {
    loads.add(id);
    // Already complete, so a screen that awaits it draws on the next frame: the
    // play screen's spinner delay decides whether a spinner is shown, and a
    // fake that resolved a frame late would decide it instead.
    return Future<TracksPuzzleRecord>.value(recordFor(id));
  }

  @override
  void prewarm(TracksPuzzleId id) => prewarms.add(id);
}
