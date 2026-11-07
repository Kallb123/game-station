// The screen a quiz round is played on (`PLAN-phase-10-quiz.md` §4.5-§4.7).
//
// The round itself is `QuizRound`, a plain object this screen drives. What the
// screen adds is the order things are written in: the round's effect on the
// save is applied when the last question is finished, or when a child stops
// part-way, and never both (`QuizRound.applyTo` is idempotent for a finished
// round, but a second write would be noise).

import 'dart:async';

import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/motif.dart';
import '../../../core/audio/providers.dart';
import '../../../core/clock.dart';
import '../../../core/game_rng.dart';
import '../../../core/haptics.dart';
import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/providers.dart';
import '../../../core/ui/big_button.dart';
import '../../../core/ui/completion_card.dart';
import '../../../core/ui/confetti.dart';
import '../../../core/ui/layout.dart';
import '../../../core/ui/safe_pop.dart';
import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../../../routes.dart';
import '../data/providers.dart';
import '../model/quiz_picker.dart';
import '../model/quiz_round.dart';
import 'quiz_style.dart';

/// Which round to play: a mix of the shelf, or one title
/// (`PLAN-phase-10-quiz.md` §4.5).
///
/// A typed object for the reason `TracksPlayArgs` is: `arguments` is
/// `Object?`, and the route table checks the type rather than casting.
@immutable
class QuizPlayArgs {
  /// A round drawn from every ticked title.
  const QuizPlayArgs.mixed() : titleId = null;

  /// A round over the one title [titleId] names.
  const QuizPlayArgs.title(String this.titleId);

  /// The title to play, or null for a mixed round.
  final String? titleId;

  @override
  bool operator ==(Object other) =>
      other is QuizPlayArgs && other.titleId == titleId;

  @override
  int get hashCode => titleId.hashCode;
}

/// Line height of the question and answers: the theme's 1.4 is for running
/// text, and these are short blocks that wrap at 200 % text, where a tighter
/// line is the difference between fitting a phone and scrolling (§4.8).
const double _quizTextHeight = 1.2;

/// One round of the quiz, played.
class QuizPlayScreen extends ConsumerStatefulWidget {
  const QuizPlayScreen({required this.args, super.key});

  final QuizPlayArgs args;

  @override
  ConsumerState<QuizPlayScreen> createState() => _QuizPlayScreenState();
}

class _QuizPlayScreenState extends ConsumerState<QuizPlayScreen> {
  /// Captured once: the quit path writes through it after an `await`.
  late final ProgressRepository _repository;

  /// Null when nothing is offered or ticked. The menus never lead here then,
  /// but a stale route should meet a gentle line, not an error.
  QuizRound? _round;

  /// Whether the last question has been finished and the result written.
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _repository = ref.read(progressRepositoryProvider);
    ref.read(appAudioProvider).preload(const [
      Motif.sudokuCorrect,
      Motif.sudokuWrong,
      Motif.sudokuComplete,
    ]);

