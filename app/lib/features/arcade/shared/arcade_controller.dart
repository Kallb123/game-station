// What `GameShell` drives, and what it reads back (`PLAN-phase-4.md` §4.8).
//
// One interface rather than one `GameShell` per game: the shell owns the HUD,
// pause, quit confirmation and the game-over card, and everything it needs
// from a specific game — its score and lives, its view, where input goes, and
// what to store when the run ends — comes through these eight members.
// Nothing is here that `GameShell` does not call; a member a second game
// would need and this one would not is `PLAN-phase-4.md` §2's signal to
// reshape this then, with two games in hand rather than one and a guess.

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, Widget;

import 'arcade_result.dart';
import 'pad_input.dart';

/// Score, lives and wave, as `GameShell` draws them above the field.
///
/// Value equality is why this can sit behind a [ValueNotifier]: a game whose
/// score has not changed this frame produces an equal [ArcadeHud], which
/// [ValueNotifier] does not renotify for — the HUD text only rebuilds on a
/// real change, not on every fixed step.
@immutable
class ArcadeHud {
  const ArcadeHud({
    required this.score,
    this.lives = 0,
    this.wave = 0,
    this.note = '',
  });

  /// Points scored so far this run.
  final int score;

  /// Lives left. Zero where a game has no such thing.
  final int lives;

  /// The wave, level or round reached. Zero where a game has no such thing.
  final int wave;

  /// A short game-specific line drawn after the wave and folded into the
  /// same `Semantics` label — Snake's `Next 7` (`PLAN-phase-7-snake.md`
  /// §4.7). Empty draws nothing; Invaders never sets this.
  final String note;

  @override
  bool operator ==(Object other) =>
      other is ArcadeHud &&
      other.score == score &&
      other.lives == lives &&
      other.wave == wave &&
      other.note == note;

  @override
  int get hashCode => Object.hash(score, lives, wave, note);
}

/// What `GameShell` needs from one arcade game, and nothing it does not
/// (`PLAN-phase-4.md` §4.8).
///
/// A game implements this once and `GameShell` wraps it; `InvadersGame` is
/// the first, and every game `PLAN.md` §4.4 adds later is another.
abstract interface class ArcadeGameController {
  /// Score, lives and wave, for the HUD row above the field.
  ValueListenable<ArcadeHud> get hud;

  /// Flips to `true` the moment the run ends — a lost last life, or whatever
  /// a later game's equivalent is. `GameShell` writes [result] to the save
  /// the first time this becomes `true`, and shows the game-over card.
  ValueListenable<bool> get isOver;

  /// The game's own view — a `GameWidget` for `InvadersGame` — built with
  /// [context] rather than cached, since a game may need the theme.
  Widget buildView(BuildContext context);

  /// Where `GameShell` writes what `OnScreenPad` and the keyboard mirror
  /// produce, and what the game reads back each fixed step.
  ValueNotifier<PadInput> get input;

  /// Stops the game clock. Called from the pause button, from `P`/`Escape`,
  /// and from an `AppLifecycleListener` on `inactive` and `paused`
  /// (`PLAN.md` §4.2, `PLAN-phase-4.md` §4.8).
  void pause();

  /// Starts the game clock again, without replaying the time spent paused.
  void resume();

  /// Discards the current run and begins a new one with a fresh seed, for
  /// the game-over card's *Play again*.
  void restart();

  /// What the current run is worth right now — score, wave and kills so far,
  /// and which mode it was played in. Read on game over and on quit alike: a
  /// run stopped early is still a run (`PLAN-phase-4.md` §4.8).
  ArcadeResult get result;
}
