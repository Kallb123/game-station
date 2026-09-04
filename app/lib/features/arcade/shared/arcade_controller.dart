// What `GameShell` drives, and what it reads back (`PLAN-phase-4.md` §4.8).
//
// One interface rather than one `GameShell` per game: the shell owns the HUD,
// pause, quit confirmation and the game-over card, and everything it needs
// from a specific game — its score and lives, its view, where input goes, and
// what to store when the run ends — comes through these eight members.
// Nothing is here that `GameShell` does not call; a member a second game
// would need and this one would not is `PLAN-phase-4.md` §2's signal to
// reshape this then, with two games in hand rather than one and a guess.

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show BuildContext, Widget;

import 'arcade_result.dart';
import 'pad_input.dart';

/// The fixed-resolution field's own background, drawn explicitly by each
/// game's field component before anything else — the same black either game
/// drew by default when nothing painted the empty cells at all, now stated
/// rather than incidental (`PLAN.md` §7's phase-7 closing note).
const Color arcadeFieldColor = Color(0xFF000000);

/// The letterbox area outside the field, on a window whose aspect ratio does
/// not match [arcadeFieldColor]'s. [Game.backgroundColor] defaults to the
/// same black the field used to leave undrawn, so the two were
/// indistinguishable — on a tall phone in particular, where Snake wraps at
/// the field's edge, a child could not see where that edge was. Grey against
/// black gives the field a visible boundary on every game built on
/// `CameraComponent.withFixedResolution`, not only Snake, so both games in
/// the arcade take it.
const Color arcadeLetterboxColor = Color(0xFF3A3D42);

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
