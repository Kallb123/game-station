// The board: one square grid of cells, at whatever size the puzzle is.
//
// There is no `if (size == 9)` anywhere in this file or in `sudoku_cell.dart`.
// Everything comes from `SudokuSpec` — the number of digits, where the box
// lines fall, and the shape a cell's pencil marks are laid out in — because a
// 6x6 whose boxes come out 3x2 instead of 2x3 is a grid that still looks
// plausible (`PLAN-phase-3.md` §4.5, `PLAN.md` §3.6).

import 'package:flutter/material.dart';

import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../model/sudoku_session.dart';
import 'sudoku_cell.dart';

/// How much of a cell's height one digit fills.
///
/// A proportion rather than a size from `AppTypeScale`: the digit is sized by
/// the geometry it sits in, so that the board reads the same on a phone and on
/// a tablet, and so that a text scale cannot clip it (`PLAN-phase-3.md` §4.5).
const double _digitFillRatio = 0.6;

/// The same, for one pencil mark, which shares its cell with up to eight
/// others.
const double _noteFillRatio = 0.22;

/// The board of [session], drawn square and as large as it is given room for.
///
/// Takes the session alone rather than a session and a `SudokuSpec` as
/// `PLAN-phase-3.md` §4.5 sketched: the session has carried its own spec since
/// PR 4, and two sources for one fact is one that can disagree.
class SudokuGridView extends StatelessWidget {
  /// A view of [session]'s board.
  const SudokuGridView({required this.session, super.key});

  /// The puzzle being played.
  final SudokuSession session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = _colorsFor(theme);
    final spec = session.spec;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The shorter side, so the board is square and fits: portrait leaves
        // the width, landscape leaves the height. An unbounded height — a
        // board inside a scrolling column — has no shorter side to take, and
        // the width is the answer that keeps it on screen.
        final side = constraints.hasBoundedHeight
            ? constraints.biggest.shortestSide
            : constraints.maxWidth;
        final cell = (side - 2 * AppBorders.gridBox) / spec.digits;

        return Center(
          child: SizedBox.square(
            dimension: side,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: colors.line,
                  width: AppBorders.gridBox,
                ),
              ),
              child: Column(
                children: [
                  for (var row = 0; row < spec.digits; row++)
                    Expanded(
                      child: Row(
                        children: [
                          for (var col = 0; col < spec.digits; col++)
                            Expanded(
                              child: SudokuCell(
                                key: ValueKey<int>(spec.indexAt(row, col)),
                                session: session,
                                index: spec.indexAt(row, col),
                                colors: colors,
                                digitSize: (cell * _digitFillRatio).clamp(
                                  AppTypeScale.caption,
                                  AppTypeScale.display,
                                ),
                                noteSize: (cell * _noteFillRatio).clamp(
                                  1,
                                  AppTypeScale.caption,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The board's colours, derived from the Sudoku role rather than from the
  /// app's own scheme (`PLAN-phase-3.md` §4.5), so the board reads as the same
  /// thing as the card that launched it. `roleScheme` memoises the derivation.
  SudokuCellColors _colorsFor(ThemeData theme) {
    final brightness = theme.brightness;
    final role = AppTheme.roleScheme(
      AppPalette.of(brightness).sudoku,
      brightness,
    );

    return SudokuCellColors(
      line: role.outline,
      selected: role.primaryContainer,
      sameDigit: role.secondaryContainer,
      peer: role.surfaceContainerHighest,
      given: role.onSurface,
      entered: role.primary,
      wrong: theme.colorScheme.error,
      note: role.onSurfaceVariant,
    );
  }
}
