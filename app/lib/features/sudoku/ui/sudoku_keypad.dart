// The digits, and the five things that are not digits.
//
// The pad is one box of the grid it belongs to: `spec.boxRows` rows of
// `spec.boxCols` buttons, which makes a 9x9 the 3x3 shape of a phone keypad and
// a 6x6 a 2x3 — derived from the same two numbers the board's box lines come
// from rather than written down twice (`PLAN-phase-3.md` §4.5).

import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../model/sudoku_session.dart';

/// The keypad for [session]: its digits, erase, pencil, undo, redo and hint.
class SudokuKeypad extends StatelessWidget {
  /// A keypad driving [session].
  const SudokuKeypad({required this.session, super.key});

  /// The puzzle being played.
  final SudokuSession session;

  @override
  Widget build(BuildContext context) {
    final spec = session.spec;

    // The whole pad rebuilds on a change, unlike the board: it is fourteen
    // widgets whose enabled state depends on the session as a whole — undo and
    // redo on the history, the pencil toggle on the mode — so there is no
    // per-button slice to subscribe to.
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < spec.boxRows; row++) ...[
            if (row > 0) const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                for (var col = 0; col < spec.boxCols; col++) ...[
                  if (col > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _DigitButton(
                      digit: row * spec.boxCols + col + 1,
                      // Enabled with nothing selected, where it does nothing:
                      // a pad that greys out until a cell is tapped teaches a
                      // child that the buttons are broken, and the fix — tap a
                      // cell — is the next thing they will do anyway. Greyed
                      // out once the digit is on the board as many times as it
                      // belongs there, right or wrong.
                      onPressed:
                          session.isDigitComplete(row * spec.boxCols + col + 1)
                          ? null
                          : session.enter,
                    ),
                  ),
                ],
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: session.erase,
                icon: const Icon(Icons.backspace_outlined),
                tooltip: 'Erase',
              ),
              IconButton(
                onPressed: () => session.pencilMode = !session.pencilMode,
                // The glyph changes as well as the colour, so the mode is
                // readable without telling two container colours apart
                // (`AGENTS.md`).
                isSelected: session.pencilMode,
                selectedIcon: const Icon(Icons.edit),
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Pencil marks',
              ),
              IconButton(
                onPressed: session.canUndo ? session.undo : null,
                icon: const Icon(Icons.undo),
                tooltip: 'Undo',
              ),
              IconButton(
                onPressed: session.canRedo ? session.redo : null,
                icon: const Icon(Icons.redo),
                tooltip: 'Redo',
              ),
              IconButton(
                // Enabled whatever the board holds: the hint has an answer for
                // every state a puzzle in play can be in — a mistake to point
                // at, a cell technique can decide, or the emptiest cell of a
                // board technique has run out on (`PLAN-phase-3.md` §4.6).
                onPressed: session.hint,
                icon: const Icon(Icons.lightbulb_outline),
                tooltip: 'Hint',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One digit of the keypad.
class _DigitButton extends StatelessWidget {
  const _DigitButton({required this.digit, required this.onPressed});

  final int digit;

  /// Null greys the button out and disables it.
  final void Function(int digit)? onPressed;

  @override
  Widget build(BuildContext context) => FilledButton.tonal(
    onPressed: onPressed == null ? null : () => onPressed!(digit),
    style: FilledButton.styleFrom(
      // Wider than tall by default in a row this size; the floor is what
      // matters, and it is the theme's (`AppTapTargets.min`). The horizontal
      // padding is dropped to nothing so that three buttons fit across a small
      // phone at 200% text scale — the label is one character, so there is
      // nothing to pad away from.
      padding: EdgeInsets.zero,
      minimumSize: const Size(AppTapTargets.min, AppTapTargets.min),
    ),
    child: Text('$digit', style: Theme.of(context).textTheme.headlineSmall),
  );
}
