// LEFT, RIGHT and FIRE (`PLAN-phase-4.md` §4.2, §4.6): three raw-`Listener`
// buttons rather than `GestureDetector`s, so the gesture arena never gets a
// chance to award a second finger to whichever button claimed the first
// (`PLAN.md` §4.2's "support two simultaneous touches").
//
// Each button tracks its own pointer id rather than a shared held flag, for
// the same reason in miniature: a second finger landing on FIRE while LEFT is
// held must not touch LEFT's state, which a single "something is down" flag
// could not tell apart.
//
// A sibling of the play field in a `Column` (the screen composes that, until
// `GameShell` does), not an overlay drawn over it — `PLAN-phase-4.md` §4.6
// notes that a pad with its own band does not need the transparency
// `PLAN.md` §4.2 asks of one drawn over the field.

import 'package:flutter/material.dart';

import '../../../core/haptics.dart';
import '../../../core/storage/save_data.dart' show PadSide;
import '../../../core/ui/tokens.dart';
import 'pad_input.dart';

/// Which buttons [OnScreenPad] draws (`PLAN-phase-7-snake.md` §4.6).
enum PadLayout {
  /// LEFT, RIGHT and FIRE — what phase 4 built and what Invaders keeps.
  lateral,

  /// UP, DOWN, LEFT and RIGHT in a diamond, no FIRE — Snake has nothing to
  /// fire.
  dPad,
}

/// How far each button's centre sits from the diamond's own centre, in dp.
///
/// Four [AppTapTargets.primary] (72 dp) circles placed 90 degrees apart
/// around a shared centre must keep every adjacent pair — which sit
/// `sqrt(2)` times [_dPadReach] apart, not [_dPadReach] itself — at least
/// 72 dp apart so neither circle draws into the other. `72 / sqrt(2)` is
/// that floor; the two extra dp are margin so rounding never lets two
/// circles just touch. This is `PLAN-phase-7-snake.md` §7's "compact diamond
/// with the buttons overlapping their corners" fallback: each button's
/// square *bounding box* overlaps its neighbours', but the drawn circles
/// inside those boxes never do — found necessary once `layout_sweep_test.dart`
/// covered `/arcade/snake` in landscape at 200% text scale, where the
/// original one-cell-gap grid (232 dp square) overflowed the field's
/// available height by 29 dp.
const double _dPadReach = 52.92;

/// The diamond's side, in dp — the smallest square that holds all four
/// buttons at [_dPadReach], the same square in both dimensions.
const double _dPadExtent = 2 * (_dPadReach + AppTapTargets.primary / 2);

/// LEFT, RIGHT and FIRE, or a four-way D-pad, below the play field.
///
/// [side] decides which side of the band the controls sit on. In
/// [PadLayout.lateral], LEFT and RIGHT always stay adjacent to each other and
/// only the two groups — movement and FIRE — swap ends, as one `Row` whose
/// children are reversed rather than two separate layouts
/// (`PLAN-phase-4.md` §4.6). [PadLayout.dPad] has one cluster rather than
/// two, so [side] instead names which side that cluster sits on
/// (`PLAN-phase-7-snake.md` §4.6).
class OnScreenPad extends StatefulWidget {
  const OnScreenPad({
    required this.input,
    required this.haptics,
    this.side = PadSide.right,
    this.axis = Axis.horizontal,
    this.layout = PadLayout.lateral,
    this.child,
    super.key,
  }) : assert(
         axis == Axis.horizontal || child != null,
         'a vertical pad needs the field to place between its two rails',
       );

  /// Written to on every button press and release, combining whichever
  /// directions and fire are currently held.
  final ValueNotifier<PadInput> input;

  /// Which side FIRE sits on in [PadLayout.lateral], or which side the D-pad
  /// itself sits on in [PadLayout.dPad] — mirrors a profile's stored
  /// `padSide` for a left-handed player.
  final PadSide side;

  /// [Axis.horizontal] (the default) draws the pad in one strip below the
  /// play field, as `PLAN.md` §4.2 sketches it.
  ///
  /// [Axis.vertical] draws two rails either side of [child] instead: a
  /// landscape field already letterboxes to empty space on both sides, which
  /// is where the pad goes rather than below a field with no room left to
  /// give it (`PLAN-phase-5.md` §4.8).
  final Axis axis;

  /// Which buttons this pad draws. Defaults to [PadLayout.lateral], today's
  /// pad, so every existing call site is unchanged (`PLAN-phase-7-snake.md`
  /// §4.7).
  final PadLayout layout;

