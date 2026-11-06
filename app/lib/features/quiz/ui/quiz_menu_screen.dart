// `/quiz`: three big buttons (`PLAN-phase-10-quiz.md` §4.5).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/ui/big_button.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import 'quiz_play_screen.dart';
import 'quiz_style.dart';

/// The Quiz menu: a mix of the shelf, one title, or the shelf itself.
class QuizMenuScreen extends ConsumerWidget {
  const QuizMenuScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final known = ref.watch(activeProfileProvider).quiz.known;
    final catalog = ref.watch(quizCatalogProvider);
    // A mixed round needs a title that is both ticked and still offered: a
    // tick on a withdrawn title is kept in the save but plays nothing.
    final canQuiz = catalog.offeredTitles.any((t) => known.contains(t.id));
    final navigator = Navigator.of(context);

    return ScreenScaffold(
      title: quizTitle,
      child: QuizTheme(
        child: ContentWidthCap(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppSpacing.md,
              children: [
                BigButton(
                  icon: Icons.shuffle,
                  label: quizMeLabel,
                  onPressed: canQuiz
                      ? () => navigator.pushNamed(
                          AppRoutes.quizPlay,
                          arguments: const QuizPlayArgs.mixed(),
                        )
                      : null,
                ),
                // Directly under the disabled button, so a child who cannot
                // press it is told why in the place they are looking.
                if (!canQuiz)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: Text(
                      tickShelfHint,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                BigButton(
                  icon: Icons.format_list_bulleted,
                  label: pickOneLabel,
                  onPressed: () => navigator.pushNamed(AppRoutes.quizPick),
                ),
                // Highlighted while there is nothing to quiz on, so the way
                // forward is the one that stands out.
                BigButton(
                  icon: Icons.shelves,
                  label: myShelfLabel,
                  selected: !canQuiz,
                  onPressed: () => navigator.pushNamed(AppRoutes.quizShelf),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
