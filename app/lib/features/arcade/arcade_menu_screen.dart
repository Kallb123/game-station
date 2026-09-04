// The screen `/arcade` opens: what there is to play, the child's own options
// for it, and how they have done so far (`PLAN-phase-4.md` §4.10). Extended in
// `PLAN-phase-7-snake.md` §4.9 for a second game: the card that was Invaders'
// alone becomes `_GameCard`, given a game's name, best, options and top-five
// table, so a second game gets the same shape rather than a second layout.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../core/storage/save_data.dart';
import '../../core/ui/big_button.dart';
import '../../core/ui/layout.dart';
import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../routes.dart';
import 'invaders/invaders_screen.dart' show invadersGameId;
import 'shared/game_shell.dart' show noScoresYetMessage;
import 'snake/snake_screen.dart' show snakeGameId;

/// The Invaders card's own heading.
const String invadersTitle = 'Invaders';

/// The Invaders card's button.
const String playInvadersLabel = 'Play Invaders';

/// The Snake card's own heading.
const String snakeTitle = 'Snake';

/// The Snake card's button.
const String playSnakeLabel = 'Play Snake';

/// Shown on a card when this profile has no score in the selected mode yet —
/// distinct from [noScoresYetMessage], which is what the table under it shows
/// for the same reason.
const String notPlayedYetMessage = 'Not played yet';

/// The heading over the arcade-wide toggles.
const String optionsSectionLabel = 'Options';

/// The heading over a card's own top-five table.
const String topScoresSectionLabel = 'Top scores';

/// The two arcade-wide toggles left in the Options section once auto-fire and
/// the counting toggles move onto their own games' cards
/// (`PLAN-phase-7-snake.md` §4.9): fewer rows and slower aliens for the whole
/// arcade, and which side LEFT and RIGHT sit on.
const String easyModeLabel = 'Easy mode';
const String padSideLabel = 'Buttons on the left';

/// The Invaders card's own option: the ship fires on its own, so a small
/// player only has to steer.
const String autoFireLabel = 'Auto-fire';

/// The Snake card's own options: whether targets carry numbers to count, and
/// whether that count is in ones or twos (`PLAN-phase-7-snake.md` §4.3,
/// §4.8). [countIn2sLabel] is drawn only while [numbersLabel] is selected.
const String numbersLabel = 'Numbers';
const String countIn2sLabel = 'Count in 2s';

/// `Best 15400 · Wave 7` — what a card shows for a played mode. [roundLabel]
/// is the word for what [HighScore.wave] counts: Invaders calls it a wave,
/// Snake a level, matching the word `GameShell`'s HUD already uses for each
/// (`PLAN-phase-7-snake.md` §4.7).
String bestScoreLabel(HighScore best, {String roundLabel = 'Wave'}) =>
    'Best ${best.score} · $roundLabel ${best.wave}';

/// `Longest 24` — the Snake card's lifetime longest snake
/// (`ArcadeGameProgress.bestLength`, `PLAN-phase-7-snake.md` §4.9). Lifetime
/// rather than per-mode, so it does not change when a toggle does.
String longestSnakeLabel(int length) => 'Longest $length';

/// `1. 15400 · Wave 7` — one row of a top-five table.
String scoreRowLabel(int rank, HighScore score, {String roundLabel = 'Wave'}) =>
    '$rank. ${score.score} · $roundLabel ${score.wave}';

/// Arcade's own screen: the games to play, this child's options for each, and
/// the top five for whichever mode those options currently choose.
class ArcadeMenuScreen extends ConsumerWidget {
  const ArcadeMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final profile = ref.watch(activeProfileProvider);

    // Read when a toggle is tapped rather than held from this build, so
    // nothing here keeps a repository from a scope that has since been
    // replaced (the same reasoning `settings_screen.dart`'s `update` follows).
    void setOptions({
      bool? easyMode,
      bool? autoFire,
      PadSide? padSide,
      SnakeCounting? snakeCounting,
    }) => ref
        .read(progressRepositoryProvider)
        .setArcadeOptions(
          easyMode: easyMode,
          autoFire: autoFire,
          padSide: padSide,
          snakeCounting: snakeCounting,
        );

    final invadersScores =
        profile.arcade.games[invadersGameId]?.highScores
            .where((score) => score.easy == profile.arcadeEasyMode)
            .toList() ??
        const <HighScore>[];
    // The repository keeps `highScores` sorted best first within a mode
    // (`progress_repository.dart`'s `_withHighScore`), so a card's best entry
    // is simply the first that survived the filter above.
    final invadersBest = invadersScores.isEmpty ? null : invadersScores.first;

    final counting = profile.snakeCounting != SnakeCounting.off;
    final snakeProgress = profile.arcade.games[snakeGameId];
    final snakeScores =
        snakeProgress?.highScores
            .where(
              (score) =>
                  score.easy == profile.arcadeEasyMode &&
                  score.counting == counting,
            )
            .toList() ??
        const <HighScore>[];
    final snakeBest = snakeScores.isEmpty ? null : snakeScores.first;

