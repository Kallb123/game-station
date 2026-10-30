// The tool row: four pencil sizes, the twelve paint-box colours, the palette
// button, the eraser, the colour dropper, undo, redo and New sheet — every
// control a child chooses a pencil, a colour or an action from
// (`PLAN-phase-8.md` §4.7, §4.8, §6 PR 3).
//
// The colours are in two places (`palette.dart`). The twelve a child already
// knows — Red to White — are swatches here, one tap away, because they were
// asked to stay directly reachable rather than behind a menu. Everything else,
// two hundred and sixty-two colours made of a 16 x 16 grid and the six skin
// tones, lives in a popup (`palette_popup.dart`) behind one palette button, so
// the row is the same size however many colours there are and the skin tones
// do not lengthen it.
//
// Four groups — sizes, tools, actions and colours — each its own `Wrap` rather
// than a fixed `Row`, and every `Wrap` horizontal whichever [ToolRowLayout] is
// in force: a group too wide for the space it is given folds onto another line
// by itself, so nothing here can overflow, at any text scale, because nothing
// here draws scaling text. The groups themselves never share a line: brush
// thickness reads apart from the tools, and undo and redo — built as a single
// `Row` so a `Wrap` has no seam to split them at — never separate across
// lines.
//
// The order is the same either way — the four sizes, then the palette button,
// eraser and dropper, then undo, redo and New sheet, then the colours — and
// what [ToolRowLayout] changes is the width the groups are given. As a band
// below the sheet (portrait) it is the window's width; as a rail beside it
// (landscape) it is [ToolRow.railWidthFor] the window.
//
// The colours come last because they are the group that folds onto lines of
// its own, and so the only one that can be left below the fold on a window
// too short for all four: both layouts scroll rather than shrink a control
// (`draw_sheet_screen.dart`), and a colour is the one thing here worth
// scrolling for. The tools, which a child swaps between mid-drawing, and the
// actions, which are tapped in a hurry, stay above it. They keep two lines of
// their own rather than one shared line of six controls, which would fold into
// a lone New sheet on the next.
//
// The twelve colours are kept to even lines: six to a line where the space
// holds six, four to a line otherwise, and never five and five and a stray
// two. A phone's portrait band is 312 dp wide, which holds five swatches but
// not six, so the group is held to four swatches' width there
// ([ToolRow.colorColumnsFor]) and three lines of four result.
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

/// How much a selected size dot, colour swatch or the palette button's colour
/// dot grows by, on top of its unselected diameter — the "size change" half of
/// the selection signal (`PLAN-phase-8.md` §1), alongside the border.
const double _selectionGrowth = 8;

/// A selected colour swatch's diameter, or the palette button's colour dot
/// when it is selected. Unselected they are [_selectionGrowth] smaller, both
/// comfortably inside the 56 dp button that holds either.
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

