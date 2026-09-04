// The Flame layer: the frame-to-fixed-step accumulator and the single render
// pass over `SnakeSim`'s current state (`PLAN-phase-7-snake.md` §3, §4.2,
// §4.5) — the same split `invaders_game.dart` draws, on the same shared
// accumulator (`shared/fixed_step.dart`) rather than a second copy of it.
//
// `SnakeGame` holds no game state beyond the accumulator — score, lives, the
// body, the targets and everything else stay in `sim`, which this file only
// reads. `_SnakeField`, the one component this adds to the world, holds none
// either: every `render` call reads `sim` fresh, so nothing here can drift
// out of step with it (`PLAN-phase-4.md` §7's "the simulation and the
// renderer drift into two copies of the state" risk, unchanged for the
// second game).
//
// Sound and haptics are PR 6's (`PLAN-phase-7-snake.md` §4.10, §6): this PR
// drains no `SnakeEvent`, because there is no `Motif` for one yet to drain
// into — `SnakeGame` gains that once PR 6 adds the four motifs.

import 'dart:ui';

import 'package:flame/camera.dart';
import 'package:flame/components.dart' show Component;
import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
import 'package:flutter/widgets.dart' show BuildContext, Widget;

import '../shared/arcade_controller.dart';
import '../shared/arcade_result.dart';
import '../shared/fixed_step.dart';
import '../shared/pad_input.dart';
import 'model/counting.dart';
import 'model/digits.dart';
import 'model/snake_rules.dart';
import 'model/snake_sim.dart';

/// Units per glyph pixel: a three-digit number is 11 glyph pixels wide
/// including gaps (`PLAN-phase-7-snake.md` §4.5), and `11 * 1.4 == 15.4`
/// units fits inside the 16-unit cell it is centred in.
const double _glyphScale = 1.4;
const int _glyphWidth = 3;
const int _glyphHeight = 5;
const int _glyphGap = 1;

/// The pixel width, including inter-digit gaps, of [value]'s numeral before
/// it is scaled by [_glyphScale] — a pure function of its digit count.
int numeralPixelWidth(int value) {
  final digits = value.toString().length;
  return digits * _glyphWidth + (digits - 1) * _glyphGap;
}

/// The rectangle [value]'s numeral draws inside, in cell-local units — `(0,
/// 0)` to `(cellSize, cellSize)` — centred on both axes. A pure function so
/// `snake_game_test.dart` can assert it stays inside the cell for 7, 42 and
/// 200 — the widths ordinary play reaches (`PLAN-phase-7-snake.md` §4.5, §8)
/// — without rendering anything.
Rect numeralExtent(int value) {
  final width = numeralPixelWidth(value) * _glyphScale;
  final height = _glyphHeight * _glyphScale;
  return Rect.fromLTWH(
    (cellSize - width) / 2,
    (cellSize - height) / 2,
    width,
    height,
  );
}

