// What one finished arcade run reports to `ProgressRepository`
// (`PLAN-phase-4.md` §4.9).
//
// A game reports one of these on game over and on quit alike — a run stopped
// early is still a run (`PLAN-phase-4.md` §4.8) — and the repository decides
// what to keep from it: `ProgressRepository.recordArcadeResult` turns it into
// a capped, per-mode `HighScore` and an addition to the lifetime kill count.
// Nothing here is stored as its own shape; `HighScore` and
// `ArcadeGameProgress` (`core/storage/save_data.dart`) are.
//
// Declared here rather than in `core/storage` because it belongs to the
// arcade, not to storage in general: any later game in `PLAN.md` §4.4 reports
// through the same type, the way every game shares `GameShell`
// (`PLAN-phase-4.md` §5).

/// One run of one arcade game, as it ended.
class ArcadeResult {
  const ArcadeResult({
    required this.score,
    this.wave = 0,
    this.kills = 0,
    this.easy = false,
    this.counting = false,
    this.length = 0,
  });

  /// Points scored this run.
  final int score;

  /// The wave, level or round reached. Zero where a game has no such thing.
  final int wave;

  /// Aliens (or the equivalent) destroyed this run, added to the profile's
  /// lifetime count regardless of whether the run made the high-score table.
  final int kills;

  /// Whether the run was played in easy mode. Carried onto the [HighScore] it
  /// produces, so the top five is kept separately per mode.
  final bool easy;

  /// Whether the run was a Snake counting run. Carried onto the [HighScore]
  /// it produces, so the top five is kept separately per `(easy, counting)`
  /// pair (`PLAN-phase-7-snake.md` §4.8). Always false for every game but
  /// Snake.
  final bool counting;

  /// How long the snake grew this run. `ProgressRepository.recordArcadeResult`
  /// raises `ArcadeGameProgress.bestLength` by `max` regardless of [score], so
  /// the longest snake a profile has ever grown is never lost to a run that
  /// scored nothing (`PLAN-phase-7-snake.md` §4.8). Always zero for every game
  /// but Snake.
  final int length;

  @override
  bool operator ==(Object other) =>
      other is ArcadeResult &&
      other.score == score &&
      other.wave == wave &&
      other.kills == kills &&
      other.easy == easy &&
      other.counting == counting &&
      other.length == length;

  @override
  int get hashCode => Object.hash(score, wave, kills, easy, counting, length);
}
