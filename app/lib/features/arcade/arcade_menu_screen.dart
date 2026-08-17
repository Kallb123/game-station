// The screen `/arcade` opens: what there is to play, the child's own options
// for it, and how they have done so far (`PLAN-phase-4.md` §4.10). It replaces
// PR 4's `_ArcadePlaceholder`, and the temporary button that placeholder drew
// to reach `/arcade/invaders` is deleted with it.
//
// One game today, so this is the first `GameCard` `PLAN.md` §4.4's later games
// join rather than a screen built to hold seven of them already — a menu
// shaped by seven hypothetical games fits none of them.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/providers.dart';
import '../../core/storage/save_data.dart';
import '../../core/ui/big_button.dart';
import '../../core/ui/screen_scaffold.dart';
import '../../core/ui/theme.dart';
import '../../core/ui/tokens.dart';
import '../../routes.dart';
import 'invaders/invaders_screen.dart' show invadersGameId;
import 'shared/game_shell.dart' show noScoresYetMessage;

/// The Invaders card's own heading.
const String invadersTitle = 'Invaders';

/// The Invaders card's button.
const String playInvadersLabel = 'Play Invaders';

/// Shown on the Invaders card when this profile has no score in the selected
/// mode yet — distinct from [noScoresYetMessage], which is what the table
/// under it shows for the same reason.
const String notPlayedYetMessage = 'Not played yet';

/// The heading over the three toggles.
const String optionsSectionLabel = 'Options';

/// The three toggles, each a child's own choice rather than the tablet's
/// (`PLAN-phase-4.md` §3): fewer rows and slower aliens, the ship firing on
/// its own, and which side LEFT and RIGHT sit on.
const String easyModeLabel = 'Easy mode';
const String autoFireLabel = 'Auto-fire';
const String padSideLabel = 'Buttons on the left';

/// The heading over the top-five table.
const String topScoresSectionLabel = 'Top scores';

/// `Best 15400 · Wave 7` — what the Invaders card shows for a played mode.
String bestScoreLabel(HighScore best) =>
    'Best ${best.score} · Wave ${best.wave}';

/// `1. 15400 · Wave 7` — one row of the top-five table.
String scoreRowLabel(int rank, HighScore score) =>
    '$rank. ${score.score} · Wave ${score.wave}';

/// Arcade's own screen: one game to play, this child's options for it, and
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
    void setOptions({bool? easyMode, bool? autoFire, PadSide? padSide}) => ref
        .read(progressRepositoryProvider)
        .setArcadeOptions(
          easyMode: easyMode,
          autoFire: autoFire,
          padSide: padSide,
        );

    final scores =
        profile.arcade.games[invadersGameId]?.highScores
            .where((score) => score.easy == profile.arcadeEasyMode)
            .toList() ??
        const <HighScore>[];
    // The repository keeps `highScores` sorted best first within a mode
    // (`progress_repository.dart`'s `_withHighScore`), so the card's best
    // entry is simply the first that survived the filter above.
    final best = scores.isEmpty ? null : scores.first;

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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InvadersCard(
                best: best,
                onPlay: () =>
                    Navigator.of(context).pushNamed(AppRoutes.arcadeInvaders),
              ),
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeading(optionsSectionLabel),
              const SizedBox(height: AppSpacing.md),
              BigButton(
                icon: Icons.sentiment_satisfied_alt,
                label: easyModeLabel,
                selected: profile.arcadeEasyMode,
                onPressed: () => setOptions(easyMode: !profile.arcadeEasyMode),
              ),
              const SizedBox(height: AppSpacing.sm),
              BigButton(
                icon: Icons.bolt,
                label: autoFireLabel,
                selected: profile.arcadeAutoFire,
                onPressed: () => setOptions(autoFire: !profile.arcadeAutoFire),
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
              const SizedBox(height: AppSpacing.xl),
              const _SectionHeading(topScoresSectionLabel),
              const SizedBox(height: AppSpacing.md),
              _TopScores(scores: scores),
            ],
          ),
        ),
      ),
    );
  }
}

/// What there is to play, and how this profile has done at it in the
/// currently selected mode.
class _InvadersCard extends StatelessWidget {
  const _InvadersCard({required this.best, required this.onPlay});

  final HighScore? best;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final best = this.best;

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
            icon: Icons.rocket_launch,
            color: colors.onSecondaryContainer,
            child: Semantics(
              header: true,
              child: Text(
                invadersTitle,
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
              best == null ? notPlayedYetMessage : bestScoreLabel(best),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          BigButton(
            icon: Icons.play_arrow,
            label: playInvadersLabel,
            onPressed: onPlay,
          ),
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
  const _TopScores({required this.scores});

  final List<HighScore> scores;

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
            child: Text(scoreRowLabel(i + 1, scores[i]), style: style),
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
