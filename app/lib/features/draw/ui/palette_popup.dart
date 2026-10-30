// The colour popup: a 16 x 16 grid of small squares — column is hue, row runs
// from pale tint down to deep shade — and the six skin tones in a row beneath
// it (`PLAN-phase-8.md` §4.7). Opened by the tool row's one palette button
// (`tool_row.dart`) so that two hundred and sixty-two colours cost a child one
// 56 dp control rather than a screen of them. The twelve paint-box colours are
// not in it: they are swatches in the row itself, one tap away.
//
// **The squares are far below the 56 dp tap-target floor, on purpose.**
// `AGENTS.md` asks for large touch targets and `PLAN.md` §4.2 sets the floor,
// and the player asked in so many words for "small squares" in a wide
// palette: 262 of them at 56 dp is 14 000 dp of scrolling, and the point of a
// grid is to see the whole spectrum at once. The exception is bounded rather
// than general. Each square's tappable cell is its side plus [PalettePopup.gap]
// — no dead space between two neighbours, so a finger that lands between them
// still picks one — and a miss costs nothing: the popup closes on a choice and
// reopens in one tap, and the choice is shown on the button and ringed in the
// grid, so a wrong one is seen at once. Every other control in the popup, the
// close button, keeps the floor.
//
// Selection is never colour alone (`PLAN-phase-8.md` §1): the chosen square is
// ringed (see [_SelectionRing]) and carries `selected` in the semantics tree,
// and every square has a spoken name because the grid draws no text.
//
// The grid is a [Stack] of positioned cells rather than a `Column` of `Row`s
// so that the ring is one more positioned child, painted last, over its
// neighbours. A square's own border could not do that: it would be painted
// before the squares that follow it, and would either be covered or have to
// take space from the layout and shift the grid when the selection moved.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/ui/tokens.dart';
import '../model/palette.dart';

/// Opens the colour popup over [context]'s screen and returns the palette
/// index the child chose, or null if the popup was dismissed — by a tap on
/// the barrier, the close button or the system back gesture.
///
/// [selectedIndex] is the colour in use now, so its square can be ringed. A
/// colour with no square here — a paint-box colour, which is a swatch in the
/// tool row — rings nothing (see [PalettePopup.selectedIndex]).
Future<int?> showPalettePopup(BuildContext context, {int? selectedIndex}) =>
    showDialog<int>(
      context: context,
      builder: (dialogContext) => PalettePopup(
        selectedIndex: selectedIndex,
        onSelected: (index) => Navigator.of(dialogContext).pop(index),
        onClose: () => Navigator.of(dialogContext).pop(),
      ),
    );

/// The popup's content: a [Dialog] holding the grid, the skin tones and a
/// close button.
class PalettePopup extends StatelessWidget {
  const PalettePopup({
    required this.onSelected,
    required this.onClose,
    this.selectedIndex,
    super.key,
  });

  /// The colour in use, if any: [DrawPalette.colors] index.
  ///
  /// Its square is ringed if it has one. A paint-box colour (0-11) has none:
  /// the tool row rings its swatch (`tool_row.dart`), and ringing the nearest
  /// grid square here as well would tell a child that two different colours
  /// are chosen. So the popup opens unringed then, which is also true — none
  /// of what it offers is the colour in use.
  final int? selectedIndex;

  /// Called with the palette index of the square tapped.
  final ValueChanged<int> onSelected;

  /// Called by the close button. Dismissing by the barrier does not come
  /// through here: the route closes itself.
  final VoidCallback onClose;

  /// The gap between two neighbouring squares, in dp. Part of each square's
  /// tappable cell, not dead space (see the file header).
  static const double gap = 2;

  /// The largest a square grows to, on a window with room to spare: past this
  /// a "small squares" palette stops being one.
  static const double maxSide = 28;

  /// The space between the grid and the skin-tone row, so that the tones read
  /// as a set of their own rather than a seventeenth row of the grid.
  static const double sectionGap = AppSpacing.sm;

  static const Key closeKey = ValueKey('PalettePopup.close');

  /// The ring that marks the selected square. Absent when [selectedIndex] has
  /// no square to mark, as it is for a paint-box colour.
  static const Key highlightKey = ValueKey('PalettePopup.highlight');

  static Key squareKey(int index) => ValueKey('PalettePopup.square.$index');

  /// The side of a square, in dp, for a grid given [width] and [height] to
  /// fill: whichever of the two is the tighter, capped at [maxSide].
  ///
  /// Never floored. A floor would overflow a window too small for it, and the
  /// phones this is checked on — 360 x 640 and 640 x 360 — come out above
  /// 14 dp without one (`palette_popup_test.dart`).
  static double sideFor({required double width, required double height}) {
    // Columns wide; rows tall plus the skin-tone row and the gap above it.
    final fromWidth = width / DrawPalette.gridColumns - gap;
    final fromHeight = (height - sectionGap) / (DrawPalette.gridRows + 1) - gap;
    return math.max(0, math.min(maxSide, math.min(fromWidth, fromHeight)));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Side by side where the window is wider than tall, which is where
          // a close button below the grid would cost the grid a row's height
          // it cannot spare; stacked otherwise.
          final sideBySide = constraints.maxWidth > constraints.maxHeight;
          const padding = AppSpacing.md;
          const closeExtent = AppTapTargets.min;
          final side = sideFor(
            width:
                constraints.maxWidth -
                2 * padding -
                (sideBySide ? closeExtent + AppSpacing.md : 0),
            height:
                constraints.maxHeight -
                2 * padding -
                (sideBySide ? 0 : closeExtent + AppSpacing.sm),
          );

          final grid = _Grid(
            side: side,
            selectedIndex: selectedIndex,
            onSelected: onSelected,
          );
          final close = IconButton(
            key: closeKey,
            onPressed: onClose,
            icon: const Icon(Icons.close),
            tooltip: 'Close',
          );

          return Padding(
            padding: const EdgeInsets.all(padding),
            child: sideBySide
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppSpacing.md,
                    children: [grid, close],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    spacing: AppSpacing.sm,
                    children: [grid, close],
                  ),
          );
        },
      ),
    );
  }
}

