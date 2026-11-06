// `/quiz/pick`: choose one title to play (`PLAN-phase-10-quiz.md` §4.5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/puzzle_menu.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../model/quiz_catalog.dart';
import 'quiz_play_screen.dart';
import 'quiz_shelf_screen.dart' show quizNothingYetMessage;
import 'quiz_style.dart';
import 'quiz_title_tile.dart';

/// Every offered title, by collection and series, ticked ones first.
class QuizPickScreen extends ConsumerWidget {
  const QuizPickScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(quizCatalogProvider);
    final quiz = ref.watch(activeProfileProvider).quiz;
    final brightness = Theme.of(context).brightness;
    final theme = Theme.of(context);
    final offered = {for (final t in catalog.offeredTitles) t.id};
    final navigator = Navigator.of(context);

    final children = <Widget>[];
    for (final collection in QuizCollection.values) {
      var headed = false;
      for (final series in catalog.series) {
        if (series.collection != collection) continue;
        final shown = [
          for (final t in series.titles)
            if (offered.contains(t.id)) t,
        ];
        if (shown.isEmpty) continue;
        if (!headed) {
          headed = true;
          children.add(SectionHeading(quizCollectionLabel(collection)));
        }
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Semantics(
              header: true,
              child: Text(series.name, style: theme.textTheme.titleMedium),
            ),
          ),
        );
        // Ticked first; the two filters below keep order, so each group keeps the
        // series' own reading order.
        final ordered = [
          ...shown.where((t) => quiz.known.contains(t.id)),
          ...shown.where((t) => !quiz.known.contains(t.id)),
        ];
        final color = quizSeriesColor(catalog, series, brightness);
        for (final t in ordered) {
          children.add(
            QuizTitleTile(
              title: t,
              collection: collection,
              seriesColor: color,
              progress: quiz.titles[t.id],
              onTap: () => navigator.pushNamed(
                AppRoutes.quizPlay,
                arguments: QuizPlayArgs.title(t.id),
              ),
            ),
          );
        }
      }
    }
    if (children.isEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(quizNothingYetMessage, style: theme.textTheme.bodyLarge),
        ),
      );
    }

    return ScreenScaffold(
      title: pickOneLabel,
      child: QuizTheme(
        child: ContentWidthCap(
          child: ListView.separated(
            itemCount: children.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) => children[i],
          ),
        ),
      ),
    );
  }
}
