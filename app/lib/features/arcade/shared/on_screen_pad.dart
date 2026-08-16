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

import '../../../core/storage/save_data.dart' show PadSide;
import '../../../core/ui/tokens.dart';
import 'pad_input.dart';

/// LEFT, RIGHT and FIRE, below the play field.
///
/// [side] decides which side FIRE sits on: LEFT and RIGHT always stay
/// adjacent to each other, and only the two groups — movement and FIRE — swap
/// ends, as one `Row` whose children are reversed rather than two separate
/// layouts (`PLAN-phase-4.md` §4.6).
class OnScreenPad extends StatefulWidget {
  const OnScreenPad({
    required this.input,
    this.side = PadSide.right,
    super.key,
  });

  /// Written to on every button press and release, combining whichever of
  /// left, right and fire are currently held.
  final ValueNotifier<PadInput> input;

  /// Which side FIRE sits on — mirrors a profile's stored `padSide` for a
  /// left-handed player.
  final PadSide side;

  /// Keys for finding each button in a test — by identity rather than by the
  /// icon it happens to draw today, which is otherwise the only handle a test
  /// has on a `Listener` with no text of its own.
  static const Key leftKey = ValueKey('OnScreenPad.left');
  static const Key rightKey = ValueKey('OnScreenPad.right');
  static const Key fireKey = ValueKey('OnScreenPad.fire');

  @override
  State<OnScreenPad> createState() => _OnScreenPadState();
}

class _OnScreenPadState extends State<OnScreenPad> {
  bool _left = false;
  bool _right = false;
  bool _fire = false;

  void _update({bool? left, bool? right, bool? fire}) {
    _left = left ?? _left;
    _right = right ?? _right;
    _fire = fire ?? _fire;
    widget.input.value = PadInput(left: _left, right: _right, fire: _fire);
  }

  @override
  Widget build(BuildContext context) {
    final movement = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PadButton(
          key: OnScreenPad.leftKey,
          label: 'Left',
          icon: Icons.arrow_back,
          onHeldChanged: (held) => _update(left: held),
        ),
        const SizedBox(width: AppSpacing.lg),
        _PadButton(
          key: OnScreenPad.rightKey,
          label: 'Right',
          icon: Icons.arrow_forward,
          onHeldChanged: (held) => _update(right: held),
        ),
      ],
    );
    final fire = _PadButton(
      key: OnScreenPad.fireKey,
      label: 'Fire',
      icon: Icons.circle,
      onHeldChanged: (held) => _update(fire: held),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: widget.side == PadSide.right
          ? [movement, fire]
          : [fire, movement],
    );
  }
}

/// One button, [AppTapTargets.primary] (72 dp) on a side — `PLAN.md` §4.2
/// asks that floor of LEFT and RIGHT, and FIRE gets it too because it is held
/// as continuously as they are (`PLAN-phase-4.md` §1).
class _PadButton extends StatefulWidget {
  const _PadButton({
    required this.label,
    required this.icon,
    required this.onHeldChanged,
    super.key,
  });

  final String label;
  final IconData icon;
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
