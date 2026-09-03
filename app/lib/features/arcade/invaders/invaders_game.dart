// The Flame layer: the frame-to-fixed-step accumulator and the single render
// pass over `InvadersSim`'s current state (`PLAN-phase-4.md` §3, §4.2, §4.5).
//
// `InvadersGame` holds no game state beyond the accumulator — score, lives,
// alien positions and everything else stay in `sim`, which this file only
// reads. `_InvadersField`, the one component this adds to the world, holds
// none either: every `render` call reads `sim` fresh, so there is nothing
// here that could drift out of step with it (`PLAN-phase-4.md` §7's "the
// simulation and the renderer drift into two copies of the state" risk).
//
// Differs from §4.5's sketch in one way: rather than overriding
// `FlameGame.render` directly, the sim is drawn by one child `Component`
// added to `world`, so the camera's `FixedResolutionViewport`
// letterbox-and-scale transform — the mechanism `PLAN.md` §4.1's "a phone
// and a tablet run the same game" rests on — applies to it for free instead
// of being reimplemented by hand around a manually-drawn canvas.

import 'dart:ui';

import 'package:flame/camera.dart';
import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext, Widget;

import '../../../core/audio/app_audio.dart';
import '../../../core/audio/motif.dart';
import '../../../core/haptics.dart';
import '../shared/arcade_controller.dart';
import '../shared/arcade_result.dart';
import '../shared/fixed_step.dart';
import '../shared/pad_input.dart';
import 'model/invaders_rules.dart';
import 'model/invaders_sim.dart';
import 'model/sprites.dart' as sprites;

/// Drives [InvadersSim] on Flame's frame loop, draws its current state, and
/// is the first [ArcadeGameController] `GameShell` wraps
/// (`PLAN-phase-4.md` §4.8).
///
/// Takes every colour it draws with at construction, rather than reading
/// `Theme.of(context)`: a `FlameGame` is not built with a `BuildContext`
/// (`PLAN-phase-4.md` §4.5).
class InvadersGame extends FlameGame implements ArcadeGameController {
  InvadersGame({
    required InvadersSim sim,
    required this.seed,
    required this.input,
    required Color color,
    required this.audio,
    required this.haptics,
  }) : _sim = sim,
       _field = _InvadersField(sim: sim, color: color),
       hud = ValueNotifier(_hudOf(sim)),
       isOver = ValueNotifier(sim.isOver),
       super(
         camera: CameraComponent.withFixedResolution(
           width: fieldWidth,
           height: fieldHeight,
         ),
       ) {
    // The default viewfinder centres world point (0, 0) in the viewport; the
    // sim's field runs from (0, 0) to (fieldWidth, fieldHeight), so centring
    // the field's own centre point is what makes the two rectangles coincide
    // — world (0, 0) then lands exactly on the viewport's top-left corner.
    camera.viewfinder.position = Vector2(fieldWidth / 2, fieldHeight / 2);
    world.add(_field);
  }

  /// The run this game is drawing and driving. Every position, timer and
  /// counter lives here; [InvadersGame] only reads it. Replaced wholesale by
  /// [restart], which is why this is not `final`.
  InvadersSim _sim;

  /// The current run, for a test or a caller that wants more than [hud] and
  /// [isOver] expose — `invaders_screen_test.dart` reads `sim.player.x` this
  /// way.
  InvadersSim get sim => _sim;

  /// Where every [InvadersEvent] this game drains is turned into a [Motif]
  /// (`PLAN-phase-5.md` §4.4). Taken at construction like [color]: a
  /// `FlameGame` is not built with a `BuildContext` to read a provider from.
  final AppAudio audio;

  /// Buzzes the ship's destruction and the run's end — the two moments in an
  /// Invaders run worth feeling (`PLAN-phase-5.md` §4.5). Taken at
  /// construction for the same reason [audio] is.
  final AppHaptics haptics;

  /// A fresh seed for [restart] — the injected clock, the same way the first
  /// run's seed reaches this game (`PLAN-phase-4.md` §4.3), so a test can fix
  /// it and a child gets a different run each time.
  final int Function() seed;

  @override
  final ValueNotifier<PadInput> input;

  @override
  final ValueNotifier<ArcadeHud> hud;

  @override
  final ValueNotifier<bool> isOver;

  final _InvadersField _field;

  @override
  Widget buildView(BuildContext context) =>
      // `autofocus: false`: `GameWidget` requests its own focus by default,
      // which would win it away from `GameShell`'s `Focus` node the moment
      // the screen builds — declining that here is what lets the outer node
      // keep it, so the keyboard mirror above this game keeps being called.
      GameWidget(game: this, autofocus: false);

