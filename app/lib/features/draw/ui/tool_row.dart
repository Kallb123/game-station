// The tool row: four pencil sizes, the palette button, the eraser, the colour
// dropper, undo, redo and New sheet — every control a child chooses a pencil,
// a colour or an action from (`PLAN-phase-8.md` §4.7, §4.8, §6 PR 3).
//
// The colours are not here. Two hundred and sixty-two of them live in a popup
// (`palette_popup.dart`) behind one palette button, which shows the colour in
// use and opens the grid when tapped, so the row is the same size however many
// colours there are and a colour is two taps, not a scroll.
//
// Three groups — sizes, tools and actions — each its own `Wrap` rather than a
// fixed `Row`, and every `Wrap` horizontal whichever [ToolRowLayout] is in
// force: a group too wide for the space it is given folds onto another line
// by itself, so nothing here can overflow, at any text scale, because nothing
// here draws scaling text. The groups themselves never share a line: brush
// thickness reads apart from the tools, and undo and redo — built as a single
// `Row` so a `Wrap` has no seam to split them at — never separate across
// lines.
//
// The order is the same either way — the four sizes, then the palette button,
// eraser and dropper, then undo, redo and New sheet — and what
// [ToolRowLayout] changes is the width the groups are given. As a band below
// the sheet (portrait) it is the window's width; as a rail beside it
// (landscape) it is [ToolRow.railWidthFor] the window, which is the width of
// the four sizes, the widest line there is.
//
// The tools are the palette button, the eraser and the dropper — the three a
// child swaps between mid-drawing, each selected while it is the active tool —
// and they get a line of their own, apart from the actions, rather than one
// shared line of six controls that would fold into a lone New sheet on the
// next.
//
// Selection is never colour alone (`PLAN.md` §7's accessibility rule,
// `PLAN-phase-8.md` §1): every selectable control here gains a 3 dp
// `AppBorders.selected` ring and grows, and every control — selectable or
// not — carries a `Semantics` label of its own, because the row draws no
// text.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../model/palette.dart';
import 'palette_popup.dart';

/// How much a selected size dot or the palette button's colour dot grows by,
/// on top of its unselected diameter — the "size change" half of the
/// selection signal (`PLAN-phase-8.md` §1), alongside the border.
const double _selectionGrowth = 8;

/// The palette button's colour dot when the pencil is selected. Unselected it
/// is [_selectionGrowth] smaller, both comfortably inside the 56 dp button.
const double _swatchDiameter = 34;

/// Where a [ToolRow] is drawn, which is what decides the shape of its groups.
///
/// The two cases the sheet has (`draw_sheet_screen.dart`), named for what
/// they are rather than for an axis: both lay every group out horizontally,
/// so [Axis] would say the opposite of what happens.
enum ToolRowLayout {
  /// The band below the sheet, as wide as the screen: portrait.
  band,

  /// The rail beside the sheet, [ToolRow.railWidthFor] the window wide:
  /// landscape, on the side the profile's `padSide` already names.
  rail,
}

/// The four pencil sizes, the palette button, the eraser, the colour dropper,
/// undo, redo and New sheet, laid out for [DrawSheetScreen]
/// (`draw_sheet_screen.dart`).
class ToolRow extends StatelessWidget {
  const ToolRow({
    required this.sizeIndex,
    required this.colorIndex,
    required this.isEraser,
    required this.isDropper,
    required this.onSizeSelected,
    required this.onColorSelected,
    required this.onEraserSelected,
    required this.onDropperSelected,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
    required this.onNewSheet,
    this.layout = ToolRowLayout.band,
    super.key,
  });

  /// The pencil size a new stroke will use. Read even while [isEraser]: the
  /// eraser's own width comes from the same table (`draw_sheet_screen.dart`),
  /// so switching back to a pencil resumes at the size last chosen rather
  /// than resetting to thin.
  final int sizeIndex;

  /// The colour a new stroke will use, ignored while [isEraser] or
  /// [isDropper] — though the palette button keeps showing it, so a child who
  /// has picked up the eraser can still see what colour the pencil will be.
  final int colorIndex;

  /// Whether the eraser, rather than [colorIndex]'s pencil, is the active
  /// tool.
  final bool isEraser;

