// The tool row: four pencil sizes, twelve colours, the eraser, undo, redo
// and New sheet — every control a child chooses a pencil, a colour or an
// action from (`PLAN-phase-8.md` §4.7, §6 PR 3).
//
// A `Wrap`, not a fixed `Row`: the same controls sit in a horizontal band
// below the sheet in portrait and could sit in a narrower column beside it in
// landscape (`axis`, the same split `OnScreenPad.axis` makes in
// `features/arcade/shared/on_screen_pad.dart`), and `Wrap` folds onto another
// line by itself if a narrow phone cannot fit them on one — so nothing here
// can overflow, at any text scale, because nothing here draws scaling text.
//
// Selection is never colour alone (`PLAN.md` §7's accessibility rule,
// `PLAN-phase-8.md` §1): every selectable control here gains a 3 dp
// `AppBorders.selected` ring and grows, and every control — selectable or
// not — carries a `Semantics` label of its own, because the row draws no
// text.

import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../model/palette.dart';

/// How much a selected size dot or colour swatch grows by, on top of its
/// unselected diameter — the "size change" half of the selection signal
/// (`PLAN-phase-8.md` §1), alongside the border.
const double _selectionGrowth = 8;

/// A selected colour swatch's diameter. Unselected swatches are smaller
/// ([_selectionGrowth] less), both comfortably inside the 56 dp button that
/// holds either.
const double _swatchDiameter = 34;

/// The four pencil sizes, the twelve colours, the eraser, undo, redo and New
/// sheet, laid out for [DrawSheetScreen] (`draw_sheet_screen.dart`).
class ToolRow extends StatelessWidget {
  const ToolRow({
    required this.sizeIndex,
    required this.colorIndex,
    required this.isEraser,
    required this.onSizeSelected,
    required this.onColorSelected,
    required this.onEraserSelected,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onNewSheet,
    this.axis = Axis.horizontal,
    super.key,
  });

  /// The pencil size a new stroke will use. Read even while [isEraser]: the
  /// eraser's own width comes from the same table (`draw_sheet_screen.dart`),
  /// so switching back to a pencil resumes at the size last chosen rather
  /// than resetting to thin.
  final int sizeIndex;

  /// The colour a new stroke will use, ignored while [isEraser].
  final int colorIndex;

  /// Whether the eraser, rather than [colorIndex]'s pencil, is the active
  /// tool.
  final bool isEraser;

  final ValueChanged<int> onSizeSelected;
  final ValueChanged<int> onColorSelected;
  final VoidCallback onEraserSelected;

  /// Whether [onUndo] and [onRedo] do anything right now. `false` disables
  /// the button rather than hiding it, and reports that to the semantics
  /// tree as well as to the eye — `IconButton` does both from `onPressed`
  /// being null, the same mechanism `sudoku_keypad.dart` relies on for the
  /// same two buttons.
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  /// Files the current drawing away and starts a blank one
  /// (`PLAN-phase-8.md` §1, §4.7). Never disabled: a blank sheet is always a
  /// valid thing to ask for.
  final VoidCallback onNewSheet;

  /// [Axis.horizontal] (the default) is a band below the sheet;
  /// [Axis.vertical] is a rail beside it, for a landscape layout that wants
  /// one — the same choice `OnScreenPad.axis` offers the arcade's pad.
  final Axis axis;

  static const Key eraserKey = ValueKey('ToolRow.eraser');
  static const Key undoKey = ValueKey('ToolRow.undo');
  static const Key redoKey = ValueKey('ToolRow.redo');
  static const Key newSheetKey = ValueKey('ToolRow.newSheet');

  static Key sizeKey(int index) => ValueKey('ToolRow.size.$index');
  static Key colorKey(int index) => ValueKey('ToolRow.color.$index');

