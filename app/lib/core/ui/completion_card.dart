// What a finished puzzle says, and the two ways on from it. Shared by both
// puzzle screens, Sudoku and Tracks (`PLAN-phase-9-tracks.md` §4.12).
//
// **A card over the board rather than a screen of its own**
// (`PLAN-phase-3.md` §4.6): the grid a child has just finished stays visible
// behind it, and *Back* keeps one meaning — a route would give the back arrow
// two, one of which lands on a board that is already over.
//
// It takes its numbers rather than the session: the screen owns the clock and
// the format it is read in, and a summary widget that reached into a model to
// find them would be a second place that decides what a finished puzzle is
// worth.

import 'package:flutter/material.dart';

import 'big_button.dart';
import 'layout.dart';
import 'tokens.dart';

/// What the card says at the top. Public because the tests name the same
/// strings the card draws.
const String completionTitle = 'Well done!';

/// The three rows of numbers.
const String completionTimeLabel = 'Time';
const String completionHintsLabel = 'Hints';
const String completionMistakesLabel = 'Mistakes';

/// What the star means, spelled out beside it — the star is never the only
/// carrier of the fact (`AGENTS.md`, `PLAN.md` §9).
const String completionCleanLabel = 'No hints, no mistakes';

/// The way on to the next puzzle. The way back is named by each screen, through
/// [CompletionCard.backLabel].
const String nextPuzzleLabel = 'Next puzzle';

/// The card shown over a solved board.
class CompletionCard extends StatelessWidget {
  /// A card reporting a puzzle finished in [time], with [hints] and [mistakes].
  const CompletionCard({
    required this.time,
    required this.hints,
    required this.mistakes,
    required this.clean,
    required this.onNext,
    required this.backLabel,
    required this.onBack,
    super.key,
  }) : _score = null,
       _outOf = 0,
       _stars = 0,
       _nextLabel = nextPuzzleLabel;

  /// A card for a scored finish, a quiz round: [score] out of [outOf] with
  /// [stars] beside it. The same card with a different body rather than a
  /// second widget, so the two finishes cannot drift apart in layout.
  ///
  /// [onNext] is *Play again* in practice; null hides it.
  const CompletionCard.score({
    required int score,
    required int outOf,
    required int stars,
    required String nextLabel,
    required this.onNext,
    required this.backLabel,
    required this.onBack,
    super.key,
  }) : time = '',
       hints = 0,
       mistakes = 0,
       clean = false,
       // A named parameter cannot initialise a private field directly.
       // ignore: prefer_initializing_formals
       _score = score,
       // ignore: prefer_initializing_formals
       _outOf = outOf,
       // ignore: prefer_initializing_formals
       _stars = stars,
       // ignore: prefer_initializing_formals
       _nextLabel = nextLabel;

  /// How long it took, already formatted — `4:05`.
  final String time;

  /// How many hints were used.
  final int hints;

  /// How many mistakes were made: wrong digits in Sudoku, wrong connections in
  /// Tracks.
  final int mistakes;

  /// Whether this solve earned the star: no hints and no mistakes
  /// (`PLAN.md` §3.7).
  final bool clean;

  /// Play the next puzzle at this size and difficulty. Null where there is no
  /// next one, which only the last index of the endless list can reach.
  final VoidCallback? onNext;

  /// What the back button says: *Back to Sudoku*, *Back to Tracks*.
  final String backLabel;

  /// Back to where the puzzle was chosen.
  final VoidCallback onBack;

  /// Set only by [CompletionCard.score], which draws it instead of the timed
  /// rows.
  final int? _score;
  final int _outOf;
  final int _stars;
  final String _nextLabel;

  bool get _scored => _score != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      // Scrolls rather than clips: three rows of numbers and two primary
      // buttons at 200% text scale are taller than a small phone, and a child
      // who cannot reach *Back* is stuck on the screen (`PLAN-phase-3.md` §1).
      //
      // Capped at `maxContentWidth`: a `SingleChildScrollView` otherwise
      // fills the width it is given, which in landscape is the grid and the
      // keypad together (`PLAN-phase-5.md` §4.8) — full width there is a
      // dialog stretched edge to edge over a board it no longer resembles.
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: maxContentWidth),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        completionTitle,
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_scored) ...[
                      Text(
                        '$_score out of $_outOf',
                        style: theme.textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Center(child: _ScoreStars(count: _stars)),
                    ] else ...[
                      _Stat(label: completionTimeLabel, value: time),
                      _Stat(label: completionHintsLabel, value: '$hints'),
                      _Stat(label: completionMistakesLabel, value: '$mistakes'),
                      if (clean) ...[
                        const SizedBox(height: AppSpacing.md),
                        const _CleanStar(),
                      ],
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    if (onNext != null) ...[
                      BigButton(
                        icon: _scored ? Icons.replay : Icons.arrow_forward,
                        label: _nextLabel,
                        onPressed: onNext,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    BigButton(
                      icon: _scored ? Icons.arrow_back : Icons.grid_on,
                      label: backLabel,
                      onPressed: onBack,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One number and what it counts.
///
/// A row that wraps into two lines rather than a fixed-width table: at 200%
/// text scale "Mistakes" and its number do not fit across a small phone side by
/// side, and a table would clip one of them.
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      // Merged, so a screen reader says "Time 4:05" as one thing rather than
      // reading a label and a number as two.
      child: MergeSemantics(
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: AppSpacing.lg,
          children: [
            Text(label, style: theme.textTheme.bodyLarge),
            Text(
              value,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The star, and the words that carry the same fact.
class _CleanStar extends StatelessWidget {
  const _CleanStar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return MergeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.star,
            size: AppIconSizes.large,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              completionCleanLabel,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// The stars of a scored finish. Its own label rather than the quiz's widget:
/// `core/` imports nothing from a feature.
class _ScoreStars extends StatelessWidget {
  const _ScoreStars({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      label: '$count of 3 stars',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Icon(Icons.star, size: AppIconSizes.large, color: color),
          ],
        ),
      ),
    );
  }
}