  /// Whether the colour dropper is the active tool: the next tap on the
  /// sheet picks a colour rather than drawing (`PLAN-phase-8.md` §4.8).
  /// Never true together with [isEraser]; if a caller says both, both buttons
  /// show selected rather than one being quietly preferred.
  final bool isDropper;

  final ValueChanged<int> onSizeSelected;

  /// Called with the palette index a child chose in the popup the palette
  /// button opens. Not called when the popup is dismissed.
  final ValueChanged<int> onColorSelected;
  final VoidCallback onEraserSelected;
  final VoidCallback onDropperSelected;

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

  /// [ToolRowLayout.band] (the default) is the band below the sheet;
  /// [ToolRowLayout.rail] is the panel beside it, for a landscape layout
  /// that wants one.
  final ToolRowLayout layout;

  /// The width a [ToolRowLayout.rail] draws at when the window can spare it:
  /// the four pencil sizes and the three gaps between them.
  ///
  /// The widest line the row has — the tools take three controls and the
  /// actions a 72 dp pair and one more — so it is what keeps the sizes on one
  /// line, and a rail any wider would take width from the sheet for nothing.
  static const double railWidth = AppTapTargets.min * 4 + AppSpacing.sm * 3;

  /// How wide to draw the rail where the sheet and it have [available]
  /// logical pixels to share (`draw_sheet_screen.dart`'s `_landscapeLayout`).
  ///
  /// [railWidth], and never more than half of [available]: the rail's groups
  /// fold onto more lines when they are given less, and the sheet has nothing
  /// to fold.
  static double railWidthFor(double available) =>
      math.min(railWidth, available / 2);

  static const Key paletteKey = ValueKey('ToolRow.palette');
  static const Key eraserKey = ValueKey('ToolRow.eraser');
  static const Key dropperKey = ValueKey('ToolRow.dropper');
  static const Key undoKey = ValueKey('ToolRow.undo');
  static const Key redoKey = ValueKey('ToolRow.redo');
  static const Key newSheetKey = ValueKey('ToolRow.newSheet');

  static Key sizeKey(int index) => ValueKey('ToolRow.size.$index');

  /// A group's own [Wrap] — sizes, tools and actions each get one — so a
  /// group too wide for the space still folds onto another line by itself
  /// (`ToolRow`'s own doc comment) without folding into a neighbouring
  /// group's line.
  Widget _group(List<Widget> children) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: children,
  );

  @override
  Widget build(BuildContext context) {
    final sizes = _group([
      for (var i = 0; i < DrawPencils.widths.length; i++)
        _SizeDot(
          key: sizeKey(i),
          index: i,
          selected: !isEraser && !isDropper && sizeIndex == i,
          onTap: () => onSizeSelected(i),
        ),
    ]);
    final palette = _PaletteButton(
      key: paletteKey,
      colorIndex: colorIndex,
      selected: !isEraser && !isDropper,
      onTap: () async {
        final chosen = await showPalettePopup(
          context,
          selectedIndex: colorIndex,
        );
        // The popup is modal, so the row outlives it in practice; the check
        // is for the one case it might not, a route torn down underneath it.
        if (chosen != null && context.mounted) onColorSelected(chosen);
      },
    );
    final eraser = _EraserButton(
      key: eraserKey,
      selected: isEraser,
      onTap: onEraserSelected,
    );
    final dropper = _DropperButton(
      key: dropperKey,
      selected: isDropper,
      onTap: onDropperSelected,
    );
    // Undo and redo as a single [Row], not two separate children of the
    // group's `Wrap` — a `Wrap` only ever breaks *between* children, so this
    // is what keeps the pair from landing on two different lines.
    final undoRedo = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: AppSpacing.sm,
      children: [
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
      ],
    );
    final newSheet = _ActionButton(
      toolKey: newSheetKey,
      icon: Icons.note_add_outlined,
      label: 'New sheet',
      onPressed: onNewSheet,
    );

    final column = Column(
      // The groups stack whichever layout is in force: a band stacks them
      // the same way one group's own lines stack, and a rail is too narrow
      // to hold two of them side by side.
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: AppSpacing.md,
      // Brush thickness first and on its own; then the tools a child swaps
      // between mid-drawing, colour among them; then the actions. Three lines
      // fit every window the band or rail is drawn in, but both still scroll
      // when one does not (`draw_sheet_screen.dart`'s `_portraitLayout` and
      // `_landscapeLayout`), and it is the last line that scrolls out of view.
      children: [
        sizes,
        _group([palette, eraser, dropper]),
        _group([undoRedo, newSheet]),
      ],
    );

    return switch (layout) {
      ToolRowLayout.band => column,
      // Bounded, not sized: `BoxConstraints.enforce` keeps whichever of this
      // and the parent's own limit is smaller, so the rail takes its natural
      // width beside a sheet that has width to spare and folds instead of
      // overflowing beside one that does not.
      ToolRowLayout.rail => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: railWidth),
        child: column,
      ),
    };
  }
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