/// The grid and the skin-tone row, every square at one position computed from
/// [side] so nothing depends on how the framework would have wrapped them.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.side,
    required this.selectedIndex,
    required this.onSelected,
  });

  final double side;
  final int? selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final cell = side + PalettePopup.gap;
    final picker = DrawPalette.pickerIndices;
    // The skin tones are the last of [pickerIndices], after the grid, and sit
    // below it with a gap of their own.
    final skinTones = picker.length - DrawPalette.gridSize;
    final width = cell * DrawPalette.gridColumns;
    final height = cell * (DrawPalette.gridRows + 1) + PalettePopup.sectionGap;

    Offset origin(int position) {
      if (position < DrawPalette.gridSize) {
        return Offset(
          position % DrawPalette.gridColumns * cell,
          position ~/ DrawPalette.gridColumns * cell,
        );
      }
      return Offset(
        (position - DrawPalette.gridSize) * cell,
        DrawPalette.gridRows * cell + PalettePopup.sectionGap,
      );
    }

    assert(skinTones <= DrawPalette.gridColumns, 'the tones fit one row');

    int? ringedPosition;
    final squares = <Widget>[];
    for (var position = 0; position < picker.length; position++) {
      final index = picker[position];
      final at = origin(position);
      final selected = index == selectedIndex;
      if (selected) ringedPosition = position;
      squares.add(
        Positioned(
          left: at.dx,
          top: at.dy,
          width: cell,
          height: cell,
          child: _Square(
            key: PalettePopup.squareKey(index),
            index: index,
            side: side,
            selected: selected,
            onTap: () => onSelected(index),
          ),
        ),
      );
    }

    if (ringedPosition != null) {
      final at = origin(ringedPosition);
      squares.add(
        Positioned(
          left: at.dx + PalettePopup.gap / 2,
          top: at.dy + PalettePopup.gap / 2,
          width: side,
          height: side,
          // Last child, so it paints over every neighbour; ignored by hits so
          // the squares under it still take the tap.
          child: IgnorePointer(child: _SelectionRing(side: side)),
        ),
      );
    }

    return SizedBox(
      width: width,
      height: height,
      // Not clipped: the ring of an edge square reaches a few dp past the
      // grid, into the dialog's own padding.
      child: Stack(clipBehavior: Clip.none, children: squares),
    );
  }
}

/// One colour: a filled square with a hairline edge, inside a cell that
/// extends half a [PalettePopup.gap] past it on every side so that the tap
/// area has no seams.
///
/// The edge is there for the near-white squares, which would otherwise vanish
/// against a light dialog, and black against a dark one (`PLAN-phase-8.md`
/// §1) — the same reason every swatch in the tool row has one.
class _Square extends StatelessWidget {
  const _Square({
    required this.index,
    required this.side,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int index;
  final double side;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Semantics(
      label: DrawPalette.nameAt(index),
      button: true,
      selected: selected,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: SizedBox(
            width: side,
            height: side,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: DrawPalette.colorAt(index),
                borderRadius: BorderRadius.circular(2),
                border: Border.all(
                  color: colors.outlineVariant,
                  width: AppBorders.hairline,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The mark on the selected square: a [AppBorders.selected] ring in the text
/// colour drawn *outside* the square, and a thin ring in the surface colour
/// just inside its edge.
///
/// Two rings because no single colour reads against all 262 squares: the
/// outer one is as far from the dialog's background as a colour can be and
/// stands out against it and against every pale square; the inner one is what
/// separates it from a dark square, where the outer ring alone would blend
/// into the fill it hugs. The ring sits outside the layout — it is the grid's
/// last positioned child, [_Grid] — so moving the selection moves nothing else.
class _SelectionRing extends StatelessWidget {
  const _SelectionRing({required this.side});

  final double side;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final extent = side + 2 * AppBorders.selected;

    return OverflowBox(
      minWidth: 0,
      minHeight: 0,
      maxWidth: extent,
      maxHeight: extent,
      child: SizedBox(
        width: extent,
        height: extent,
        child: DecoratedBox(
          key: PalettePopup.highlightKey,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: colors.onSurface,
              width: AppBorders.selected,
            ),
          ),
          // A border does not inset its child, so the padding is what puts the
          // inner line on the square's own edge, inside the outer ring.
          child: Padding(
            padding: const EdgeInsets.all(AppBorders.selected),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: colors.surface, width: 1.5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
