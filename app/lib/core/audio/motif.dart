/// Every sound in the app, and the asset each one is.
///
/// `PLAN-phase-5.md` §4.2. Six of the fifteen files exist today, synthesised by
/// `tool/audio/generate_motifs.py` into `assets/audio/sudoku/`; the nine
/// `arcade/` ones arrive with `PLAN-phase-5.md`'s PR 3 and are named here first
/// so PR 3 needs no Dart change and PR 4's event map has something to point at.
/// There is no `isMusic`: `settings.sound` gates all fifteen, because there is
/// no music (`PLAN-phase-5.md` §4.6).
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
  arcadeExtraLife('arcade/extra_life.wav');

  const Motif(this.asset);

  /// The file under `assets/audio/`.
  final String asset;
}