/// The four pencil sizes, the twelve paint-box colours, the palette button,
/// the eraser, the colour dropper, undo, redo and New sheet, laid out for
/// [DrawSheetScreen]
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
  /// [isDropper] — though the swatch or palette button for it keeps its
  /// colour, so a child who has picked up the eraser can still see what colour
  /// the pencil will be.
  ///
  /// A paint-box colour (0-11) is a swatch in the row and is ringed there; any
  /// other is a popup colour, and the palette button is ringed instead. Never
  /// both (`DrawPalette.isRowIndex`).
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

  /// Called with the palette index a child chose: a swatch in the row, or a
  /// square in the popup the palette button opens. Not called when the popup
  /// is dismissed.
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
  /// six colour swatches and the five gaps between them.
  ///
  /// Six, because the twelve colours then fill the rail in two even lines, and
  /// two lines are what a short landscape window can afford below the tools.
  /// It is 128 dp wider than the narrow rail, so it is only taken where the
  /// sheet does not mind losing them ([railWidthFor]).
  static const double railWidth = AppTapTargets.min * 6 + AppSpacing.sm * 5;

  /// The width a rail falls back to when [railWidth] would take more than
  /// half the window: four swatches and the three gaps between them, which is
  /// also exactly the four pencil sizes, the widest of the other lines.
  ///
  /// Four rather than five to a line, because twelve divides by four: three
  /// even lines of four, where five would leave a stray two.
  static const double narrowRailWidth =
      AppTapTargets.min * 4 + AppSpacing.sm * 3;

  /// How wide to draw the rail where the sheet and it have [available]
  /// logical pixels to share (`draw_sheet_screen.dart`'s `_landscapeLayout`).
  ///
  /// Never more than half of it — the rail's groups fold onto more lines when
  /// they are given less, and the sheet has nothing to fold — and one of the
  /// two widths above wherever that leaves a choice, so the colours land in
  /// lines of six or of four rather than in a ragged grid of whatever number
  /// happens to fit. A 640 dp phone's half is 320 dp, so it gets the narrow
  /// rail; a window of 752 dp or more gets the wide one.
  static double railWidthFor(double available) {
    final half = available / 2;
    return half >= railWidth ? railWidth : math.min(narrowRailWidth, half);
  }

  /// How many colour swatches share a line in a space [available] dp wide:
  /// six where six fit ([railWidth]), else four.
  ///
  /// A fixed choice of two, not "as many as fit", because the number that fits
  /// is five on a phone held upright and twelve does not divide by five.
  static int colorColumnsFor(double available) =>
      available >= railWidth ? 6 : 4;

  static const Key paletteKey = ValueKey('ToolRow.palette');
  static const Key eraserKey = ValueKey('ToolRow.eraser');
  static const Key dropperKey = ValueKey('ToolRow.dropper');
  static const Key undoKey = ValueKey('ToolRow.undo');
  static const Key redoKey = ValueKey('ToolRow.redo');
  static const Key newSheetKey = ValueKey('ToolRow.newSheet');

  static Key sizeKey(int index) => ValueKey('ToolRow.size.$index');
  static Key colorKey(int index) => ValueKey('ToolRow.color.$index');

  /// A group's own [Wrap] — sizes, tools, actions and colours each get one —
  /// so a group too wide for the space still folds onto another line by itself
  /// (`ToolRow`'s own doc comment) without folding into a neighbouring
  /// group's line.
  Widget _group(List<Widget> children) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.sm,
    children: children,
  );

  /// The colour swatches' [_group], held to [colorColumnsFor] swatches' width
  /// of whatever space the row has, so that they fold into even lines. Without
  /// the bound a 312 dp band would take five to a line, and five twelve
  /// times over is five, five and two.
  Widget _colorGroup(List<Widget> swatches) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = colorColumnsFor(constraints.maxWidth);
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: AppTapTargets.min * columns + AppSpacing.sm * (columns - 1),
        ),
        child: _group(swatches),
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final pencil = !isEraser && !isDropper;
    final sizes = _group([
      for (var i = 0; i < DrawPencils.widths.length; i++)
        _SizeDot(
          key: sizeKey(i),
          index: i,
          selected: pencil && sizeIndex == i,
          onTap: () => onSizeSelected(i),
        ),
    ]);
    final colors = [
      for (final i in DrawPalette.rowIndices)
        _ColorSwatch(
          key: colorKey(i),
          index: i,
          selected: pencil && colorIndex == i,
          onTap: () => onColorSelected(i),
        ),
    ];
    final palette = _PaletteButton(
      key: paletteKey,
      // Only a popup colour belongs to this button; a row colour is ringed on
      // its own swatch, and two rings would claim two colours at once.
      colorIndex: DrawPalette.isPickerIndex(colorIndex) ? colorIndex : null,
      selected: pencil && DrawPalette.isPickerIndex(colorIndex),
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
      // between mid-drawing, the palette button among them; then the actions;
      // then the colours, the only group that folds onto lines of its own and
      // so the one whose last line scrolls out of view when the window is too
      // short for all four (`draw_sheet_screen.dart`'s `_portraitLayout` and
      // `_landscapeLayout`). Nothing above them is a control to make a child
      // scroll for.
      children: [
        sizes,
        _group([palette, eraser, dropper]),
        _group([undoRedo, newSheet]),
        _colorGroup(colors),
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

/// A paint-box colour swatch. Every swatch carries its own hairline border,
/// not only the selection ring around it — the white and near-white swatches
/// would otherwise disappear against a light theme's surface, and the same is
/// true of black against a dark one (`PLAN-phase-8.md` §1).
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

/// The one palette button: "more colours", and the popup behind a tap
/// (`palette_popup.dart`).
///
/// It has two appearances, by where the colour in use came from.
///
/// * A popup colour (a grid square or a skin tone) is [colorIndex]: shown as a
///   dot of that colour with a small palette glyph in its corner, so the
///   button says both which colour the pencil has — it has no swatch in the
///   row to say so — and that tapping it opens more.
/// * A row colour leaves [colorIndex] null, and the button is the palette
///   glyph alone, in the text colour like the eraser's and the dropper's. A
///   dot would have to be that colour, and then two controls would show the
///   same one; a rainbow or a grey dot would claim a colour nobody chose. The
///   glyph says only "more colours", which is all it knows.
///
/// Selected only when [colorIndex] is a popup colour and the pencil is the
/// active tool — the ring and the dot's growth, as for the eraser and the
/// dropper. Choosing a colour is choosing the pencil: the row's
/// `onColorSelected` path leaves the eraser and the dropper behind. The dot
/// carries its own hairline border, not only the ring around it: white would
/// otherwise disappear against a light theme's surface, and black against a
/// dark one (`PLAN-phase-8.md` §1).
class _PaletteButton extends StatelessWidget {
  const _PaletteButton({
    required this.colorIndex,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The popup colour in use, or null when the colour in use is a row
  /// swatch's.
  final int? colorIndex;
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
    final index = colorIndex;
    final diameter = selected
        ? _swatchDiameter
        : _swatchDiameter - _selectionGrowth;
    final ring = selected ? AppBorders.selected : AppBorders.hairline;

    return Semantics(
      label: 'More colours',
      value: index == null ? null : DrawPalette.nameAt(index),
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
          child: index == null
              ? Icon(
                  Icons.palette,
                  size: AppIconSizes.standard,
                  color: colors.onSurface,
                )
              // Expanded to the ring's inside, so the badge's inset is
              // measured from the button's edge and not from the dot's.
              : Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: Container(
                        width: diameter,
                        height: diameter,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: DrawPalette.colorAt(index),
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
                        child: Icon(
                          Icons.palette,
                          size: 12,
                          color: colors.onSurface,
                        ),
                      ),
                    ),
                  ],
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
