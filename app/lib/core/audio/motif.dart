/// Every sound in the app, and the asset each one is.
///
/// `PLAN-phase-5.md` §4.2. Six are Sudoku's, synthesised by
/// `tool/audio/generate_motifs.py` into `assets/audio/sudoku/`; nine are
/// Invaders' `arcade/` set (`PLAN-phase-5.md` PR 3); four are Snake's
/// `snake/` set (`PLAN-phase-7-snake.md` §4.10). There is no `isMusic`:
/// `settings.sound` gates all nineteen, because there is no music
/// (`PLAN-phase-5.md` §4.6).
enum Motif {
  sudokuPlace('sudoku/place.wav'),
  sudokuCorrect('sudoku/correct.wav'),
  sudokuWrong('sudoku/wrong.wav'),
  sudokuErase('sudoku/erase.wav'),
  sudokuHint('sudoku/hint.wav'),
  sudokuComplete('sudoku/complete.wav'),
  arcadePlayerShoot('arcade/player_shoot.wav'),
  arcadePlayerHit('arcade/player_hit.wav'),
  arcadeAlienShoot('arcade/alien_shoot.wav'),
  arcadeAlienHit('arcade/alien_hit.wav'),
  arcadeAlienMove('arcade/alien_move.wav'),
  arcadeUfoLoop('arcade/ufo_loop.wav'),
  arcadeUfoHit('arcade/ufo_hit.wav'),
  arcadeWaveClear('arcade/wave_clear.wav'),
  arcadeExtraLife('arcade/extra_life.wav'),
  snakeEat('snake/eat.wav'),
  snakeNotYet('snake/not_yet.wav'),
  snakeCrash('snake/crash.wav'),
  snakeLevelClear('snake/level_clear.wav');

  const Motif(this.asset);

  /// The file under `assets/audio/`.
  final String asset;

  /// The nine arcade motifs, in the same order as `PLAN-phase-5.md` §4.1's
  /// table. What `InvadersScreen` hands `AppAudio.preload` on entry, so a
  /// run pays no first-play decode cost for its own sounds mid-game — and
  /// not [values] entire, which would spend that same budget decoding motifs
  /// an Invaders run can never play.
  static const List<Motif> arcadeSet = [
    arcadePlayerShoot,
    arcadePlayerHit,
    arcadeAlienShoot,
    arcadeAlienHit,
    arcadeAlienMove,
    arcadeUfoLoop,
    arcadeUfoHit,
    arcadeWaveClear,
    arcadeExtraLife,
  ];

  /// The four snake motifs, in the same order as `PLAN-phase-7-snake.md`
  /// §4.10's table. What `SnakeScreen` hands `AppAudio.preload` on entry, for
  /// the same reason [arcadeSet] exists.
  static const List<Motif> snakeSet = [
    snakeEat,
    snakeNotYet,
    snakeCrash,
    snakeLevelClear,
  ];
}
