// The tool row: four pencil sizes, eighteen colours, the eraser, undo, redo
// and New sheet — every control a child chooses a pencil, a colour or an
// action from (`PLAN-phase-8.md` §4.7, §6 PR 3).
//
// Three groups — sizes, colours and actions — each its own `Wrap` rather than
// a fixed `Row`, and every `Wrap` horizontal whichever [ToolRowLayout] is in
// force: a group too wide for the space it is given folds onto another line
// by itself, so nothing here can overflow, at any text scale, because nothing
// here draws scaling text. The groups themselves never share a line: brush
// thickness reads apart from colour, and undo and redo — built as a single
// `Row` so a `Wrap` has no seam to split them at — never separate across
// lines.
//
// The order is the same either way — the four sizes, then undo, redo, the
// eraser and New sheet, then the colours — and what [ToolRowLayout] changes
// is the width the groups are given. As a band below the sheet (portrait) it
// is the window's width; as a rail beside it (landscape) it is
// [ToolRow.railWidthFor] the window, six swatches wide where the window can
// spare it, so the eighteen colours fill the rail in three rows of six rather
// than running down it one control at a time (`palette.dart`: twelve
// paint-box colours and six skin tones, so the tones are the third row).
//
// The colours come last because they are the group that folds onto lines of
// its own, and so the only one that can be left below the fold on a window
// too short for all three: both layouts scroll rather than shrink a control
// (`draw_sheet_screen.dart`), and a colour is the one thing here worth
// scrolling for. The eraser sits with the actions rather than at the end of
// the swatches for the same reason — it is reached for mid-drawing.
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

/// How much a selected size dot or colour swatch grows by, on top of its
/// unselected diameter — the "size change" half of the selection signal
/// (`PLAN-phase-8.md` §1), alongside the border.
const double _selectionGrowth = 8;

/// A selected colour swatch's diameter. Unselected swatches are smaller
/// ([_selectionGrowth] less), both comfortably inside the 56 dp button that
/// holds either.
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

/// The four pencil sizes, the eighteen colours, the eraser, undo, redo and New
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
    this.layout = ToolRowLayout.band,
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

  /// [ToolRowLayout.band] (the default) is the band below the sheet;
  /// [ToolRowLayout.rail] is the panel beside it, for a landscape layout
  /// that wants one.
  final ToolRowLayout layout;

  /// The width a [ToolRowLayout.rail] draws at when the window can spare it:
  /// six colour swatches and the five gaps between them.
  ///
  /// Six, because the whole point of the rail is to use the width a landscape
  /// window has and the height it does not: the colours take three rows of
  /// six where four to a row would need five, which is the difference
  /// between a short landscape phone's rail scrolling a little and scrolling
  /// a lot.
  static const double railWidth = AppTapTargets.min * 6 + AppSpacing.sm * 5;

  /// The width a rail falls back to when [railWidth] would take more than
  /// half the window: undo and redo at their primary floor, the eraser and
  /// New sheet at the ordinary one, and the three gaps between the four —
  /// the narrowest the action line fits on, and four colours to a row.
  static const double narrowRailWidth =
      AppTapTargets.primary * 2 + AppTapTargets.min * 2 + AppSpacing.sm * 3;

  /// How wide to draw the rail where the sheet and it have [available]
  /// logical pixels to share (`draw_sheet_screen.dart`'s `_landscapeLayout`).
  ///
  /// Never more than half of it — the rail's groups fold onto more lines when
  /// they are given less, and the sheet has nothing to fold — and one of the
  /// two widths above wherever that leaves a choice, so the colours land in
  /// rows of six or of four rather than in a ragged grid of whatever number
  /// happens to fit. Eighteen divides evenly into the wide rail's rows of
  /// six; at the narrow width the last row carries the two left over, which
  /// is the price of the six skin tones and cheaper than a row length that
  /// changes with every window.
  static double railWidthFor(double available) {
    final half = available / 2;
    return half >= railWidth ? railWidth : math.min(narrowRailWidth, half);
  }

  static const Key eraserKey = ValueKey('ToolRow.eraser');
  static const Key undoKey = ValueKey('ToolRow.undo');
  static const Key redoKey = ValueKey('ToolRow.redo');
  static const Key newSheetKey = ValueKey('ToolRow.newSheet');

  static Key sizeKey(int index) => ValueKey('ToolRow.size.$index');
  static Key colorKey(int index) => ValueKey('ToolRow.color.$index');

  /// A group's own [Wrap] — sizes, colours and actions each get one — so a
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
          selected: !isEraser && sizeIndex == i,
          onTap: () => onSizeSelected(i),
        ),
    ]);
    final colors = [
      for (var i = 0; i < DrawPalette.colors.length; i++)
        _ColorSwatch(
          key: colorKey(i),
          index: i,
          selected: !isEraser && colorIndex == i,
          onTap: () => onColorSelected(i),
        ),
    ];
    final eraser = _EraserButton(
      key: eraserKey,
      selected: isEraser,
      onTap: onEraserSelected,
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
      // Brush thickness first and on its own, never sharing a line with
      // colour selection; then the actions; then the colours, which are the
      // only group that folds onto lines of its own and so the only one that
      // can be left with a line below the fold when the window is too short
      // for all three (`draw_sheet_screen.dart`'s `_portraitLayout`, the
      // rail's own scroll view). Undo and redo are tapped in a hurry and the
      // eraser is tapped mid-drawing: none of the three is a control to make
      // a child scroll for.
      children: [
        sizes,
        _group([undoRedo, eraser, newSheet]),
        _group(colors),
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
          child: _EraserGlyph(
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