  /// The play field, placed between the two rails. Only read when [axis] is
  /// [Axis.vertical], and required there.
  final Widget? child;

  /// Buzzes a press — not a release, which would double every tap
  /// (`PLAN-phase-5.md` §4.5).
  final AppHaptics haptics;

  /// Keys for finding each button in a test — by identity rather than by the
  /// icon it happens to draw today, which is otherwise the only handle a test
  /// has on a `Listener` with no text of its own.
  static const Key leftKey = ValueKey('OnScreenPad.left');
  static const Key rightKey = ValueKey('OnScreenPad.right');
  static const Key fireKey = ValueKey('OnScreenPad.fire');
  static const Key upKey = ValueKey('OnScreenPad.up');
  static const Key downKey = ValueKey('OnScreenPad.down');

  @override
  State<OnScreenPad> createState() => _OnScreenPadState();
}

class _OnScreenPadState extends State<OnScreenPad> {
  bool _up = false;
  bool _down = false;
  bool _left = false;
  bool _right = false;
  bool _fire = false;

  void _update({bool? up, bool? down, bool? left, bool? right, bool? fire}) {
    _up = up ?? _up;
    _down = down ?? _down;
    _left = left ?? _left;
    _right = right ?? _right;
    _fire = fire ?? _fire;
    widget.input.value = PadInput(
      up: _up,
      down: _down,
      left: _left,
      right: _right,
      fire: _fire,
    );
  }

  @override
  Widget build(BuildContext context) =>
      widget.layout == PadLayout.dPad ? _buildDPad() : _buildLateral();

  Widget _buildLateral() {
    final movement = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PadButton(
          key: OnScreenPad.leftKey,
          label: 'Left',
          icon: Icons.arrow_back,
          haptics: widget.haptics,
          onHeldChanged: (held) => _update(left: held),
        ),
        const SizedBox(width: AppSpacing.lg),
        _PadButton(
          key: OnScreenPad.rightKey,
          label: 'Right',
          icon: Icons.arrow_forward,
          haptics: widget.haptics,
          onHeldChanged: (held) => _update(right: held),
        ),
      ],
    );
    final fire = _PadButton(
      key: OnScreenPad.fireKey,
      label: 'Fire',
      icon: Icons.circle,
      haptics: widget.haptics,
      onHeldChanged: (held) => _update(fire: held),
    );
    final rails = widget.side == PadSide.right
        ? [movement, fire]
        : [fire, movement];

    if (widget.axis == Axis.horizontal) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: rails,
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rail(rails[0]),
        Expanded(child: widget.child!),
        _rail(rails[1]),
      ],
    );
  }

  Widget _buildDPad() {
    final dPad = _DPad(haptics: widget.haptics, onUpdate: _update);

    if (widget.axis == Axis.horizontal) {
      return Row(
        mainAxisAlignment: widget.side == PadSide.right
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [dPad],
      );
    }

    // The rail the D-pad does not occupy becomes an equal-width spacer
    // rather than collapsing to nothing, so the field stays centred instead
    // of sliding towards whichever side is empty (`PLAN-phase-7-snake.md`
    // §4.6).
    const spacer = SizedBox(width: _dPadExtent, height: _dPadExtent);
    final rails = widget.side == PadSide.right
        ? [spacer, dPad]
        : [dPad, spacer];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _rail(rails[0]),
        Expanded(child: widget.child!),
        _rail(rails[1]),
      ],
    );
  }

  // Stretched, so `Expanded(child: widget.child!)` gets the row's full
  // height for the field — but each rail is wrapped in its own `Center`
  // first, or that same stretch would hand its fixed-size buttons a tight
  // height too and force them to fill it, a 72 dp circle stretched into a
  // bar the height of the screen.
  Widget _rail(Widget buttons) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: buttons,
    ),
  );
}

/// UP, DOWN, LEFT and RIGHT in a diamond (`PLAN-phase-7-snake.md` §4.6), each
/// [_dPadReach] from the shared centre — the arrangement that puts each
/// arrow where its direction points, packed to [_dPadExtent]'s compact
/// footprint rather than a spaced-out 3x3 grid (`_dPadReach`'s own doc).
///
/// Each button is wrapped in a [ClipOval] here — and only here, not inside
/// [_PadButton] itself, which the lateral layout also uses and has no reason
/// to shrink from a square target to a circular one. [_dPadReach] only keeps
/// the four drawn *circles* apart; [_PadButton]'s own hit-test area is its
/// full 72 dp *square*, and at this reach adjacent squares still overlap by
/// design (`_dPadReach`'s doc). Left unclipped, a tap in that overlap —
/// visually well inside one button's circle — would resolve to whichever
/// button is later in this [Stack] instead, which is exactly the dropped
/// turn `PLAN-phase-7-snake.md` §7 calls out as its highest-severity risk.
/// [ClipOval] restricts each button's hit-test to the same circle it draws,
/// so a point belongs to at most one of them regardless of paint order.
class _DPad extends StatelessWidget {
  const _DPad({required this.haptics, required this.onUpdate});

