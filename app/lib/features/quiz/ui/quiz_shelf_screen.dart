// `/quiz/shelf`: tick what has been read or watched (`PLAN-phase-10-quiz.md`
// §4.5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/ui/big_button.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../data/providers.dart';
import '../model/quiz_catalog.dart';
import 'quiz_style.dart';
import 'quiz_title_tile.dart';

/// Shown when the catalog offers nothing. Only a stale route reaches it.
const String quizNothingYetMessage = 'There are no quizzes here yet.';

/// The shelf: one collection at a time, its series, and a tile per title.
class QuizShelfScreen extends ConsumerStatefulWidget {
  const QuizShelfScreen({super.key});

  @override
  ConsumerState<QuizShelfScreen> createState() => _QuizShelfScreenState();
}

class _QuizShelfScreenState extends ConsumerState<QuizShelfScreen> {
  /// The collection being shown. Screen state, not saved: it is a view, and
  /// the ticks it edits are what persist.
  QuizCollection? _chosen;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(quizCatalogProvider);
    final quiz = ref.watch(activeProfileProvider).quiz;
    final repo = ref.read(progressRepositoryProvider);
    final brightness = Theme.of(context).brightness;
    final offered = {for (final t in catalog.offeredTitles) t.id};

    // Only series with something to show, each with only its offered titles.
    final shelf = <(QuizSeries, List<QuizTitle>)>[
      for (final s in catalog.series)
        if (s.titles.any((t) => offered.contains(t.id)))
          (
            s,
            [
              for (final t in s.titles)
                if (offered.contains(t.id)) t,
            ],
          ),
    ];
    final collections = [
      for (final c in QuizCollection.values)
        if (shelf.any((e) => e.$1.collection == c)) c,
    ];
    final current = collections.contains(_chosen)
        ? _chosen!
        : (collections.isEmpty ? null : collections.first);

    final children = <Widget>[];
    if (current == null) {
      children.add(
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            quizNothingYetMessage,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      );
    } else {
      // A switch with one position is noise, so it needs two collections.
      // Stacked, as Tracks' size toggle is: three side by side overflow a
      // phone.
      if (collections.length > 1) {
        for (final c in collections) {
          children.add(
            BigButton(
              icon: quizCollectionIcon(c),
              label: quizCollectionLabel(c),
              selected: c == current,
              onPressed: () => setState(() => _chosen = c),
            ),
          );
        }
        children.add(const SizedBox(height: AppSpacing.md));
      }
      for (final (series, titles) in shelf) {
        if (series.collection != current) continue;
        final ids = [for (final t in titles) t.id];
        final allTicked = ids.every(quiz.known.contains);
        final color = quizSeriesColor(catalog, series, brightness);
        children.add(
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Semantics(
              header: true,
              child: Text(
                series.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        );
        children.add(
          BigButton(
            icon: Icons.done_all,
            label: quizAllLabel(series.collection),
            selected: allTicked,
            // Ticks all if any is unticked, else unticks all.
            onPressed: () => repo.setQuizKnown(ids, known: !allTicked),
          ),
        );
        for (final t in titles) {
          final ticked = quiz.known.contains(t.id);
          children.add(
            QuizTitleTile(
              title: t,
              collection: series.collection,
              seriesColor: color,
              progress: quiz.titles[t.id],
              ticked: ticked,
              onTap: () => repo.setQuizKnown([t.id], known: !ticked),
            ),
          );
        }
      }
    }

    return ScreenScaffold(
      title: myShelfLabel,
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