    return ScreenScaffold(
      title: 'Arcade',
      // The arcade's own colour, the one the home card that opened this
      // screen is drawn in (`home_screen.dart`), over the content rather than
      // the chrome — the same split `sudoku_menu_screen.dart` makes for
      // Sudoku's half.
      child: Theme(
        data: theme.copyWith(
          colorScheme: AppTheme.roleScheme(
            AppPalette.of(theme.brightness).arcade,
            theme.brightness,
          ),
        ),
        child: ContentWidthCap(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _GameCard(
                  icon: Icons.rocket_launch,
                  title: invadersTitle,
                  bestLine: invadersBest == null
                      ? notPlayedYetMessage
                      : bestScoreLabel(invadersBest),
                  playLabel: playInvadersLabel,
                  onPlay: () =>
                      Navigator.of(context).pushNamed(AppRoutes.arcadeInvaders),
                  toggles: [
                    BigButton(
                      icon: Icons.bolt,
                      label: autoFireLabel,
                      selected: profile.arcadeAutoFire,
                      onPressed: () =>
                          setOptions(autoFire: !profile.arcadeAutoFire),
                    ),
                  ],
                  scores: invadersScores,
                ),
                const SizedBox(height: AppSpacing.md),
                _GameCard(
                  icon: Icons.videogame_asset,
                  title: snakeTitle,
                  bestLine: snakeBest == null
                      ? notPlayedYetMessage
                      : bestScoreLabel(snakeBest, roundLabel: 'Level'),
                  extraLine: longestSnakeLabel(snakeProgress?.bestLength ?? 0),
                  playLabel: playSnakeLabel,
                  onPlay: () =>
                      Navigator.of(context).pushNamed(AppRoutes.arcadeSnake),
                  toggles: [
                    BigButton(
                      icon: Icons.pin,
                      label: numbersLabel,
                      selected: counting,
                      onPressed: () => setOptions(
                        snakeCounting: counting
                            ? SnakeCounting.off
                            : SnakeCounting.ones,
                      ),
                    ),
                    if (counting)
                      BigButton(
                        icon: Icons.filter_2,
                        label: countIn2sLabel,
                        selected: profile.snakeCounting == SnakeCounting.twos,
                        onPressed: () => setOptions(
                          snakeCounting:
                              profile.snakeCounting == SnakeCounting.twos
                              ? SnakeCounting.ones
                              : SnakeCounting.twos,
                        ),
                      ),
                  ],
                  scores: snakeScores,
                  roundLabel: 'Level',
                ),
                const SizedBox(height: AppSpacing.xl),
                const _SectionHeading(optionsSectionLabel),
                const SizedBox(height: AppSpacing.md),
                BigButton(
                  icon: Icons.sentiment_satisfied_alt,
                  label: easyModeLabel,
                  selected: profile.arcadeEasyMode,
                  onPressed: () =>
                      setOptions(easyMode: !profile.arcadeEasyMode),
                ),
                const SizedBox(height: AppSpacing.sm),
                BigButton(
                  icon: Icons.swap_horiz,
                  label: padSideLabel,
                  selected: profile.padSide == PadSide.left,
                  onPressed: () => setOptions(
                    padSide: profile.padSide == PadSide.left
                        ? PadSide.right
                        : PadSide.left,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One game: its name, its best score for the mode the toggles above it
/// currently select, its own options, its Play button, and its own top-five
/// table (`PLAN-phase-7-snake.md` §4.9). What was `_InvadersCard` before a
/// second game needed the same shape.
class _GameCard extends StatelessWidget {
  const _GameCard({
    required this.icon,
    required this.title,
    required this.bestLine,
    this.extraLine,
    this.toggles = const [],
    required this.playLabel,
    required this.onPlay,
    required this.scores,
    this.roundLabel = 'Wave',
  });

  final IconData icon;
  final String title;
  final String bestLine;

  /// The Snake card's lifetime longest-snake line; null on every other card.
  final String? extraLine;

  /// This game's own options, drawn under its Play button.
  final List<Widget> toggles;

  final String playLabel;
  final VoidCallback onPlay;
  final List<HighScore> scores;

  /// The word for what a score's `wave` field counts, passed on to
  /// [scoreRowLabel] so the table reads the same word as [bestLine].
  final String roundLabel;

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
            icon: icon,
            color: colors.onSecondaryContainer,
            child: Semantics(
              header: true,
              child: Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          ),
          _CardLine(
            icon: Icons.emoji_events,
            color: colors.onSecondaryContainer,
            child: Text(
              bestLine,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          if (extraLine != null)
            _CardLine(
              icon: Icons.straighten,
              color: colors.onSecondaryContainer,
              child: Text(
                extraLine!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSecondaryContainer,
                ),
              ),
            ),
          BigButton(
            icon: Icons.play_arrow,
            label: playLabel,
            onPressed: onPlay,
          ),
          for (final toggle in toggles) toggle,
          Semantics(
            header: true,
            child: Text(
              topScoresSectionLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          _TopScores(scores: scores, roundLabel: roundLabel),
        ],
      ),
    );
  }
}

/// A glyph and a line of text, wrapping rather than clipping at a large text
/// scale. The same shape `sudoku_menu_screen.dart`'s daily card uses its own
/// copy of, for the same reason: a widget this small is not worth a shared
/// import across two features that otherwise share nothing.
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

/// This profile's top five for the mode `scores` was already filtered to, or
/// the empty state when it has none.
class _TopScores extends StatelessWidget {
  const _TopScores({required this.scores, this.roundLabel = 'Wave'});

  final List<HighScore> scores;
  final String roundLabel;

  @override
  Widget build(BuildContext context) {
    if (scores.isEmpty) {
      return Text(
        noScoresYetMessage,
        style: Theme.of(context).textTheme.bodyMedium,
        textAlign: TextAlign.center,
      );
    }

    final style = Theme.of(context).textTheme.bodyMedium;
    return Column(
      children: [
        for (var i = 0; i < scores.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              scoreRowLabel(i + 1, scores[i], roundLabel: roundLabel),
              style: style,
            ),
          ),
      ],
    );
  }
}

/// A heading over a group, at the size the rest of the app puts one — the
/// same shape `sudoku_menu_screen.dart`'s own copy is.
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
