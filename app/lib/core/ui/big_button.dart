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
/// A label of one word never wraps: a word split across lines reads as two
/// words to a child learning to read ("Puzzle" / "s" at 200% text on a 360 dp
/// phone), so it shrinks to fit instead. A label with spaces wraps at them.
///
/// [selected] is drawn as a border and a check icon as well as a colour
/// change, because a player who cannot tell the two colours apart still has to
/// be able to tell which profile is theirs.
class BigButton extends StatelessWidget {
  const BigButton({
    required IconData this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
    super.key,
  }) : glyph = null;

  /// A button with a text symbol where the icon goes, at the icon's size.
  /// For a symbol Material Icons does not have, such as the division sign the
  /// quiz's Maths buttons show (`PLAN-quiz-maths.md` §4.5).
  const BigButton.glyph({
    required String this.glyph,
    required this.label,
    required this.onPressed,
    this.selected = false,
    super.key,
  }) : icon = null;

  /// The icon shown before the label, unless this is a [BigButton.glyph].
  final IconData? icon;

  /// The symbol shown before the label, for a [BigButton.glyph].
  final String? glyph;

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
            if (glyph case final glyph?)
              // A box the icon's size, so a row of glyph buttons and icon
              // buttons line their labels up; the symbol is decoration, as
              // the icon is, since the label says the same in words.
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: AppIconSizes.large,
                  // Drawn at the box's height with no line spacing, so the
                  // symbol is as big as an icon; scaled down only if a wide
                  // one would not fit.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      glyph,
                      textScaler: TextScaler.noScaling,
                      style: const TextStyle(
                        fontSize: AppIconSizes.large,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              )
            else
              Icon(icon, size: AppIconSizes.large),
            const SizedBox(width: AppSpacing.md),
            Flexible(child: _Label(label)),
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

/// [BigButton]'s label: wrapped at its spaces, or scaled down when it is one
/// word too wide to fit.
class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    if (text.trim().contains(' ')) return Text(text);

    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, maxLines: 1, softWrap: false),
    );
  }
}
