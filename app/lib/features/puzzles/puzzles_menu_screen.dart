// The Puzzles menu: the two puzzle games behind the home screen's one card
// (PLAN-phase-9-tracks.md §4.14).
//
// Two picture cards and nothing to read, for the same reason the home screen
// has three: whatever else stood on this screen would be something to get
// through before a child could play. It warms no puzzle; each game's own menu
// does that once it opens.

import 'package:flutter/material.dart';

import '../../core/ui/big_button.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../routes.dart';
import '../sudoku/ui/sudoku_menu_screen.dart' show sudokuMenuTitle;
import '../tracks/model/tracks_difficulties.dart' show tracksMenuTitle;

/// The title of the Puzzles menu, and the label of the home card that opens it.
const String puzzlesMenuTitle = 'Puzzles';

/// The glyph of the Sudoku card, the same one the Sudoku menu uses.
const IconData puzzlesSudokuIcon = Icons.grid_on;

/// The glyph of the Tracks card.
const IconData puzzlesTracksIcon = Icons.route;

/// How tall a card is allowed to get in landscape, matching the home screen's
/// cards so the two screens read as one family.
const double _landscapeCardHeight = 200;

/// The menu between the home screen and the two puzzle games.
class PuzzlesMenuScreen extends StatelessWidget {
  const PuzzlesMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Both games are the Puzzles role. The palette token is still named
    // `sudoku`; renaming a token is not part of adding the second game.
    final colors = AppTheme.roleScheme(
      AppPalette.of(theme.brightness).sudoku,
      theme.brightness,
    );

    const sudoku = _PuzzleCard(
      icon: puzzlesSudokuIcon,
      label: sudokuMenuTitle,
      route: AppRoutes.sudoku,
    );
    const tracks = _PuzzleCard(
      icon: puzzlesTracksIcon,
      label: tracksMenuTitle,
      route: AppRoutes.tracks,
    );

    return ScreenScaffold(
      title: puzzlesMenuTitle,
      child: Theme(
        data: theme.copyWith(colorScheme: colors),
        child: isLandscapeWindow(context)
            ? Row(
                children: [
                  _landscapeCell(sudoku),
                  const SizedBox(width: AppSpacing.lg),
                  _landscapeCell(tracks),
                ],
              )
            : const ContentWidthCap(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: sudoku),
                    SizedBox(height: AppSpacing.lg),
                    Expanded(child: tracks),
                  ],
                ),
              ),
      ),
    );
  }

  static Widget _landscapeCell(Widget card) => Expanded(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: maxContentWidth,
          maxHeight: _landscapeCardHeight,
        ),
        child: card,
      ),
    ),
  );
}

/// One game, labelled with the title its own menu carries, so the card and
/// the screen it opens cannot be renamed apart.
class _PuzzleCard extends StatelessWidget {
  const _PuzzleCard({
    required this.icon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return BigButton(
      icon: icon,
      label: label,
      onPressed: () => Navigator.of(context).pushNamed(route),
    );
  }
}
