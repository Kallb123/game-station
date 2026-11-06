// The row both the shelf and the pick list draw for one title
// (`PLAN-phase-10-quiz.md` §4.5).

import 'package:flutter/material.dart';

import '../../../core/storage/save_data.dart';
import '../../../core/ui/tokens.dart';
import '../model/quiz_catalog.dart';
import 'quiz_style.dart';

/// One title as a full-width tap target: an optional tick, the collection's
/// glyph in the series colour, the name, and its best score once played.
///
/// It is one semantics node. [ticked] null means the tile has no tick (the pick
/// list), so no `checked` state is announced; otherwise the tick is both drawn
/// and announced, and the glyph alone never carries it.
class QuizTitleTile extends StatelessWidget {
  const QuizTitleTile({
    required this.title,
    required this.collection,
    required this.seriesColor,
    required this.progress,
    required this.onTap,
    this.ticked,
    super.key,
  });

  final QuizTitle title;
  final QuizCollection collection;
  final Color seriesColor;

  /// This profile's counters for the title, if it has any.
  final QuizTitleProgress? progress;

  final VoidCallback onTap;
  final bool? ticked;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final played = progress != null && progress!.rounds > 0;
    final best = played ? quizBestLabel(progress!.best) : null;

    return Semantics(
      container: true,
      button: true,
      checked: ticked,
      label: best == null ? title.name : '${title.name}, $best',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadii.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.card),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTapTargets.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  if (ticked != null) ...[
                    Icon(
                      ticked! ? Icons.check_box : Icons.check_box_outline_blank,
                      size: AppIconSizes.large,
                      color: colors.primary,
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  Icon(
                    quizCollectionIcon(collection),
                    size: AppIconSizes.large,
                    color: seriesColor,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (best != null)
                          Wrap(
                            spacing: AppSpacing.sm,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              QuizStars(count: quizStars(progress!.best)),
                              Text(best),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
