// What the Tracks menu shows, worked out from one profile's saved history.
//
// `SudokuMenu` for Tracks, minus the daily puzzle and the streak, which Tracks
// does not have (`PLAN-phase-9-tracks.md` §2, §4.14). Pure over
// [TracksProgress], so the arithmetic behind every card and row is tested with
// plain `test()` calls rather than by reading a widget tree.
//
// Everything is derived rather than stored, for the reason `sudoku_menu.dart`
// gives: the save has no "last played" field, and a counter that decides a card
// is not worth widening a save format for.

import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/save_data.dart';
import 'tracks_difficulties.dart';

/// One profile's Tracks history, as the menu needs to read it.
class TracksMenu {
  /// Solved indexes first and positionally, because a named parameter cannot
  /// carry the private field's name and so cannot initialise it directly.
  const TracksMenu._(
    this._solvedIndexes,
    this._fallbackAssists, {
    required this.progress,
    required this.continuePuzzle,
    required this.lastPlayed,
  });

  /// The menu for [progress].
  factory TracksMenu.of(TracksProgress progress) {
    final solvedIndexes = <String, Set<int>>{};
    final fallback = <String, ({int hints, int mistakes, String id})>{};
    TracksPuzzleId? lastSolved;
    DateTime? lastSolvedAt;

    for (final entry in progress.solved.entries) {
      final id = _parse(entry.key);
      if (id == null) continue;

      (solvedIndexes[TracksProgress.bestTimeKey(id.spec, id.difficulty)] ??=
              <int>{})
          .add(id.index);

      // The §4.3 fallback: a solve at exactly the stored best time. Fewest
      // assists wins, then the lowest id, so map order cannot decide it.
      final key = TracksProgress.bestTimeKey(id.spec, id.difficulty);
      final solve = entry.value;
      if (solve.timeMs == progress.bestTimeMs[key]) {
        final current = fallback[key];
        final cost = solve.hints + solve.mistakes;
        if (current == null ||
            cost < current.hints + current.mistakes ||
            (cost == current.hints + current.mistakes &&
                id.value.compareTo(current.id) < 0)) {
          fallback[key] = (
            hints: solve.hints,
            mistakes: solve.mistakes,
            id: id.value,
          );
        }
      }

      final at = entry.value.solvedAt;
      if (at == null) continue;
      // The id breaks a tie, so that iterating a map — which has no order worth
      // relying on — cannot decide which size the menu opens on.
      if (lastSolvedAt == null ||
          at.isAfter(lastSolvedAt) ||
          (at == lastSolvedAt && id.value.compareTo(lastSolved!.value) < 0)) {
        lastSolvedAt = at;
        lastSolved = id;
      }
    }

    final continuePuzzle = _continueFrom(progress.inProgress);
    return TracksMenu._(
      solvedIndexes,
      fallback,
      progress: progress,
      continuePuzzle: continuePuzzle,
      lastPlayed: continuePuzzle ?? lastSolved,
    );
  }

  /// The history this reads.
  final TracksProgress progress;

  /// The puzzle the *Keep going* card offers, or null when nothing is
  /// half-finished.
  ///
  /// The one with the most time on its clock, ties broken by the id: the rule
  /// `SudokuMenu.continuePuzzle` documents, for the same reason — a save holds
  /// no timestamp for an unfinished board.
  final TracksPuzzleId? continuePuzzle;

  /// The most recent puzzle this profile has anything to say about, or null for
  /// a profile that has played none: [continuePuzzle] first, then the solved
  /// puzzle with the latest `solvedAt`.
  final TracksPuzzleId? lastPlayed;

  /// Solved indexes by [TracksProgress.bestTimeKey], so [nextPuzzle] and
  /// [solvedCount] cost nothing per build.
  final Map<String, Set<int>> _solvedIndexes;

  /// Hints and mistakes of the solve behind each tier's best time, found in
  /// `solved` for saves written before `bestSolve` existed
  /// (`PLAN-best-time-assists.md` §4.3).
  final Map<String, ({int hints, int mistakes, String id})> _fallbackAssists;

  /// The size the menu opens on: the one last played, else 5x5.
  TracksSpec get lastSpec => lastPlayed?.spec ?? defaultTracksSpec;

  /// The difficulty the menu would suggest at [spec]: the last one played,
  /// or the hardest [spec] offers when it does not have that one — which is
  /// Medium on 5x5 for a child who last played 7x7 Hard. A profile with no
  /// history gets [defaultTracksDifficulty].
  Difficulty lastDifficultyFor(TracksSpec spec) {
    final last = lastPlayed?.difficulty;
    if (last == null) return defaultTracksDifficulty;
    final offered = tracksDifficultiesFor(spec);
    return offered.contains(last) ? last : offered.last;
  }

  /// The puzzle a difficulty row launches: the lowest index this profile has
  /// not solved.
  ///
  /// A half-finished one is offered again rather than skipped — the play screen
  /// resumes it from the save.
  TracksPuzzleId nextPuzzle(TracksSpec spec, Difficulty difficulty) {
    final solved = _solvedIndexes[TracksProgress.bestTimeKey(spec, difficulty)];
    var index = 0;
    while (solved != null &&
        index < TracksPuzzleId.maxPuzzleIndex &&
        solved.contains(index)) {
      index++;
    }
    return TracksPuzzleId(spec, difficulty, index);
  }

  /// How many puzzles of this size and difficulty this profile has finished.
  int solvedCount(TracksSpec spec, Difficulty difficulty) =>
      _solvedIndexes[TracksProgress.bestTimeKey(spec, difficulty)]?.length ?? 0;

  /// The best time for this size and difficulty in milliseconds, or null where
  /// none has been set.
  int? bestTimeMs(TracksSpec spec, Difficulty difficulty) =>
      progress.bestTimeMs[TracksProgress.bestTimeKey(spec, difficulty)];

  /// What the best solve for this size and difficulty cost, or null where
  /// that is unknown.
  ///
  /// The stored `bestSolve` when it agrees with the best time; else the
  /// fallback from `solved`, which exists because saves written before
  /// `bestSolve` have a best time and no detail beside it
  /// (`PLAN-best-time-assists.md` §4.3). Nothing is written back.
  ({int hints, int mistakes})? bestAssists(
    TracksSpec spec,
    Difficulty difficulty,
  ) {
    final key = TracksProgress.bestTimeKey(spec, difficulty);
    final stored = progress.bestSolveFor(key);
    if (stored != null) {
      return (hints: stored.hints, mistakes: stored.mistakes);
    }
    final found = _fallbackAssists[key];
    return found == null
        ? null
        : (hints: found.hints, mistakes: found.mistakes);
  }

  static TracksPuzzleId? _continueFrom(
    Map<String, TracksInProgress> inProgress,
  ) {
    TracksPuzzleId? best;
    var bestElapsed = -1;

    for (final entry in inProgress.entries) {
      final id = _parse(entry.key);
      if (id == null) continue;

      final elapsed = entry.value.elapsedMs;
      if (elapsed > bestElapsed ||
          (elapsed == bestElapsed && id.value.compareTo(best!.value) < 0)) {
        best = id;
        bestElapsed = elapsed;
      }
    }
    return best;
  }

  /// [id] as a [TracksPuzzleId], or null for one this build cannot spell.
  ///
  /// Dropping the entry is the whole of the handling: a hand-edited save must
  /// cost a card, not throw in front of a child (`AGENTS.md`).
  static TracksPuzzleId? _parse(String id) {
    try {
      return TracksPuzzleId.parse(id);
    } on FormatException {
      return null;
    }
  }
}
