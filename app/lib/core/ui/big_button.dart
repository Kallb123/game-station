import 'package:flutter/material.dart';

import 'tokens.dart';

/// A primary action: an icon, a label, and at least [AppTapTargets.primary] of
/// height to hit.
///
/// The two home cards, the profile picker's avatars and the Sudoku difficulty
/// choices are all this button. It exists so the size rule lives in one place
/// rather than in each screen's padding.
///
/// It grows rather than clips: the label wraps and the button gets taller, so
/// a long name at 200% text scale is still readable.
///
/// That wrapping needs a bounded width. Give it one — a `Column`, a `SizedBox`
/// or an `Expanded` — rather than a bare `Row`, where the flexible label has
/// no width to wrap into.
///
/// [selected] is drawn as a border and a check icon as well as a colour
/// change, because a player who cannot tell the two colours apart still has to
/// be able to tell which profile is theirs.
class BigButton extends StatelessWidget {
  const BigButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  /// The glyph shown before the label.
  final IconData icon;

  /// What the button does, in as few words as a child needs.
  final String label;

  /// Called on a tap. Null disables the button.
  final VoidCallback? onPressed;

  /// Whether this button is the chosen one of a set.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(AppTapTargets.primary, AppTapTargets.primary),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl,
          vertical: AppSpacing.lg,
        ),
        backgroundColor: selected ? colors.primaryContainer : null,
        foregroundColor: selected ? colors.onPrimaryContainer : null,
        // An unselected button carries a transparent border of the same
        // width, so selecting one does not shift the row it sits in.
        side: BorderSide(
          color: selected ? colors.onPrimaryContainer : Colors.transparent,
          width: AppBorders.selected,
        ),
      ),
      // Inside the button rather than around it, so the flag merges into the
      // button's own semantics node instead of forming a second one that a
      // screen reader announces separately.
      child: Semantics(
        selected: selected,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppIconSizes.large),
            const SizedBox(width: AppSpacing.md),
            Flexible(child: Text(label)),
            if (selected) ...[
              const SizedBox(width: AppSpacing.md),
              const Icon(Icons.check_circle, size: AppIconSizes.standard),
            ],
          ],
        ),
      ),
    );
  }
}