    // Seeded from the injected clock like the arcade games, so a test that
    // fixes the clock fixes the round.
    final seed = ref.read(nowProvider)().millisecondsSinceEpoch & 0xFFFFFFFF;
    final picker = QuizPicker(ref.read(quizCatalogProvider));
    final progress = _repository.activeProfile.quiz;
    final rng = GameRng(seed);
    final id = widget.args.titleId;
    _round = id == null
        ? picker.mixedRound(progress, rng)
        : picker.singleTitleRound(id, progress, rng);
  }

  void _choose(int option) {
    final round = _round!;
    // A solved question, or an option already tried, ignores further taps.
    if (round.isSolved(round.index) ||
        round.wrongTriesAt(round.index).contains(option)) {
      return;
    }

    final right = round.answer(option);
    if (right) {
      ref.read(appAudioProvider).play(Motif.sudokuCorrect);
      ref.read(appHapticsProvider).tap();
    } else {
      // Softer than the Sudoku mistake, and silent to the hand: a wrong answer
      // is not a failure (§1).
      ref.read(appAudioProvider).play(Motif.sudokuWrong, gain: 0.5);
    }
    setState(() {});
  }

  void _next() {
    final round = _round!;
    if (!round.isSolved(round.index)) return;

    if (round.index < round.questions.length - 1) {
      setState(round.advance);
      return;
    }

    // Written before the card appears, so a force-quit on the card loses
    // nothing.
    _repository.updateQuiz(round.applyTo);
    unawaited(_repository.flush());
    ref.read(appAudioProvider).play(Motif.sudokuComplete);
    setState(() => _finished = true);
  }

  Future<void> _confirmQuit() async {
    final round = _round;
    // Nothing answered loses nothing; a finished round is already written.
    if (round == null || _finished || round.solvedCount == 0) {
      popIfPossible(context);
      return;
    }

    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(quizQuitTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(quizKeepPlayingLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(quizStopLabel),
          ),
        ],
      ),
    );
    if (!mounted || !(stop ?? false)) return;

    // The partial advance, so the questions already seen are not asked first
    // next time; `applyTo` leaves rounds and best alone for an unfinished
    // round.
    _repository.updateQuiz(round.applyTo);
    unawaited(_repository.flush());
    popIfPossible(context);
  }

  void _playAgain() {
    Navigator.of(
      context,
    ).pushReplacementNamed(AppRoutes.quizPlay, arguments: widget.args);
  }

  @override
  Widget build(BuildContext context) {
    return QuizTheme(
      // The theme must sit above the scaffold, so its colours reach the
      // dialog and the card as well.
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_confirmQuit());
        },
        child: Builder(builder: _scaffold),
      ),
    );
  }

  Widget _scaffold(BuildContext context) {
    final round = _round;
    return Scaffold(
      body: SafeArea(
        child: round == null
            ? _nothingToAsk(context)
            : _playing(context, round),
      ),
    );
  }

  Widget _nothingToAsk(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            nothingToAskMessage,
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          BigButton(
            icon: Icons.arrow_back,
            label: backToQuizLabel,
            onPressed: () => popIfPossible(context),
          ),
        ],
      ),
    );
  }

  Widget _playing(BuildContext context, QuizRound round) {
    // Capped on a tablet as every menu is: three answers stretched across
    // 800 dp read as bars rather than buttons. A phone is drawn unchanged.
    final question = ContentWidthCap(
      child: QuizQuestionView(
        round: round,
        onChoose: _choose,
        onNext: _next,
        onBack: () => unawaited(_confirmQuit()),
      ),
    );
    if (!_finished) return question;

    // The last question stays under the card; the barrier stops a tap
    // reaching it.
    final colors = Theme.of(context).colorScheme;
    final score = round.score;
    return Stack(
      fit: StackFit.expand,
      children: [
        question,
        ModalBarrier(
          color: colors.scrim.withValues(alpha: 0.4),
          dismissible: false,
        ),
        Confetti(
          colors: [
            colors.primary,
            colors.secondary,
            colors.tertiary,
            colors.primaryContainer,
          ],
        ),
        CompletionCard.score(
          score: score,
          outOf: quizRoundLength,
          stars: quizStars(score),
          nextLabel: playAgainLabel,
          onNext: _playAgain,
          backLabel: backToQuizLabel,
          onBack: () => popIfPossible(context),
        ),
      ],
    );
  }
}

/// The play screen's chrome and the question on it: back, progress dots, the
/// question, its three answers and the reserved *Next* slot.
///
/// Public and driven by a [QuizRound] so the §4.8 text-size test can pump the
/// real layout. It holds no state of its own; the screen rebuilds it as the
/// round moves.
class QuizQuestionView extends StatelessWidget {
  const QuizQuestionView({
    required this.round,
    required this.onChoose,
    required this.onNext,
    required this.onBack,
    super.key,
  });

  final QuizRound round;