/// Drives [SnakeSim] on Flame's frame loop, draws its current state, and is
/// the second [ArcadeGameController] `GameShell` wraps
/// (`PLAN-phase-7-snake.md` §4.5).
///
/// Takes every colour it draws with at construction, rather than reading
/// `Theme.of(context)`: a `FlameGame` is not built with a `BuildContext`
/// (`PLAN-phase-4.md` §4.5).
class SnakeGame extends FlameGame implements ArcadeGameController {
  SnakeGame({
    required SnakeSim sim,
    required this.seed,
    required this.input,
    required Color color,
  }) : _sim = sim,
       _field = _SnakeField(sim: sim, color: color),
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
    // — world (0, 0) then lands exactly on the viewport's top-left corner
    // (`invaders_game.dart`'s own constructor comment gives the same reason).
    camera.viewfinder.position = Vector2(fieldWidth / 2, fieldHeight / 2);
    world.add(_field);
  }

  /// The run this game is drawing and driving. Every position, timer and
  /// counter lives here; [SnakeGame] only reads it. Replaced wholesale by
  /// [restart], which is why this is not `final`.
  SnakeSim _sim;

  /// The current run, for a test that wants more than [hud] and [isOver]
  /// expose — `snake_game_test.dart` reaches `sim.debugSetBody` this way.
  SnakeSim get sim => _sim;

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

  final _SnakeField _field;

  @override
  Widget buildView(BuildContext context) =>
      // `autofocus: false`: `GameWidget` requests its own focus by default,
      // which would win it away from `GameShell`'s `Focus` node the moment
      // the screen builds — declining that here is what lets the outer node
      // keep it, so the keyboard mirror above this game keeps being called
      // (`invaders_game.dart`'s own `buildView` gives the same reason).
      GameWidget(game: this, autofocus: false);

  @override
  void pause() => pauseEngine();

  @override
  void resume() => resumeEngine();

  @override
  void restart() {
    _sim = SnakeSim(rules: _sim.rules, counting: _sim.counting, seed: seed());
    _field.sim = _sim;
    _accumulator.reset();
    hud.value = _hudOf(_sim);
    isOver.value = false;
    resumeEngine();
  }

  @override
  ArcadeResult get result => ArcadeResult(
    score: _sim.score,
    wave: _sim.level,
    kills: _sim.eaten,
    easy: identical(_sim.rules, SnakeRules.easy),
    counting: _sim.counting != SnakeCounting.off,
    length: _sim.longest,
  );

  static ArcadeHud _hudOf(SnakeSim sim) => ArcadeHud(
    score: sim.score,
    lives: sim.lives,
    wave: sim.level,
    // `Next 7`, what a child who cannot yet read the numeral at arm's length
    // has, and what a screen reader says (`PLAN-phase-7-snake.md` §4.3).
    // Empty in classic mode, where `nextValue` is always 0.
    note: sim.counting == SnakeCounting.off ? '' : 'Next ${sim.nextValue}',
  );

  /// Repaints every cell in this colour from the next frame on — the same
  /// reshape hook `invaders_game.dart`'s own `color` setter documents, for
  /// the same `ThemeMode.system` reason.
  set color(Color value) => _field.color = value;

  /// Turns frame deltas into fixed steps — `shared/fixed_step.dart`'s running
  /// total, shared with `InvadersGame` (`PLAN-phase-7-snake.md` §4.7).
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

    // Skipped when nothing stepped, the same reason `invaders_game.dart`
    // skips it: a run that is over settles at one unchanging [ArcadeHud]
    // forever, and there is no reason to keep rebuilding it every frame
    // after that.
    if (steps > 0) {
      hud.value = _hudOf(_sim);
      if (_sim.isOver) isOver.value = true;
    }
  }

  @override
  void resumeEngine() {
    // The delta across a pause is not game time (`PLAN-phase-4.md` §4.5):
    // without this, backgrounding the app for a minute and returning would
    // ask next frame for the thousands of steps that minute is worth, which
    // the clamp in `shared/fixed_step.dart` would then have to drop anyway.
    // Resetting here reaches the same outcome without a frame that briefly
    // owes them.
    _accumulator.reset();
    super.resumeEngine();
  }
}

/// The colour a numeral or a pair of eyes draws in against [base] — black or
/// white, whichever [Color.computeLuminance] says contrasts more, so a
/// numeral reads at full contrast regardless of which palette role [base]
/// turns out to be (`PLAN-phase-7-snake.md` §4.5).
Color _contrastColor(Color base) => base.computeLuminance() > 0.5
    ? const Color(0xFF000000)
    : const Color(0xFFFFFFFF);

/// A decoy's dimmed shade of [base] — outlined rather than filled, so it
/// reads as scenery rather than as something to aim for
/// (`PLAN-phase-7-snake.md` §4.5).
Color _dimColor(Color base) => base.withValues(alpha: 0.4);

/// Where each D-pad direction places the pair of eyes on the head cell, in
/// cell-local units — toward the edge the snake is heading, so which way it
/// is going is visible without inferring it from movement
/// (`PLAN-phase-7-snake.md` §4.5).
const Map<SnakeDirection, List<Offset>> _eyeOffsets = {
  SnakeDirection.up: [Offset(4, 3), Offset(9, 3)],
  SnakeDirection.down: [Offset(4, 10), Offset(9, 10)],
  SnakeDirection.left: [Offset(3, 4), Offset(3, 9)],
  SnakeDirection.right: [Offset(10, 4), Offset(10, 9)],
};

