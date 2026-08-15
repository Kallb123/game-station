// What the Sudoku menu shows, worked out from one profile's saved history.
//
// Pure over [SudokuProgress], with no Flutter beyond nothing at all, so the
// menu's arithmetic — which puzzle *Keep going* offers, which one a difficulty
// row launches, how many are solved — is tested with plain `test()` calls
// rather than by reading a widget tree (`PLAN-phase-3.md` §5).
//
// Everything here is derived rather than stored. Schema v1 was declared in full
// in phase 1 and has no field saying which puzzle was played last
// (`PLAN-phase-1.md` §4.2), and §4.3 already set the precedent for that: a
// counter that decides a card is not worth widening a save format for. The
// rules below say what a save can actually support, and each one is a rule
// rather than a heuristic scattered through the screen.

import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/storage/save_data.dart';
import 'difficulties.dart';

/// One profile's Sudoku history, as the menu needs to read it.
///
/// Built once per change to the profile ([SudokuMenu.of] walks `solved`), and
/// then answers every row on the screen without walking it again.
class SudokuMenu {
  /// Solved indexes first and positionally, because a named parameter cannot
  /// carry the private field's name and so cannot initialise it directly.
  const SudokuMenu._(
    this._solvedIndexes, {
    required this.progress,
    required this.continuePuzzle,
    required this.lastPlayed,
  });

  /// The menu for [progress].
  factory SudokuMenu.of(SudokuProgress progress) {
    final solvedIndexes = <String, Set<int>>{};
    PuzzleId? lastSolved;
    DateTime? lastSolvedAt;

    for (final entry in progress.solved.entries) {
      final id = _parse(entry.key);
      if (id == null) continue;

      (solvedIndexes[SudokuProgress.bestTimeKey(id.spec, id.difficulty)] ??=
              <int>{})
          .add(id.index);

      final at = entry.value.solvedAt;
      if (at == null) continue;
      // The id breaks a tie, so that iterating a map — which has no order worth
      // relying on — cannot decide which size the daily card offers.
      if (lastSolvedAt == null ||
          at.isAfter(lastSolvedAt) ||
          (at == lastSolvedAt && id.value.compareTo(lastSolved!.value) < 0)) {
        lastSolvedAt = at;
        lastSolved = id;
      }
    }

    final continuePuzzle = _continueFrom(progress.inProgress);
    return SudokuMenu._(
      solvedIndexes,
      progress: progress,
      continuePuzzle: continuePuzzle,
      lastPlayed: continuePuzzle ?? lastSolved,
    );
  }

  /// The history this reads.
  final SudokuProgress progress;

  /// The puzzle the *Keep going* card offers, or null when nothing is
  /// half-finished.
  ///
  /// **The one with the most time on its clock**, ties broken by the id, and
  /// not "the one played last" — which is what a child means, and what a save
  /// cannot say: [PuzzleInProgress] carries no timestamp, and the puzzle cache's
  /// recency is in memory only (`PLAN-phase-3.md` §4.8), so there is nothing on
  /// disk to sort by. The closest thing a save does hold is how long each board
  /// was played for, and the one with the most time in it is the one worth
  /// coming back to. An in-memory "last played" would be exact for as long as
  /// the app runs and empty after the force-quit this card exists for.
  final PuzzleId? continuePuzzle;

  /// The most recent puzzle this profile has anything to say about, or null for
  /// a profile that has played none.
  ///
  /// [continuePuzzle] first — a board left half-done is the strongest evidence
  /// a save carries — then the solved puzzle with the latest `solvedAt`.
  final PuzzleId? lastPlayed;

  /// Solved indexes by [SudokuProgress.bestTimeKey], so [nextPuzzle] and
  /// [solvedCount] cost nothing per build.
  final Map<String, Set<int>> _solvedIndexes;

  /// Days in a row, as the daily card shows it.
  int get streak => progress.dailyStreak.current;

  /// The size the menu opens on: the one last played, else 9x9.
  SudokuSpec get lastSpec => lastPlayed?.spec ?? defaultSudokuSpec;

  /// The difficulty the daily card offers, before it is clamped to a size.
  Difficulty get lastDifficulty =>
      lastPlayed?.difficulty ?? defaultSudokuDifficulty;

  /// Today's puzzle at [spec], where [dayIndex] is `dayIndexFor(now)`.
  ///
  /// Any size and difficulty counts towards the streak, so which one today's
  /// puzzle is asked at is a matter of taste rather than of arithmetic
  /// (`PLAN-phase-3.md` §4.7): it is the tier the child last played, at the
  /// size the menu is currently showing.
  PuzzleId dailyPuzzle(SudokuSpec spec, int dayIndex) =>
      PuzzleId(spec, dailyDifficultyFor(spec), dayIndex);

  /// [lastDifficulty], or the hardest tier [spec] has when it does not have
  /// that one — which is 6x6 for a child who last played 9x9 Expert.
  Difficulty dailyDifficultyFor(SudokuSpec spec) {
    final offered = difficultiesFor(spec);
    return offered.contains(lastDifficulty) ? lastDifficulty : offered.last;
  }

  /// The puzzle a difficulty row launches: the lowest index this profile has
  /// not solved.
  ///
  /// A half-finished one is offered again rather than skipped — the play screen
  /// resumes it from the save, which is what a child tapping the tier they were
  /// last playing expects.
  PuzzleId nextPuzzle(SudokuSpec spec, Difficulty difficulty) {
    final solved = _solvedIndexes[SudokuProgress.bestTimeKey(spec, difficulty)];
    var index = 0;
    while (solved != null &&
        index < PuzzleId.maxPuzzleIndex &&
        solved.contains(index)) {
      index++;
    }
    return PuzzleId(spec, difficulty, index);
  }

  /// How many puzzles of this size and difficulty this profile has finished.
  int solvedCount(SudokuSpec spec, Difficulty difficulty) =>
      _solvedIndexes[SudokuProgress.bestTimeKey(spec, difficulty)]?.length ?? 0;

  /// The best time for this size and difficulty in milliseconds, or null where
  /// none has been set.
  int? bestTimeMs(SudokuSpec spec, Difficulty difficulty) =>
      progress.bestTimeMs[SudokuProgress.bestTimeKey(spec, difficulty)];

  /// The in-progress entry with the most time on its clock, or null when there
  /// is none. See [continuePuzzle] for why that is the rule.
  static PuzzleId? _continueFrom(Map<String, PuzzleInProgress> inProgress) {
    PuzzleId? best;
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

  /// [id] as a [PuzzleId], or null for one this build cannot spell.
  ///
  /// A hand-edited save is the only way to get one, and dropping the entry is
  /// the whole of the handling: the alternative is a menu that throws in front
  /// of a child rather than one card short (`AGENTS.md`).
  static PuzzleId? _parse(String id) {
    try {
      return PuzzleId.parse(id);
    } on FormatException {
      return null;
    }
  }
}