  @override
  Widget build(BuildContext context) => Wrap(
    direction: axis,
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: [
      for (var i = 0; i < DrawPencils.widths.length; i++)
        _SizeDot(
          key: sizeKey(i),
          index: i,
          selected: !isEraser && sizeIndex == i,
          onTap: () => onSizeSelected(i),
        ),
      for (var i = 0; i < DrawPalette.colors.length; i++)
        _ColorSwatch(
          key: colorKey(i),
          index: i,
          selected: !isEraser && colorIndex == i,
          onTap: () => onColorSelected(i),
        ),
      _EraserButton(
        key: eraserKey,
        selected: isEraser,
        onTap: onEraserSelected,
      ),
      _ActionButton(
        toolKey: undoKey,
        icon: Icons.undo,
        label: 'Undo',
        onPressed: canUndo ? onUndo : null,
        primary: true,
      ),
      _ActionButton(
        toolKey: redoKey,
        icon: Icons.redo,
        label: 'Redo',
        onPressed: canRedo ? onRedo : null,
        primary: true,
      ),
      _ActionButton(
        toolKey: newSheetKey,
        icon: Icons.note_add_outlined,
        label: 'New sheet',
        onPressed: onNewSheet,
      ),
    ],
  );
}

/// One pencil size, drawn as a filled dot at [DrawPencils.previewDiameters]
/// so the four read as visibly different sizes rather than as four identical
/// buttons with different labels.
class _SizeDot extends StatelessWidget {
  const _SizeDot({
    required this.index,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diameter =
        DrawPencils.previewDiameters[index] + (selected ? _selectionGrowth : 0);

    return Semantics(
      label: DrawPencils.names[index],
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: AppTapTargets.min,
          height: AppTapTargets.min,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: selected ? AppBorders.selected : AppBorders.hairline,
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// One colour swatch. Every swatch carries its own hairline border, not only
/// the selection ring around it — the white and near-white swatches would
/// otherwise disappear against a light theme's surface, and the same is true
/// of black against a dark one (`PLAN-phase-8.md` §1).
class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.index,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diameter = selected
        ? _swatchDiameter
        : _swatchDiameter - _selectionGrowth;

    return Semantics(
      label: DrawPalette.names[index],
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: AppTapTargets.min,
          height: AppTapTargets.min,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: selected ? AppBorders.selected : AppBorders.hairline,
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Container(
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: DrawPalette.colors[index],
              border: Border.all(
                color: colors.outlineVariant,
                width: AppBorders.hairline,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The eraser. Styled like [_SizeDot] and [_ColorSwatch] — a ring plus a
/// size change — rather than [IconButton]'s own `isSelected`, whose default
/// selected state is a filled background: colour alone, which this phase's
/// controls do not signal with (`PLAN-phase-8.md` §1).
class _EraserButton extends StatelessWidget {
  const _EraserButton({required this.selected, required this.onTap, super.key});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Eraser',
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: AppTapTargets.min,
          height: AppTapTargets.min,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              width: selected ? AppBorders.selected : AppBorders.hairline,
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Icon(
            Icons.backspace_outlined,
            size: selected ? AppIconSizes.large : AppIconSizes.standard,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Undo, redo and New sheet: plain [IconButton]s, the same control
/// `sudoku_keypad.dart` uses for the same two buttons and the same reason —
/// `onPressed: null` disables the button and reports it disabled to the
/// semantics tree in one, with no custom styling needed for either signal.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.toolKey,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  /// Identifies this button in a test — `IconButton` carries no key of its
  /// own to distinguish undo from redo beyond the icon it happens to draw.
  final Key toolKey;

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// `true` for undo and redo: [AppTapTargets.primary] (72 dp) rather than
  /// the [AppTapTargets.min] (56 dp) floor every other control here meets,
  /// because these two are tapped repeatedly and in a hurry
  /// (`PLAN-phase-8.md` §1).
  final bool primary;

  @override
  Widget build(BuildContext context) => IconButton(
    key: toolKey,
    onPressed: onPressed,
    icon: Icon(icon),
    tooltip: label,
    style: primary
        ? IconButton.styleFrom(
            minimumSize: const Size(
              AppTapTargets.primary,
              AppTapTargets.primary,
            ),
          )
        : null,
  );
}