/// The one palette button: the colour in use as a dot, a palette glyph in its
/// corner to read as "choose a colour", and the popup behind a tap
/// (`palette_popup.dart`).
///
/// Selected while the pencil is the active tool — the ring and the dot's
/// growth, as for the eraser and the dropper — because choosing a colour is
/// choosing the pencil: the row's `onColorSelected` path leaves the eraser and
/// the dropper behind. The dot carries its own hairline border, not only the
/// ring around it: white would otherwise disappear against a light theme's
/// surface, and black against a dark one (`PLAN-phase-8.md` §1).
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.colorIndex,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int colorIndex;
  final bool selected;
  final VoidCallback onTap;

  /// The glyph's disc and how far in from the button's corner it sits: a
  /// corner of the 56 dp circle is empty, and 8 dp in puts the disc's far edge
  /// about 3 dp inside the circle, clear of the selected ring.
  static const double _badge = 18;
  static const double _badgeInset = 8;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final diameter = selected
        ? _swatchDiameter
        : _swatchDiameter - _selectionGrowth;
    final ring = selected ? AppBorders.selected : AppBorders.hairline;

    return Semantics(
      label: 'Colours',
      value: DrawPalette.nameAt(colorIndex),
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
              width: ring,
              color: selected ? colors.primary : colors.outlineVariant,
            ),
          ),
          // Expanded to the ring's inside, so the badge's inset is measured
          // from the button's edge and not from the dot's.
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Container(
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: DrawPalette.colorAt(colorIndex),
                    border: Border.all(
                      color: colors.outlineVariant,
                      width: AppBorders.hairline,
                    ),
                  ),
                ),
              ),
              Positioned(
                right: _badgeInset - ring,
                bottom: _badgeInset - ring,
                child: Container(
                  width: _badge,
                  height: _badge,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surface,
                    border: Border.all(
                      color: colors.outlineVariant,
                      width: AppBorders.hairline,
                    ),
                  ),
                  child: Icon(Icons.palette, size: 12, color: colors.onSurface),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The eraser. Styled like [_SizeDot] and [_PaletteButton] — a ring plus a
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
          child: _EraserGlyph(
            size: selected ? AppIconSizes.large : AppIconSizes.standard,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The colour dropper. Styled exactly like [_EraserButton] — a ring plus a
/// size change, for the same reason — around [Icons.colorize], Material's
/// eyedropper, which unlike the eraser has a stock glyph that reads as the
/// tool it is.
class _DropperButton extends StatelessWidget {
  const _DropperButton({
    required this.selected,
    required this.onTap,
    super.key,
  });

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: 'Colour dropper',
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
            Icons.colorize,
            size: selected ? AppIconSizes.large : AppIconSizes.standard,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}

/// A rubber eraser, drawn rather than pulled from [Icons]: a rounded block
/// with a divider near one end — the two-tone rubber every eraser icon
/// (Material Symbols' own `ink_eraser` among them) uses to read as a drawing
/// tool, not [Icons.backspace_outlined]'s keyboard key.
class _EraserGlyph extends StatelessWidget {
  const _EraserGlyph({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final strokeWidth = size / 10;

    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Transform.rotate(
          angle: -0.5,
          child: SizedBox(
            width: size * 0.9,
            height: size * 0.58,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: color, width: strokeWidth),
                borderRadius: BorderRadius.circular(size / 6),
              ),
              child: Align(
                alignment: const Alignment(0.35, 0),
                child: Container(width: strokeWidth, color: color),
              ),
            ),
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
