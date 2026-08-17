import 'package:flutter/widgets.dart';

/// Pops the current route, but only if the navigator still has one to land on.
///
/// [NavigatorState.pop] does not check this itself: called with nothing left
/// to pop, it does not throw, it empties the navigator's history — nothing
/// left to draw, and no way back short of restarting the app. That is
/// reachable whenever a back control's own `pop()` runs after the stack
/// beneath it has already changed — a system back gesture and an on-screen
/// back tap landing close together, or (`game_shell.dart`'s `_confirmQuit`)
/// an awaited confirm dialog's result arriving after something else already
/// popped the route it meant to pop. Every screen's back control was built to
/// show or hide itself from [NavigatorState.canPop] at the time it was drawn;
/// checking it again here, at the moment the pop actually happens, is what
/// keeps a stale answer from being acted on.
void popIfPossible(BuildContext context) {
  final navigator = Navigator.of(context);
  if (navigator.canPop()) navigator.pop();
}
