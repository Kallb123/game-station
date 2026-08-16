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
import 'package:flutter/foundation.dart'
    show ValueListenable, visibleForTesting;

import '../shared/pad_input.dart';
import 'model/invaders_sim.dart';
import 'model/sprites.dart' as sprites;

/// A frame that arrives this late — a garbage-collection pause, a resumed
/// app, a debugger breakpoint — asks for far more steps than a frame can
/// afford (`PLAN-phase-4.md` §4.2). Past this many, the remainder is dropped
/// rather than chased: losing time reads to a child as a shorter pause,
/// where chasing it would fire shots nobody saw coming.
const int maxStepsPerFrame = 8;

/// Drives [InvadersSim] on Flame's frame loop and draws its current state.
///
/// Takes every colour it draws with at construction, rather than reading
/// `Theme.of(context)`: a `FlameGame` is not built with a `BuildContext`
/// (`PLAN-phase-4.md` §4.5).
class InvadersGame extends FlameGame {
  InvadersGame({required this.sim, required this.input, required Color color})
    : _field = _InvadersField(sim: sim, color: color),
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
  /// counter lives here; [InvadersGame] only reads it.
  final InvadersSim sim;

  /// Where this frame's [PadInput] comes from — `OnScreenPad` from PR 5, this
  /// screen's temporary keyboard handling until then, or a test.
  final ValueListenable<PadInput> input;

  final _InvadersField _field;

  /// Repaints every sprite in this colour from the next frame on.
  ///
  /// A `FlameGame` is constructed once but a screen built over it can be
  /// rebuilt many times — the theme changing under `ThemeMode.system`, in
  /// particular — so the colour taken at construction (`PLAN-phase-4.md`
  /// §4.5) needs a way back in rather than only a way in.
  set color(Color value) => _field.color = value;

  /// Seconds of frame time not yet turned into an [InvadersSim.step] call.
  ///
  /// A running total rather than something decremented back towards zero —
  /// see `invaders_sim_equivalence_test.dart`'s header for why the
  /// subtractive form this file's plan sketch first used is the wrong one:
  /// it rounds two frame rates to a different leftover remainder at exactly
  /// the point their totals should agree.
  double _elapsed = 0;

  /// How many fixed-step-worths of [_elapsed] have been accounted for —
  /// either by a real [InvadersSim.step] call, or by [maxStepsPerFrame]
  /// dropping the rest of a backlog. Distinct from [_totalSteps]: after a
  /// drop this jumps ahead of the steps actually taken, which is the point —
  /// it is what stops the next frame trying to make up the difference.
  int _consumedSteps = 0;

  /// The steps [update] has actually fed to [InvadersSim.step] — a test
  /// seam, in the same spirit as `InvadersSim`'s own `debugSetAliveRows`: it
  /// lets a test assert the accumulator's arithmetic directly, rather than
  /// through a side effect on the sim that would also depend on what a step
  /// happened to do.
  int _totalSteps = 0;

  @visibleForTesting
  int get debugStepsDone => _totalSteps;

  @override
  void update(double dt) {
    super.update(dt);
    // Guards against a test calling `update` directly while `paused`: the
    // real game loop never does (`pauseEngine` stops it being called at
    // all), but nothing here should assume its caller.
    if (paused) return;

    _elapsed += dt;
    final target = (_elapsed / InvadersSim.fixedStep).floor();
    var steps = 0;
    while (_consumedSteps < target && steps < maxStepsPerFrame) {
      sim.step(input.value);
      _consumedSteps++;
      _totalSteps++;
      steps++;
    }
    // The clamp above stopped short of `target`: drop the backlog rather than
    // letting the next frame try to make it up in one go (`PLAN-phase-4.md`
    // §4.2).
    if (steps == maxStepsPerFrame) _consumedSteps = target;
  }

  @override
  void resumeEngine() {
    // The delta across a pause is not game time (`PLAN-phase-4.md` §4.5):
    // without this, backgrounding the app for a minute and returning would
    // ask next frame for the thousands of steps that minute is worth, which
    // the clamp above would then have to drop anyway. Zeroing here reaches
    // the same outcome without a frame that briefly owes them.
    _elapsed = 0;
    _consumedSteps = 0;
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

  final InvadersSim sim;
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
