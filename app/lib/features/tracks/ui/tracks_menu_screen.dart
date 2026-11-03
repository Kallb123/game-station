// The screen `/tracks` opens: what there is to play, and what has been played.
//
// Sudoku's menu without the daily puzzle (`PLAN-phase-9-tracks.md` §4.14), and
// with the theme picker above the puzzles: the board they left half-done, the
// look they want, the size, and the difficulties that size offers.
//
// Nothing here decides anything about a puzzle's contents. Which ids exist is
// `tracks_difficulties.dart`, which of them this profile has played is
// `tracks_menu.dart`, and both are pure.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/ui/big_button.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/puzzle_menu.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../model/tracks_difficulties.dart';
import 'tracks_play_screen.dart';
import 'tracks_theme_picker.dart';

/// The heading over the size toggle and the difficulty list.
const String tracksPickPuzzleTitle = 'Pick a puzzle';

/// The glyph for [spec] in the size toggle: a bigger grid for a bigger board.
///
/// A function rather than a map, because a const map cannot be keyed by a
/// [TracksSpec] — it overrides `==` — and a lookup that can miss would put a
/// `null` where a child expects a picture.
IconData tracksSizeIcon(TracksSpec spec) => switch (spec.side) {
  5 => Icons.grid_view,
  7 => Icons.apps,
  _ => Icons.grid_on,
};

/// `7x7 Easy` — one tier, named the way every row on this screen names it.
String tracksTierLabel(TracksSpec spec, Difficulty difficulty) =>
    '${spec.label} ${difficultyChoices[difficulty]!.label}';

/// The label on the card that resumes a half-finished board.
String tracksContinueLabel(TracksPuzzleId id) =>
    'Keep going: ${tracksTierLabel(id.spec, id.difficulty)}';

/// Tracks' own screen: continue, the look, and everything else there is to
/// play.
class TracksMenuScreen extends ConsumerStatefulWidget {
  /// The menu on [AppRoutes.tracks].
  const TracksMenuScreen({super.key});

  @override
  ConsumerState<TracksMenuScreen> createState() => _TracksMenuScreenState();
}

class _TracksMenuScreenState extends ConsumerState<TracksMenuScreen> {
  /// The size the child picked, or null while the menu is still showing the one
  /// they last played, so a profile switch moves the toggle and a tap pins it.
  TracksSpec? _chosenSpec;

  @override
  void initState() {
    super.initState();
    // The puzzle the first suggestion would launch, generated before it is
    // tapped. One id, once, on the way in, for the reasons Sudoku's menu gives:
    // a pre-warm per rebuild would generate puzzles nobody asked for
    // (`PLAN-phase-9-tracks.md` §4.9, §4.14).
    final menu = ref.read(tracksMenuProvider);
    final spec = menu.lastSpec;
    ref
        .read(tracksPuzzleSourceProvider)
        .prewarm(menu.nextPuzzle(spec, menu.lastDifficultyFor(spec)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menu = ref.watch(tracksMenuProvider);
    final spec = _chosenSpec ?? menu.lastSpec;
    final continuing = menu.continuePuzzle;

    return ScreenScaffold(
      title: tracksMenuTitle,
      // The Puzzles colour, the one the Puzzles card on the home screen is
      // drawn in. The palette token is still called `sudoku`; renaming a token
      // is out of this change's scope.
      child: Theme(
        data: theme.copyWith(
          colorScheme: AppTheme.roleScheme(
            AppPalette.of(theme.brightness).sudoku,
            theme.brightness,
          ),
        ),
        // A scrolling column rather than a [ListView], for the reason the
        // Sudoku menu gives: nothing is saved by building rows lazily, and a
        // row that exists only once scrolled to cannot be found without it.
        child: ContentWidthCap(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (continuing != null) ...[
                  BigButton(
                    icon: Icons.play_arrow,
                    label: tracksContinueLabel(continuing),
                    onPressed: () => _play(continuing),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                const SectionHeading(pickThemeTitle),
                const SizedBox(height: AppSpacing.md),
                const TracksThemePicker(),
                const SizedBox(height: AppSpacing.xl),
                const SectionHeading(tracksPickPuzzleTitle),
                const SizedBox(height: AppSpacing.md),
                _SizeToggle(
                  chosen: spec,
                  onChosen: (value) => setState(() => _chosenSpec = value),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final difficulty in tracksDifficultiesFor(spec))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: DifficultyRow(
                      difficulty: difficulty,
                      solved: menu.solvedCount(spec, difficulty),
                      bestTimeMs: menu.bestTimeMs(spec, difficulty),
                      onPlay: () => _play(menu.nextPuzzle(spec, difficulty)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _play(TracksPuzzleId id) => Navigator.of(
    context,
  ).pushNamed(AppRoutes.tracksPlay, arguments: TracksPlayArgs(id));
}

/// 5x5, 7x7 or 9x9.
///
/// Buttons rather than a switch or a dropdown, as on the Sudoku menu: the
/// choice is visible without opening anything and the chosen one is a border
/// and a check as well as a colour (`big_button.dart`).
///
/// Stacked rather than in a row, unlike Sudoku's two. A `BigButton` needs about
/// 130 dp for its padding, glyph and check before its label gets any, so three
/// side by side overflow a 360 dp phone even at normal text size.
class _SizeToggle extends StatelessWidget {
  const _SizeToggle({required this.chosen, required this.onChosen});

  final TracksSpec chosen;
  final ValueChanged<TracksSpec> onChosen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppSpacing.sm,
      children: [
        for (final spec in tracksSizes)
          BigButton(
            icon: tracksSizeIcon(spec),
            label: spec.label,
            selected: spec == chosen,
            onPressed: () => onChosen(spec),
          ),
      ],
    );
  }
}