  @override
  void pause() {
    pauseEngine();
    // Not only the app going to the background (`app.dart`'s own lifecycle
    // listener already silences everything for that): the pause button and
    // `P`/`Escape` reach here too, and a paused game with the UFO still
    // warbling has not actually gone quiet (`PLAN-phase-5.md` §4.4).
    audio.stopAll();
  }

  @override
  void resume() => resumeEngine();

  @override
  void restart() {
    _sim = InvadersSim(
      rules: _sim.rules,
      seed: seed(),
      autoFire: _sim.autoFire,
    );
    _field.sim = _sim;
    _accumulator.reset();
    hud.value = _hudOf(_sim);
    isOver.value = false;
    resumeEngine();
  }

  @override
  ArcadeResult get result => ArcadeResult(
    score: _sim.score,
    wave: _sim.wave,
    kills: _sim.kills,
    easy: identical(_sim.rules, InvadersRules.easy),
  );

  static ArcadeHud _hudOf(InvadersSim sim) =>
      ArcadeHud(score: sim.score, lives: sim.lives, wave: sim.wave);

  /// Repaints every sprite in this colour from the next frame on.
  ///
  /// A `FlameGame` is constructed once but a screen built over it can be
  /// rebuilt many times — the theme changing under `ThemeMode.system`, in
  /// particular — so the colour taken at construction (`PLAN-phase-4.md`
  /// §4.5) needs a way back in rather than only a way in.
  set color(Color value) => _field.color = value;

  /// Turns frame deltas into fixed steps — `shared/fixed_step.dart`'s running
  /// total, shared with every other arcade game's Flame layer
  /// (`PLAN-phase-7-snake.md` §4.7).
  final FixedStepAccumulator _accumulator = FixedStepAccumulator();

  @visibleForTesting
  int get debugStepsDone => _accumulator.totalSteps;

  @override
  void update(double dt) {
    super.update(dt);
    // Guards against a test calling `update` directly while `paused`: the
    // real game loop never does (`pauseEngine` stops it being called at
    // all), but nothing here should assume its caller.
    if (paused) return;

    final steps = _accumulator.advance(dt);
    for (var i = 0; i < steps; i++) {
      _sim.step(input.value);
    }

    // Skipped when nothing stepped: a `ValueNotifier` already drops a write
    // that equals its current value, but a run that is over settles at one
    // unchanging [ArcadeHud] forever, and there is no reason to keep
    // rebuilding it every frame after that. A dropped backlog drops its
    // events with it for the same reason it drops everything else about
    // those steps: the frames they belonged to were never drawn
    // (`PLAN-phase-5.md` §4.4).
    if (steps > 0) {
      for (final event in _sim.drainEvents()) {
        _play(event);
      }
      hud.value = _hudOf(_sim);
      // `InvadersSim.step` is a no-op once `isOver`, so a UFO already in
      // flight when the run ends would never reach the `ufoLeft` event that
      // stops its loop — nothing left to drain it. Checked against the
      // notifier rather than a bare `if (_sim.isOver)` so this fires once, on
      // the frame the run actually ends, not on every frame after.
      //
      // `stopLoop`, not `stopAll`: the death that just ended the run played
      // its own one-shot motif from the same drained batch, above, and
      // `audio.play`'s deferred callback has not run yet at this point in
      // the same synchronous frame — `stopAll` would cancel it before it
      // ever sounded, silencing the very hit that is supposed to be the
      // ending (`PLAN-phase-5.md` §4.1: "the last player_hit plus the
      // game-over card is the ending"). The UFO loop is the one thing here
      // with no natural end of its own, so it is the one thing this stops.
      if (_sim.isOver && !isOver.value) audio.stopLoop(Motif.arcadeUfoLoop);
      if (_sim.isOver) isOver.value = true;
    }
  }