  /// Called with the tapped option's index; ignored once answered.
  final ValueChanged<int> onChoose;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = round.current;
    final solved = round.isSolved(round.index);
    final wrong = round.wrongTriesAt(round.index);
    final isLast = round.index == round.questions.length - 1;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            // Tighter above and below than at the sides: at 200 % text on a
            // 640 dp window every dp is a line of the longest question.
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Back and the dots share a row: a heading on its own line
                // costs a line of a 640 dp window at 200% text for nothing
                // the dots do not already say.
                Row(
                  children: [
                    IconButton(
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.arrow_back,
                        size: AppIconSizes.large,
                      ),
                      tooltip: 'Back',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: _ProgressDots(round: round)),
                  ],
                ),
                // Debug and profile builds only: an unchecked question is one
                // a reviewer has not signed off, and a child never sees it
                // (§4.2).
                if (!kReleaseMode && !current.question.checked)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(label: Text('unchecked')),
                  ),
                const SizedBox(height: AppSpacing.sm),
                Semantics(
                  header: true,
                  child: Text(
                    current.question.q,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      height: _quizTextHeight,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                for (var i = 0; i < current.options.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.xs),
                  _AnswerButton(
                    key: ValueKey('quizAnswer$i'),
                    text: current.options[i],
                    state: solved && i == current.answerIndex
                        ? _AnswerState.right
                        : wrong.contains(i)
                        ? _AnswerState.wrong
                        : solved
                        ? _AnswerState.other
                        : _AnswerState.open,
                    onTap: () => onChoose(i),
                  ),
                ],
                const SizedBox(height: AppSpacing.sm),
                _NextSlot(
                  visible: solved,
                  label: isLast ? finishLabel : nextLabel,
                  onPressed: onNext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ten dots: answered filled, the current one ringed, the rest outlined.
class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.round});

  final QuizRound round;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    final count = round.questions.length;
    return Semantics(
      container: true,
      label: 'Question ${round.index + 1} of $count',
      child: ExcludeSemantics(
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < count; i++)
              _dot(
                color,
                answered: round.isSolved(i),
                current: i == round.index,
              ),
          ],
        ),
      ),
    );
  }

  Widget _dot(Color color, {required bool answered, required bool current}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: answered ? color : null,
        // The current dot's thicker ring is the shape cue, so position never
        // rests on colour alone.
        border: Border.all(
          color: color,
          width: current ? AppBorders.selected : AppBorders.hairline,
        ),
      ),
    );
  }
}

enum _AnswerState { open, right, wrong, other }

/// One answer. Built from a [Material] and an [InkWell] rather than a button
/// so that locking it does not turn it the disabled grey: the right and wrong
/// colours have to survive the lock.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    super.key,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final String text;
  final _AnswerState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // The theme has no success token, and the arcade role scheme's tertiary
    // is a salmon that reads as the wrong answer's red. The right answer
    // borrows the Sudoku green's container instead: the one green the palette
    // already has, checked for contrast by `contrast_test.dart` as a role
    // colour. The tick and the semantics label still carry the meaning.
    final success = AppTheme.roleScheme(
      AppPalette.of(theme.brightness).sudoku,
      theme.brightness,
    );
    final (background, foreground, border) = switch (state) {
      _AnswerState.open => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
        Colors.transparent,
      ),
      _AnswerState.right => (
        success.primaryContainer,
        success.onPrimaryContainer,
        success.onPrimaryContainer,
      ),
      _AnswerState.wrong => (
        colors.errorContainer,
        colors.onErrorContainer,
        Colors.transparent,
      ),
      _AnswerState.other => (
        colors.surfaceContainerHighest,
        colors.onSurface,
        Colors.transparent,
      ),
    };
    final locked = state != _AnswerState.open;

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      enabled: !locked,
      label: state == _AnswerState.right ? '$text, right answer' : text,
      onTap: locked ? null : onTap,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.button),
          side: BorderSide(color: border, width: AppBorders.selected),
        ),
        child: InkWell(
          onTap: locked ? null : onTap,
          customBorder: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.button),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppTapTargets.primary),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      text,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: foreground,
                        height: _quizTextHeight,
                      ),
                    ),
                  ),
                  if (state == _AnswerState.right) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.check_circle,
                      size: AppIconSizes.large,
                      color: foreground,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// *Next* or *Finish*, whose space is kept before an answer so the answers do
/// not jump when it appears.
///
/// Before an answer the slot holds an invisible button with a blank label
/// rather than the real one, so the height is exactly the button's at any
/// text size while the word is not in the tree to be found or read.
class _NextSlot extends StatelessWidget {
  const _NextSlot({
    required this.visible,
    required this.label,
    required this.onPressed,
  });

  final bool visible;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (visible) {
      return BigButton(
        icon: Icons.arrow_forward,
        label: label,
        onPressed: onPressed,
      );
    }
    return const Visibility(
      visible: false,
      maintainSize: true,
      maintainAnimation: true,
      maintainState: true,
      child: BigButton(
        icon: Icons.arrow_forward,
        // A non-breaking space: a plain one would be trimmed to no line.
        label: ' ',
        onPressed: null,
      ),
    );
  }
}
