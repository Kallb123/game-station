// The screen `/sudoku` opens: what there is to play, and what has been played.
//
// Four things, in the order a child wants them (`PLAN-phase-3.md` §4.7): the
// board they left half-done, today's puzzle with the streak it feeds, the size
// they want, and the difficulties that size offers. It replaces PR 6's
// temporary launcher, which is deleted with this file's arrival.
//
// Nothing here decides anything about a puzzle's *contents*. Which ids exist is
// `difficulties.dart`, which of them this profile has played is
// `sudoku_menu.dart`, and both are pure — so the arithmetic behind every number
// on this screen is tested without pumping a widget.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import '../../../core/clock.dart';
import '../../../core/ui/big_button.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../model/difficulties.dart';
import 'sudoku_play_screen.dart';

/// The screen's name.
const String sudokuMenuTitle = 'Sudoku';

/// The heading on the daily card.
const String dailyPuzzleTitle = 'Today’s puzzle';

/// The heading over the size toggle and the difficulty list.
const String pickPuzzleTitle = 'Pick a puzzle';

/// What each difficulty is called, and the glyph beside it.
///
/// The engine never returns a display string (`difficulty.dart`), so the words
/// are the app's. Public because the tests name the same ones the screen does.
///
/// The glyph is what a child who is still learning to read picks by, so the
/// four are a scale rather than four unrelated pictures — and none of them is a
/// sad face: "this one will make you unhappy" is not what Expert means
/// (`AGENTS.md`).
const Map<Difficulty, ({String label, IconData icon})> difficultyChoices =
    <Difficulty, ({String label, IconData icon})>{
      Difficulty.easy: (label: 'Easy', icon: Icons.sentiment_very_satisfied),
      Difficulty.medium: (label: 'Medium', icon: Icons.sentiment_satisfied),
      Difficulty.hard: (label: 'Hard', icon: Icons.local_fire_department),
      Difficulty.expert: (label: 'Expert', icon: Icons.rocket_launch),
    };

/// The glyph for [spec] in the size toggle.
///
/// A function rather than a map, because a const map cannot be keyed by a
/// [SudokuSpec] — it overrides `==` — and a lookup that can miss is a lookup
/// that can put a `null` where a child expects a picture.
IconData sizeIcon(SudokuSpec spec) =>
    spec == SudokuSpec.s6x6 ? Icons.grid_view : Icons.grid_on;

/// `9x9 Easy` — one tier, named the way every card on this screen names it.
String tierLabel(SudokuSpec spec, Difficulty difficulty) =>
    '${spec.label} ${difficultyChoices[difficulty]!.label}';

/// The label on the card that resumes a half-finished board.
String continueLabel(PuzzleId id) =>
    'Keep going: ${tierLabel(id.spec, id.difficulty)}';

/// The label on the daily card's button.
String dailyPlayLabel(PuzzleId id) =>
    'Play ${tierLabel(id.spec, id.difficulty)}';

/// What the daily card says about the streak.
///
/// Counted in days rather than shown as a number on its own, because the number
/// is meaningless without the noun, and there is no room to explain it twice.
String streakLabel(int streak) => switch (streak) {
  <= 0 => 'Play today to start a streak',
  1 => '1 day in a row',
  _ => '$streak days in a row',
};

/// The line under a difficulty, saying how it has gone so far.
String tierProgressLabel({required int solved, required int? bestTimeMs}) {
  if (solved == 0) return 'Not solved yet';
  final best = bestTimeMs == null
      ? ''
      : ' · Best ${formatElapsed(Duration(milliseconds: bestTimeMs))}';
  return 'Solved $solved$best';
}

/// Sudoku's own screen: continue, today, and everything else there is to play.
class SudokuMenuScreen extends ConsumerStatefulWidget {
  /// The menu on [AppRoutes.sudoku].
  const SudokuMenuScreen({super.key});

  @override
  ConsumerState<SudokuMenuScreen> createState() => _SudokuMenuScreenState();
}

class _SudokuMenuScreenState extends ConsumerState<SudokuMenuScreen> {
  /// The size the child picked, or null while the menu is still showing the one
  /// they last played. Null rather than a copy of that size, so a profile
  /// switch moves the toggle and a tap on it pins the toggle.
  SudokuSpec? _chosenSpec;

