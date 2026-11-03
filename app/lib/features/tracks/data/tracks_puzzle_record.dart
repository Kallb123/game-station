// One generated Tracks puzzle, in the one encoded form the app moves it around
// in.
//
// As for Sudoku's `puzzle_record.dart`, the same string serves two jobs
// (`PLAN-phase-9-tracks.md` §4.9): it is what the generation isolate returns —
// a primitive, because it crosses an isolate boundary — and it is what
// `SaveData.puzzleCache` stores. One format means one parser and one test.
//
// The clue line is the engine's own `TracksClues.encode`, and the solution is
// the hex cell line `model/tracks_session_codec.dart` already writes for a
// saved board, so one hex format serves the save and the cache. The solution
// is kept because immediate mistake feedback and hints need the true
// connection at each cell, and the clues alone cannot give it without running
// the solver on every launch.

import 'package:flutter/foundation.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../model/tracks_session_codec.dart';

/// The clues of one Tracks puzzle and its solution.
///
/// ```
/// "5x5|2|3|1,2,..|..|7:5,..|6a0...."
///  │                       │
///  │                       └── the one completion, a hex digit per cell
///  └────────────────────────── the clue line, which contains "|" itself
/// ```
@immutable
class TracksPuzzleRecord {
  /// A record holding [clues] and their [solution], one connection mask per
  /// cell with the port bits set.
  ///
  /// Stores an unmodifiable copy of [solution], so a session holding the
  /// record cannot corrupt the answer it checks against.
  TracksPuzzleRecord({required this.clues, required List<int> solution})
    : solution = List.unmodifiable(solution);

  /// The record for a freshly generated [puzzle].
  factory TracksPuzzleRecord.of(TracksPuzzle puzzle) =>
      TracksPuzzleRecord(clues: puzzle.clues, solution: puzzle.solution);

  /// Reads a record back from [encoded], which is untrusted: it comes from a
  /// save file a tablet wrote months ago, possibly truncated, possibly edited.
  ///
  /// Throws a [FormatException], and never anything else, for whatever is not
  /// a puzzle of [id]'s spec: no separator, a clue line that does not decode,
  /// clues of another size, a solution that does not decode, a solution cell
  /// that is neither empty nor a piece, or a fixed clue the solution
  /// contradicts. The caller's answer to all of them is the same and it is not
  /// an error message: the id names the puzzle, so regenerating produces
  /// exactly what the entry was supposed to hold.
  factory TracksPuzzleRecord.decode(TracksPuzzleId id, String encoded) {
    // The clue line holds five separators of its own, so the record's is the
    // last one: the solution half is hex and cannot contain it.
    final split = encoded.lastIndexOf(separator);
    if (split < 0) {
      throw FormatException(
        'expected "$separator" between the clues and the solution',
        encoded,
      );
    }

    final TracksClues clues;
    try {
      clues = TracksClues.decode(encoded.substring(0, split));
    } on ArgumentError catch (error) {
      // `TracksClues.decode` promises a FormatException; this is for the day it
      // lets a constructor's ArgumentError through, because the caller catches
      // one type.
      throw FormatException('${error.message}', encoded);
    }
    if (clues.spec != id.spec) {
      throw FormatException(
        'expected clues for ${id.spec.label}, got ${clues.spec.label}',
        encoded,
      );
    }

    final solution = decodeTracksCells(id.spec, encoded.substring(split + 1));
    for (var cell = 0; cell < solution.length; cell++) {
      final mask = solution[cell];
      if (mask != 0 && !TrackSide.isPiece(mask)) {
        throw FormatException(
          'the solution at cell $cell is not a piece',
          encoded,
          split + 1 + cell,
        );
      }
      if (clues.fixed[cell] != 0 && clues.fixed[cell] != mask) {
        throw FormatException(
          'the fixed piece at cell $cell is not what the solution puts there',
          encoded,
          split + 1 + cell,
        );
      }
    }

    return TracksPuzzleRecord(clues: clues, solution: solution);
  }

  /// What stands between the clue line and the solution in an encoded record.
  static const String separator = '|';

  /// The puzzle as the child sees it: ports, counts and the pieces laid.
  final TracksClues clues;

  /// The one completion of [clues], as connection masks in row-major order
  /// with the port bits set.
  final List<int> solution;

  /// The string [TracksPuzzleRecord.decode] reads back.
  String encode() =>
      '${clues.encode()}$separator'
      '${encodeTracksCells(clues.spec, solution)}';

  @override
  bool operator ==(Object other) =>
      other is TracksPuzzleRecord &&
      other.clues == clues &&
      listEquals(other.solution, solution);

  @override
  int get hashCode => Object.hash(clues, Object.hashAll(solution));

  @override
  String toString() => 'TracksPuzzleRecord(${encode()})';
}