const double _eyeSize = 3;

/// Draws the body, the head and the targets in one pass. Holds nothing of
/// its own — every field read below comes from [sim] at render time, not
/// from state kept here (`invaders_game.dart`'s `_InvadersField` draws the
/// same boundary).
class _SnakeField extends Component {
  _SnakeField({required this.sim, required Color color})
    : _paint = Paint()..color = color;

  /// Replaced by [SnakeGame.restart], which is why this is not `final`: the
  /// field draws whichever run is current rather than the one it was built
  /// with.
  SnakeSim sim;
  final Paint _paint;

  set color(Color value) => _paint.color = value;

  @override
  void render(Canvas canvas) {
    _drawTargets(canvas);
    _drawBody(canvas);
  }

  /// Targets are laid out `[next, ...decoys]` by `SnakeSim._spawnTargets`
  /// and never reordered in place, so index 0 is always the edible one
  /// (`PLAN-phase-7-snake.md` §4.3) — the next target is filled and, in
  /// counting mode, carries its numeral at full contrast; every other target
  /// is outlined and dim.
  void _drawTargets(Canvas canvas) {
    final targets = sim.targets;
    final counting = sim.counting != SnakeCounting.off;
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      final rect = _cellRect(target.cell);
      if (i == 0) {
        canvas.drawRect(rect, _paint);
        if (counting) {
          _drawNumber(
            canvas,
            target.value,
            target.cell,
            _contrastColor(_paint.color),
          );
        }
      } else {
        final dim = _dimColor(_paint.color);
        canvas.drawRect(
          rect.deflate(1),
          Paint()
            ..color = dim
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
        if (counting) _drawNumber(canvas, target.value, target.cell, dim);
      }
    }
  }

  void _drawBody(Canvas canvas) {
    final body = sim.body;
    for (final cell in body) {
      canvas.drawRect(_cellRect(cell), _paint);
    }
    if (body.isNotEmpty) _drawEyes(canvas, body.first, sim.heading);
  }

  void _drawEyes(Canvas canvas, Cell head, SnakeDirection heading) {
    final eyePaint = Paint()..color = _contrastColor(_paint.color);
    final origin = Offset(head.col * cellSize, head.row * cellSize);
    for (final offset in _eyeOffsets[heading]!) {
      canvas.drawRect(
        Rect.fromLTWH(
          origin.dx + offset.dx,
          origin.dy + offset.dy,
          _eyeSize,
          _eyeSize,
        ),
        eyePaint,
      );
    }
  }

  /// Draws [value] centred in [cell], from [digitGlyphs]' bitmasks — the
  /// same rectangles-from-a-bitmap trick `invaders_game.dart`'s sprites use,
  /// scaled by [_glyphScale] and positioned by [numeralExtent].
  void _drawNumber(Canvas canvas, int value, Cell cell, Color color) {
    final paint = Paint()..color = color;
    final extent = numeralExtent(value);
    final origin = Offset(
      cell.col * cellSize + extent.left,
      cell.row * cellSize + extent.top,
    );
    final digits = value.toString().split('').map(int.parse).toList();
    for (var d = 0; d < digits.length; d++) {
      final glyph = digitGlyphs[digits[d]];
      final digitX = origin.dx + d * (_glyphWidth + _glyphGap) * _glyphScale;
      for (var row = 0; row < glyph.length; row++) {
        final bits = glyph[row];
        for (var col = 0; col < _glyphWidth; col++) {
          if ((bits >> (_glyphWidth - 1 - col)) & 1 == 0) continue;
          canvas.drawRect(
            Rect.fromLTWH(
              digitX + col * _glyphScale,
              origin.dy + row * _glyphScale,
              _glyphScale,
              _glyphScale,
            ),
            paint,
          );
        }
      }
    }
  }
}

Rect _cellRect(Cell cell) =>
    Rect.fromLTWH(cell.col * cellSize, cell.row * cellSize, cellSize, cellSize);