  @override
  void initState() {
    super.initState();
    // The daily puzzle is generated before it is tapped, so the card that is
    // hardest to resist opens instantly (`PLAN.md` §3.5). One id, once, on the
    // way in: a pre-warm per rebuild would generate puzzles nobody asked for,
    // and the source de-duplicates a warm against the load that follows it
    // anyway (`puzzle_source.dart`). Changing the size afterwards therefore
    // costs the generation it saved here, which is the 65 ms it always was.
    final menu = ref.read(sudokuMenuProvider);
    ref
        .read(puzzleSourceProvider)
        .prewarm(menu.dailyPuzzle(menu.lastSpec, _today()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final menu = ref.watch(sudokuMenuProvider);
    final spec = _chosenSpec ?? menu.lastSpec;
    final daily = menu.dailyPuzzle(spec, _today());
    final continuing = menu.continuePuzzle;

    return ScreenScaffold(
      title: sudokuMenuTitle,
      // Sudoku's colour, the one the home card that opened this screen is
      // drawn in (`home_screen.dart`), over the whole content rather than the
      // chrome: the screen's frame belongs to the app and its cards belong to
      // the game. Colour is never the only signal here — every card carries an
      // icon and a label as well (`tokens.dart`).
      child: Theme(
        data: theme.copyWith(
          colorScheme: AppTheme.roleScheme(
            AppPalette.of(theme.brightness).sudoku,
            theme.brightness,
          ),
        ),
        // A scrolling column rather than a [ListView]: the screen is three
        // cards and at most four rows, so nothing is saved by building them
        // lazily, and a row that exists only once it has been scrolled to is a
        // row no test — and no screen reader — can find without scrolling
        // first. It still scrolls, which is what a phone at 200% text scale
        // needs.
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (continuing != null) ...[
                BigButton(
                  icon: Icons.play_arrow,
                  label: continueLabel(continuing),
                  onPressed: () => _play(continuing),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _DailyCard(
                id: daily,
                streak: menu.streak,
                onPlay: () => _play(daily),
              ),
              const SizedBox(height: AppSpacing.xl),
              _SectionHeading(pickPuzzleTitle),
              const SizedBox(height: AppSpacing.md),
              _SizeToggle(
                chosen: spec,
                onChosen: (value) => setState(() => _chosenSpec = value),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final difficulty in difficultiesFor(spec))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _DifficultyRow(
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
    );
  }

  /// Which daily puzzle it is, from the clock the scope was given.
  int _today() => dayIndexFor(ref.read(nowProvider)());

  void _play(PuzzleId id) => Navigator.of(
    context,
  ).pushNamed(AppRoutes.sudokuPlay, arguments: SudokuPlayArgs(id));
}

/// Today's puzzle, and what solving it is worth.
///
/// A block rather than a button, because the streak is part of the offer: the
/// number only means anything next to the thing that would extend it.
class _DailyCard extends StatelessWidget {
  const _DailyCard({
    required this.id,
    required this.streak,
    required this.onPlay,
  });

  final PuzzleId id;
  final int streak;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppSpacing.md,
        children: [
          _CardLine(
            icon: Icons.today,
            color: colors.onSecondaryContainer,
            child: Semantics(
              header: true,
              child: Text(
                dailyPuzzleTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ),
          _CardLine(
            icon: Icons.calendar_month,
            color: colors.onSecondaryContainer,
            child: Text(
              streakLabel(streak),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          BigButton(
            icon: Icons.play_arrow,
            label: dailyPlayLabel(id),
            onPressed: onPlay,
          ),
        ],
      ),
    );
  }
}

/// A glyph and a line of text, wrapping rather than clipping at a large text
/// scale.
class _CardLine extends StatelessWidget {
  const _CardLine({
    required this.icon,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: AppIconSizes.large, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: child),
      ],
    );
  }
}

/// 9x9 or 6x6.
///
/// Two buttons rather than a switch or a dropdown: the choice is visible
/// without opening anything, each clears the primary tap target, and the chosen
/// one is a border and a check as well as a colour (`big_button.dart`).
class _SizeToggle extends StatelessWidget {
  const _SizeToggle({required this.chosen, required this.onChosen});

  final SudokuSpec chosen;
  final ValueChanged<SudokuSpec> onChosen;

  @override
  Widget build(BuildContext context) {
    return Row(
      spacing: AppSpacing.md,
      children: [
        for (final spec in sudokuSizes)
          // Expanded rather than a bare row child: [BigButton]'s label wraps,
          // and a flexible label needs a bounded width to wrap into.
          Expanded(
            child: BigButton(
              icon: sizeIcon(spec),
              label: spec.label,
              selected: spec == chosen,
              onPressed: () => onChosen(spec),
            ),
          ),
      ],
    );
  }
}

/// One difficulty: what it is called, how it has gone, and a way into it.
///
/// A [ListTile] rather than a [BigButton], because the row carries two lines —
/// the tier and the record — and the whole row is the target either way.
class _DifficultyRow extends StatelessWidget {
  const _DifficultyRow({
    required this.difficulty,
    required this.solved,
    required this.bestTimeMs,
    required this.onPlay,
  });

  final Difficulty difficulty;
  final int solved;
  final int? bestTimeMs;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final choice = difficultyChoices[difficulty]!;

    return ListTile(
      onTap: onPlay,
      // A floor, not a height: the tile still grows when the label wraps at a
      // large text scale. Primary rather than minimum because these rows are
      // what the screen is for, and a `ListTile` takes no size from the button
      // themes that hold the rest of the app above the floor (`theme.dart`).
      minTileHeight: AppTapTargets.primary,
      minVerticalPadding: AppSpacing.md,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      tileColor: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
      leading: Icon(choice.icon, size: AppIconSizes.large),
      title: Text(choice.label, style: theme.textTheme.titleMedium),
      subtitle: Text(
        tierProgressLabel(solved: solved, bestTimeMs: bestTimeMs),
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right, size: AppIconSizes.large),
    );
  }
}

/// A heading over a group, at the size the rest of the app puts one.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}
