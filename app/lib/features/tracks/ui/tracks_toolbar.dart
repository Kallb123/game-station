// Undo, redo and hint: the three things on a Tracks screen that are not the
// board (`PLAN-phase-9-tracks.md` §4.12).
//
// `PLAN-phase-9-tracks.md` §4.12 says `BigButton`s. Three labelled ones do not
// fit a 360 dp phone at 200 % text, and Sudoku's keypad already settled on icon
// buttons with tooltips for these same three actions, so this follows it —
// larger, because here they are the whole control surface.

import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../model/tracks_session.dart';

/// The toolbar for [session], laid out along [axis].
class TracksToolbar extends StatelessWidget {
  /// A toolbar driving [session]. [axis] is horizontal under a portrait board
  /// and vertical beside a landscape one.
  const TracksToolbar({
    required this.session,
    this.axis = Axis.horizontal,
    super.key,
  });

  /// The puzzle being played.
  final TracksSession session;

  /// Which way the buttons run.
  final Axis axis;

  @override
  Widget build(BuildContext context) {
    // Rebuilt on every change: undo's and redo's enabled state is the history's,
    // and there is no narrower slice to subscribe to.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        // Nothing on a solved board: the solve is recorded the moment it
        // happens, and an undo or a hint during the journey would change a
        // board the save already calls finished.
        final open = !session.isSolved;
        final buttons = [
          _ToolButton(
            icon: Icons.undo,
            tooltip: 'Undo',
            onPressed: open && session.canUndo ? session.undo : null,
          ),
          _ToolButton(
            icon: Icons.redo,
            tooltip: 'Redo',
            onPressed: open && session.canRedo ? session.redo : null,
          ),
          // Enabled whatever an unsolved board holds, as Sudoku's is: the
          // session has an answer for every state a puzzle in play can be in.
          _ToolButton(
            icon: Icons.lightbulb_outline,
            tooltip: 'Hint',
            onPressed: open ? session.hint : null,
          ),
        ];

        return axis == Axis.horizontal
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: buttons,
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.md),
                    buttons[i],
                  ],
                ],
              );
      },
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;

  /// Null greys the button out and disables it.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    onPressed: onPressed,
    icon: Icon(icon, size: AppIconSizes.large),
    tooltip: tooltip,
    style: IconButton.styleFrom(
      minimumSize: const Size.square(AppTapTargets.primary),
    ),
  );
}
