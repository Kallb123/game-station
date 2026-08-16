// The input every arcade game receives each fixed step, from whichever
// source is currently live (`PLAN-phase-4.md` §4.6): the on-screen pad, the
// keyboard mirror, or a test driving `InvadersSim.step` directly.
//
// Declared in `shared/` rather than under `invaders/` because every later
// game in `PLAN.md` §4.4 reuses the same three intents — `GameShell` and
// `OnScreenPad` (PR 5) are built against this type, not against Invaders'.

import 'package:flutter/foundation.dart';

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
