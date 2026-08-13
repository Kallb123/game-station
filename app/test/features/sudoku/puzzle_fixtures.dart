// Fixtures shared by the Sudoku tests.
//
// Not a `_test.dart` file, so `flutter test` does not try to run it.
//
// [FakePuzzleSource] is the reason widget tests stay fast: it is what
// `puzzleSourceProvider` is overridden with, so a screen gets a real puzzle
// without a real generation (`PLAN-phase-3.md` §4.2). The puzzles behind it are
// generated once per run and shared, because a fake that returned a made-up
// grid would let a test pass against a board no engine would produce.

import 'package:game_station/features/sudoku/data/puzzle_record.dart';
import 'package:game_station/features/sudoku/data/puzzle_source.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

/// The record for [id], generated on the first ask and remembered afterwards.
///
/// Keep test ids to Easy: a 9x9 Easy is about a millisecond and a 9x9 Hard is
/// 65 (`PLAN.md` §3.5), and thirty widget tests are what the memo exists for.
PuzzleRecord fixtureRecord(PuzzleId id) =>
    _fixtures[id.value] ??= PuzzleRecord.of(generateSudoku(id));

final Map<String, PuzzleRecord> _fixtures = {};

/// A [PuzzleSource] that answers from [fixtureRecord] without an isolate, a
/// cache or a delay, and records what it was asked for.
class FakePuzzleSource implements PuzzleSource {
  /// Answers from [records] where it has an entry, and from [fixtureRecord]
  /// otherwise — so a test that cares which puzzle it gets says so, and one
  /// that only needs a playable board says nothing.
  FakePuzzleSource({this.records = const {}});

  /// The records this answers with, by puzzle id.
  final Map<String, PuzzleRecord> records;

  /// Every id passed to [load], in order.
  final List<PuzzleId> loads = [];

  /// Every id passed to [prewarm], in order.
  final List<PuzzleId> prewarms = [];

  /// The record this source answers for [id].
  PuzzleRecord recordFor(PuzzleId id) => records[id.value] ?? fixtureRecord(id);

  @override
  Future<PuzzleRecord> load(PuzzleId id) {
    loads.add(id);
    // Already complete, so a screen that awaits it draws on the next frame:
    // the play screen's spinner delay is what decides whether a spinner is
    // shown, and a fake that resolved a frame late would decide it instead.
    return Future<PuzzleRecord>.value(recordFor(id));
  }

  @override
  void prewarm(PuzzleId id) => prewarms.add(id);
}
