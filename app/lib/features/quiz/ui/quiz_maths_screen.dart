// `/quiz/maths`: what to practise, then Start (`PLAN-quiz-maths.md` §4.5).
//
// The settings are the profile's and are remembered, so Start comes first: a
// child who set up once starts in one tap.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../../core/storage/save_data.dart';
import '../../../core/ui/big_button.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/puzzle_menu.dart';
import '../../../core/ui/screen_scaffold.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../model/maths_generator.dart';
import 'quiz_play_screen.dart';
import 'quiz_style.dart';

/// The word beside each operation's symbol: the names a primary school uses.
String mathsOpLabel(QuizMathsOp op) => switch (op) {
  QuizMathsOp.add => 'Adding',
  QuizMathsOp.subtract => 'Taking away',
  QuizMathsOp.multiply => 'Times tables',
  QuizMathsOp.divide => 'Dividing',
};

/// The Maths settings and the way into a Maths round.
class QuizMathsScreen extends ConsumerWidget {
  const QuizMathsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maths = ref.watch(activeProfileProvider).quiz.maths;
    final theme = Theme.of(context);
    // Read at tap time rather than held from this build, for the reason
    // `arcade_menu_screen.dart`'s `setOptions` gives.
    void update(QuizMathsProgress Function(QuizMathsProgress) change) =>
        ref.read(progressRepositoryProvider).updateQuizMaths(change);

    final usesSums =
        maths.ops.contains(QuizMathsOp.add) ||
        maths.ops.contains(QuizMathsOp.subtract);
    final usesTables =
        maths.ops.contains(QuizMathsOp.multiply) ||
        maths.ops.contains(QuizMathsOp.divide);

    Widget hint(String text) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Text(text, style: theme.textTheme.bodyLarge),
    );

    final children = <Widget>[
      BigButton(
        icon: Icons.play_arrow,
        label: mathsStartLabel,
        onPressed: maths.isPlayable
            ? () => Navigator.of(context).pushNamed(
                AppRoutes.quizPlay,
                arguments: const QuizPlayArgs.maths(),
              )
            : null,
      ),
      // Directly under the disabled button, so a child who cannot press it
      // is told why in the place they are looking, as on the Quiz menu.
      if (!maths.isPlayable)
        hint(maths.ops.isEmpty ? mathsPickOpHint : mathsPickTableHint),
      if (maths.rounds > 0)
        Row(
          children: [
            QuizStars(count: quizStars(maths.best)),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                quizBestLabel(maths.best),
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      const SizedBox(height: AppSpacing.sm),
      const SectionHeading(mathsOpsHeading),
      for (final op in QuizMathsOp.values)
        BigButton.glyph(
          glyph: quizMathsSymbols[op]!,
          label: mathsOpLabel(op),
          selected: maths.ops.contains(op),
          // Turning the last one off is allowed; Start then says why it is
          // disabled, which is clearer than a toggle that refuses to move.
          onPressed: () => update(
            (m) => m.copyWith(
              ops: m.ops.contains(op)
                  ? ({...m.ops}..remove(op))
                  : {...m.ops, op},
            ),
          ),
        ),
      if (usesSums) ...[
        const SizedBox(height: AppSpacing.sm),
        const SectionHeading(mathsUpToHeading),
        Row(
          spacing: AppSpacing.sm,
          children: [
            for (final n in quizMathsUpToChoices)
              Expanded(
                child: _NumberToggle(
                  key: ValueKey('mathsUpTo$n'),
                  number: n,
                  semanticsLabel: 'Up to $n',
                  selected: maths.upTo == n,
                  onTap: () => update((m) => m.copyWith(upTo: n)),
                ),
              ),
          ],
        ),
      ],
      if (usesTables) ...[
        const SizedBox(height: AppSpacing.sm),
        const SectionHeading(mathsTablesHeading),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var t = 1; t <= quizMathsMaxTable; t++)
              SizedBox.square(
                dimension: AppTapTargets.primary,
                child: _NumberToggle(
                  key: ValueKey('mathsTable$t'),
                  number: t,
                  semanticsLabel: '$t times table',
                  selected: maths.tables.contains(t),
                  onTap: () => update(
                    (m) => m.copyWith(
                      tables: m.tables.contains(t)
                          ? ({...m.tables}..remove(t))
                          : {...m.tables, t},
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    ];

    return ScreenScaffold(
      title: mathsLabel,
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

/// A number that toggles: a times table, or a size for adding.
///
/// Drawn as [BigButton] draws a selected choice — the container colour, a
/// thick border and a check — so a choice never rests on colour alone. Too
/// small for [BigButton]'s padding, which is why it is its own widget.
class _NumberToggle extends StatelessWidget {
  const _NumberToggle({
    required this.number,
    required this.semanticsLabel,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final int number;
  final String semanticsLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: const Size(AppTapTargets.primary, AppTapTargets.primary),
          padding: const EdgeInsets.all(AppSpacing.xs),
          backgroundColor: selected ? colors.primaryContainer : null,
          foregroundColor: selected ? colors.onPrimaryContainer : null,
          side: BorderSide(
            color: selected ? colors.onPrimaryContainer : Colors.transparent,
            width: AppBorders.selected,
          ),
        ),
        // Scaled down rather than clipped at large text: the number has to
        // stay whole inside a square that does not grow.
        child: FittedBox(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$number',
                style: const TextStyle(
                  fontSize: AppTypeScale.title,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: AppIconSizes.standard,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