  final AppHaptics haptics;
  final void Function({bool? up, bool? down, bool? left, bool? right}) onUpdate;

  /// A button's top-left corner, [_dPadReach] dp from the diamond's centre
  /// in the direction [dx], [dy] (each -1, 0 or 1) points.
  static double _left(double dx) =>
      _dPadExtent / 2 + dx * _dPadReach - AppTapTargets.primary / 2;
  static double _top(double dy) =>
      _dPadExtent / 2 + dy * _dPadReach - AppTapTargets.primary / 2;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: _dPadExtent,
    height: _dPadExtent,
    child: Stack(
      children: [
        Positioned(
          left: _left(0),
          top: _top(-1),
          child: ClipOval(
            child: _PadButton(
              key: OnScreenPad.upKey,
              label: 'Up',
              icon: Icons.arrow_upward,
              haptics: haptics,
              onHeldChanged: (held) => onUpdate(up: held),
            ),
          ),
        ),
        Positioned(
          left: _left(0),
          top: _top(1),
          child: ClipOval(
            child: _PadButton(
              key: OnScreenPad.downKey,
              label: 'Down',
              icon: Icons.arrow_downward,
              haptics: haptics,
              onHeldChanged: (held) => onUpdate(down: held),
            ),
          ),
        ),
        Positioned(
          left: _left(-1),
          top: _top(0),
          child: ClipOval(
            child: _PadButton(
              key: OnScreenPad.leftKey,
              label: 'Left',
              icon: Icons.arrow_back,
              haptics: haptics,
              onHeldChanged: (held) => onUpdate(left: held),
            ),
          ),
        ),
        Positioned(
          left: _left(1),
          top: _top(0),
          child: ClipOval(
            child: _PadButton(
              key: OnScreenPad.rightKey,
              label: 'Right',
              icon: Icons.arrow_forward,
              haptics: haptics,
              onHeldChanged: (held) => onUpdate(right: held),
            ),
          ),
        ),
      ],
    ),
  );
}

/// One button, [AppTapTargets.primary] (72 dp) on a side — `PLAN.md` §4.2
/// asks that floor of LEFT and RIGHT, and FIRE gets it too because it is held
/// as continuously as they are (`PLAN-phase-4.md` §1).
class _PadButton extends StatefulWidget {
  const _PadButton({
    required this.label,
    required this.icon,
    required this.haptics,
    required this.onHeldChanged,
    super.key,
  });

  final String label;
  final IconData icon;
  final AppHaptics haptics;
  final ValueChanged<bool> onHeldChanged;

  @override
  State<_PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<_PadButton> {
  /// The pointer currently holding this button, or `null`. Checked on every
  /// move, up and cancel event, so a second finger — even one already down on
  /// another button — can never release this one (`PLAN-phase-4.md` §1's "a
  /// second finger on FIRE does not release LEFT").
  int? _pointer;

  void _press(int pointer) {
    if (_pointer != null) return;
    _pointer = pointer;
    widget.haptics.tap();
    widget.onHeldChanged(true);
  }

  void _release(int pointer) {
    if (_pointer != pointer) return;
    _pointer = null;
    widget.onHeldChanged(false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (event) => _press(event.pointer),
      onPointerUp: (event) => _release(event.pointer),
      onPointerCancel: (event) => _release(event.pointer),
      onPointerMove: (event) {
        if (event.pointer != _pointer) return;
        // Flutter routes a move to whichever widget the pointer went down on,
        // wherever it has slid to since (`PLAN-phase-4.md` §1) — without this
        // check a finger that slides off the button would leave it held
        // forever, the bug `PLAN.md` §8 names.
        final local = event.localPosition;
        final inside =
            local.dx >= 0 &&
            local.dy >= 0 &&
            local.dx <= AppTapTargets.primary &&
            local.dy <= AppTapTargets.primary;
        if (!inside) _release(event.pointer);
      },
      child: Semantics(
        label: widget.label,
        button: true,
        child: Container(
          width: AppTapTargets.primary,
          height: AppTapTargets.primary,
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            size: AppIconSizes.large,
            color: colors.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}