  /// Turns one [InvadersEvent] into the one [Motif] it names
  /// (`PLAN-phase-5.md` §4.4). The UFO's arrival and departure are the two
  /// that drive the loop rather than a one-shot; the rest play once.
  ///
  /// `ufoKilled` stops the loop too, not only `ufoLeft`: `InvadersSim`
  /// reschedules the UFO's timer only when it exits normally, so a kill is
  /// followed by a fresh spawn on the very next fixed step rather than a
  /// gap — leaving the loop playing on would happen to sound continuous
  /// either way, but stopping it explicitly here means that stays true by
  /// construction rather than by an incidental timer value elsewhere.
  void _play(InvadersEvent event) {
    switch (event) {
      case InvadersEvent.playerShot:
        audio.play(Motif.arcadePlayerShoot);
      case InvadersEvent.playerKilled:
        audio.play(Motif.arcadePlayerHit);
        // Also the run-ending blow: `InvadersSim` emits this same event
        // whether a life was lost or the last one was, so one call here
        // covers both moments §4.5's table lists.
        haptics.impact();
      case InvadersEvent.alienShot:
        audio.play(Motif.arcadeAlienShoot);
      case InvadersEvent.alienKilled:
        audio.play(Motif.arcadeAlienHit);
      case InvadersEvent.alienStep:
        audio.play(Motif.arcadeAlienMove);
      case InvadersEvent.ufoAppeared:
        audio.startLoop(Motif.arcadeUfoLoop);
      case InvadersEvent.ufoLeft:
        audio.stopLoop(Motif.arcadeUfoLoop);
      case InvadersEvent.ufoKilled:
        audio.stopLoop(Motif.arcadeUfoLoop);
        audio.play(Motif.arcadeUfoHit);
      case InvadersEvent.waveCleared:
        audio.play(Motif.arcadeWaveClear);
      case InvadersEvent.extraLife:
        audio.play(Motif.arcadeExtraLife);
    }
  }

  @override
  void resumeEngine() {
    // The delta across a pause is not game time (`PLAN-phase-4.md` §4.5):
    // without this, backgrounding the app for a minute and returning would
    // ask next frame for the thousands of steps that minute is worth, which
    // the clamp above would then have to drop anyway. Resetting here reaches
    // the same outcome without a frame that briefly owes them.
    _accumulator.reset();
    super.resumeEngine();
  }
}

/// Draws every alien, shot, bunker, the player and the UFO in one pass, as
/// the sprites' bitmasks say to (`PLAN-phase-4.md` §4.7): one rectangle per
/// set bit, at the current scale. Holds nothing of its own — every field
/// read below comes from [sim] at render time, not from state kept here.
class _InvadersField extends Component {
  _InvadersField({required this.sim, required Color color})
    : _paint = Paint()..color = color;

  /// Replaced by [InvadersGame.restart], which is why this is not `final`:
  /// the field draws whichever run is current rather than the one it was
  /// built with.
  InvadersSim sim;
  final Paint _paint;

  set color(Color value) => _paint.color = value;

  @override
  void render(Canvas canvas) {
    final aliens = sim.aliens;
    for (var row = 0; row < aliens.rows; row++) {
      final sprite = _alienSprite(row, aliens.rows);
      for (var col = 0; col < alienColumns; col++) {
        if (!aliens.isAliveAt(row, col)) continue;
        _drawBitmap(
          canvas,
          sprite,
          16,
          aliens.originX + col * alienColumnPitch,
          aliens.originY + row * alienRowPitch,
        );
      }
    }

    for (final bunker in sim.bunkers) {
      for (var row = 0; row < bunkerRows; row++) {
        final bits = bunker.blocks[row];
        for (var col = 0; col < bunkerColumns; col++) {
          if ((bits >> col) & 1 == 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              bunker.x + col * bunkerBlockSize,
              Bunker.y + row * bunkerBlockSize,
              bunkerBlockSize,
              bunkerBlockSize,
            ),
            _paint,
          );
        }
      }
    }

    for (final shot in sim.shots) {
      _drawBitmap(canvas, sprites.shot, 2, shot.x, shot.y);
    }

    if (sim.player.alive) {
      _drawBitmap(canvas, sprites.player, 16, sim.player.x, Player.y);
    }

    final ufo = sim.ufo;
    if (ufo != null) {
      _drawBitmap(canvas, sprites.ufo, 16, ufo.x, Ufo.y);
    }
  }

  /// The row banding `PLAN.md` §4.1 scores by — front row 10, next two 20,
  /// the rest 30 — mirrored here so the sprite drawn matches the score
  /// earned for it. Not read from `InvadersSim`, which keeps the banding
  /// private to its own scoring method; duplicating three lines of `if`s
  /// costs less than exporting it for one caller.
  List<int> _alienSprite(int row, int totalRows) {
    final distanceFromFront = totalRows - 1 - row;
    if (distanceFromFront <= 0) return sprites.alienFront;
    if (distanceFromFront <= 2) return sprites.alienMiddle;
    return sprites.alienBack;
  }

  /// Draws one set bit of [rows] as one field-unit rectangle, most
  /// significant bit leftmost — the convention `sprites.dart` documents.
  void _drawBitmap(
    Canvas canvas,
    List<int> rows,
    int width,
    double x,
    double y,
  ) {
    for (var r = 0; r < rows.length; r++) {
      final bits = rows[r];
      for (var c = 0; c < width; c++) {
        if ((bits >> (width - 1 - c)) & 1 == 0) continue;
        canvas.drawRect(Rect.fromLTWH(x + c, y + r, 1, 1), _paint);
      }
    }
  }
}
