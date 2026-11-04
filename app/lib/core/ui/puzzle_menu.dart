// The pieces the Sudoku menu and the Tracks menu share.
//
// Both menus end in the same list: a row per difficulty, saying how it has
// gone so far, under a heading. Moving the words, the glyphs and the two
// widgets here keeps the games' menus from drifting apart, and keeps either
// feature from importing the other (`PLAN-phase-9-tracks.md` §4.14).

import 'package:flutter/material.dart';
import 'package:puzzle_engine/puzzle_engine.dart';

import 'completion_card.dart';
import 'puzzle_clock.dart';
import 'tokens.dart';

/// What each difficulty is called, and the glyph beside it.
///
/// The engine never returns a display string (`difficulty.dart`), so the words
/// are the app's. Public because the tests name the same ones the screens do.
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

/// The line under a difficulty, saying how it has gone so far.
///
/// [bestAssists] is what the best solve cost in hints and mistakes, or null
/// where that is unknown; it is ignored when there is no [bestTimeMs], because
/// a detail about a solve that has no time would describe nothing
/// (`PLAN-best-time-assists.md` §4.6). A count of zero is left out, and the
/// all-zero case reuses [completionCleanLabel] so the menu and the completion
/// card say one thing one way.
String tierProgressLabel({
  required int solved,
  required int? bestTimeMs,
  ({int hints, int mistakes})? bestAssists,
}) {
  if (solved == 0) return 'Not solved yet';
  if (bestTimeMs == null) return 'Solved $solved';
  final base =
      'Solved $solved · Best ${formatElapsed(Duration(milliseconds: bestTimeMs))}';
  if (bestAssists == null) return base;

  final hints = bestAssists.hints;
  final mistakes = bestAssists.mistakes;
  if (hints == 0 && mistakes == 0) return '$base · $completionCleanLabel';
  final parts = <String>[
    if (hints > 0) '$hints ${hints == 1 ? 'hint' : 'hints'}',
    if (mistakes > 0) '$mistakes ${mistakes == 1 ? 'mistake' : 'mistakes'}',
  ];
  return '$base · ${parts.join(', ')}';
}

/// One difficulty: what it is called, how it has gone, and a way into it.
///
/// A [ListTile] rather than a `BigButton`, because the row carries two lines —
/// the tier and the record — and the whole row is the target either way.
class DifficultyRow extends StatelessWidget {
  /// The row for [difficulty], with [solved] and [bestTimeMs] as its record.
  const DifficultyRow({
    required this.difficulty,
    required this.solved,
    required this.bestTimeMs,
    required this.onPlay,
    this.bestAssists,
    super.key,
  });

  /// The tier this row launches.
  final Difficulty difficulty;

  /// How many puzzles of this tier have been finished.
  final int solved;

  /// The best time in milliseconds, or null where none has been set.
  final int? bestTimeMs;

  /// What the best solve cost, or null where that is unknown
  /// (`PLAN-best-time-assists.md` §4.6).
  final ({int hints, int mistakes})? bestAssists;

  /// Called on a tap anywhere on the row.
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
        tierProgressLabel(
          solved: solved,
          bestTimeMs: bestTimeMs,
          bestAssists: bestAssists,
        ),
        style: theme.textTheme.bodySmall,
      ),
      trailing: const Icon(Icons.chevron_right, size: AppIconSizes.large),
    );
  }
}

/// A heading over a group, at the size the rest of the app puts one.
class SectionHeading extends StatelessWidget {
  /// A heading reading [text].
  const SectionHeading(this.text, {super.key});

  /// The words.
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
