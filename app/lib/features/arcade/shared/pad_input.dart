// The input every arcade game receives each fixed step, from whichever
// source is currently live (`PLAN-phase-4.md` §4.6): the on-screen pad, the
// keyboard mirror, or a test driving `InvadersSim.step` directly. Also the
// keyboard mirror itself, `PadKeyboardMirror`, which turns key events into the
// same [PadInput] `on_screen_pad.dart`'s buttons produce.
//
// Declared in `shared/` rather than under `invaders/` because every later
// game in `PLAN.md` §4.4 reuses the same three intents — `GameShell` and
// `OnScreenPad` are built against this type, not against Invaders'.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show FocusNode, KeyEventResult;

/// One fixed step's worth of player intent: which directions are held and
/// whether fire is held.
///
/// A value type rather than three separate booleans threaded through every
/// call, because every input source — the pad, the keyboard, a test —
/// produces the same three flags and every game consumes them the same way.
@immutable
class PadInput {
  const PadInput({this.left = false, this.right = false, this.fire = false});

  /// No direction held, fire not held.
  static const PadInput none = PadInput();

  final bool left;
  final bool right;
  final bool fire;
}

/// Keys that hold LEFT down, mirroring `OnScreenPad`'s left button
/// (`PLAN-phase-4.md` §4.6).
///
/// Not `const`: `LogicalKeyboardKey` overrides `==`, which the analyzer
/// refuses in a const set literal.
final Set<LogicalKeyboardKey> arcadeLeftKeys = {
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.keyA,
};

/// Keys that hold RIGHT down.
final Set<LogicalKeyboardKey> arcadeRightKeys = {
  LogicalKeyboardKey.arrowRight,
  LogicalKeyboardKey.keyD,
};

/// Keys that hold FIRE down.
final Set<LogicalKeyboardKey> arcadeFireKeys = {LogicalKeyboardKey.space};

/// Mirrors the keyboard into the same [PadInput] `OnScreenPad` produces, and
/// hides the pad on the first key it handles (`PLAN-phase-4.md` §4.6, "hide
/// the on-screen buttons after keyboard input"). Showing it again is the
/// caller's job — only the caller knows what counts as "the next touch" on
/// its own screen, typically a `Listener.onPointerDown` over the field.
///
/// A plain object rather than a widget: a `Focus.onKeyEvent` handler is all a
/// screen needs, and giving this its own held-key state means the screen does
/// not track `left`/`right`/`fire` itself, the way `InvadersScreen`'s PR 4
/// stand-in did before this class existed.
class PadKeyboardMirror {
  PadKeyboardMirror({required this.input, required this.padVisible});

  /// Written to on every handled key, combining whichever of left, right and
  /// fire are currently held.
  final ValueNotifier<PadInput> input;

  /// Set to `false` on the first key this handles.
  final ValueNotifier<bool> padVisible;

  bool _left = false;
  bool _right = false;
  bool _fire = false;

  /// A `Focus.onKeyEvent` handler. Ignores anything outside [arcadeLeftKeys],
  /// [arcadeRightKeys] and [arcadeFireKeys]; otherwise updates [input] with
  /// that key held or released.
  KeyEventResult handleKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final matched =
        arcadeLeftKeys.contains(key) ||
        arcadeRightKeys.contains(key) ||
        arcadeFireKeys.contains(key);
    if (!matched) return KeyEventResult.ignored;

    padVisible.value = false;
    final held = event is! KeyUpEvent;
    if (arcadeLeftKeys.contains(key)) _left = held;
    if (arcadeRightKeys.contains(key)) _right = held;
    if (arcadeFireKeys.contains(key)) _fire = held;
    input.value = PadInput(left: _left, right: _right, fire: _fire);
    return KeyEventResult.handled;
  }
}
