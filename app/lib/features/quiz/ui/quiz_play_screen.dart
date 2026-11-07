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
    // The view caps its own width: only its one-column layout is capped,
    // since two columns need the room.
    final question = QuizQuestionView(
      round: round,
      onChoose: _choose,
      onNext: _next,
      onBack: () => unawaited(_confirmQuit()),
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

/// The play screen's chrome and the question on it: back, progress bar, the
/// question card, its three answers and the feedback slot
/// (`PLAN-quiz-screen.md` §4.2).
///
/// Public and driven by a [QuizRound] so the layout test can pump the real
/// layout. It owns only a scroll controller; the screen rebuilds it as the
/// round moves.
class QuizQuestionView extends StatefulWidget {
  const QuizQuestionView({
    required this.round,
    required this.onChoose,
    required this.onNext,
    required this.onBack,
    super.key,
  });

  final QuizRound round;

  /// Called with the tapped option's index; ignored once it is locked.
  final ValueChanged<int> onChoose;
  final VoidCallback onNext;
  final VoidCallback onBack;

  @override
  State<QuizQuestionView> createState() => _QuizQuestionViewState();
}

class _QuizQuestionViewState extends State<QuizQuestionView> {
  final ScrollController _scroll = ScrollController();

  /// Identifies the feedback slot, so it can be scrolled into view.
  final GlobalKey _feedbackKey = GlobalKey();

  /// Whether the question on show was solved at the last build. The round is
  /// mutated in place, so the widget cannot compare old and new itself.
  late bool _wasSolved = widget.round.isSolved(widget.round.index);

  @override
  void didUpdateWidget(QuizQuestionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final solved = widget.round.isSolved(widget.round.index);
    if (solved && !_wasSolved) {
      // After the frame, because the solved state is what makes the slot
      // show *Next*: at large text it can be below the fold, and a child
      // should not have to find it (§4.3).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final slot = _feedbackKey.currentContext;
        if (!mounted || slot == null) return;
        unawaited(
          Scrollable.ensureVisible(
            slot,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      });
    }
    _wasSolved = solved;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final current = round.current;
    final solved = round.isSolved(round.index);
    final wrong = round.wrongTriesAt(round.index);

    return LayoutBuilder(
      builder: (context, constraints) {
        // The Fire tablet sideways. A tall tablet or a phone has one column.
        final wide =
            constraints.maxWidth >= _twoColumnMinWidth &&
            constraints.maxWidth > constraints.maxHeight;

        final content = Padding(
          // Tighter above and below than at the sides: every dp is a line
          // of the question on a small window.
          padding: EdgeInsets.fromLTRB(
            wide ? AppSpacing.xl : AppSpacing.lg,
            AppSpacing.md,
            wide ? AppSpacing.xl : AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopRow(round: round, onBack: widget.onBack),
              const SizedBox(height: AppSpacing.lg),
              // Debug and profile builds only: an unchecked question is one a
              // reviewer has not signed off, and a child never sees it
              // (`PLAN-phase-10-quiz.md` §4.2).
              if (!kReleaseMode && !current.question.checked)
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(label: Text('unchecked')),
                ),
              Expanded(
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _QuestionCard(
                              text: current.question.q,
                              fontSize: AppQuizSizes.questionWide,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xl),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _answers(current, solved, wrong),
                                const SizedBox(height: AppSpacing.lg),
                                _feedback(solved, wrong),
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _QuestionCard(
                              text: current.question.q,
                              fontSize: AppQuizSizes.question,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _answers(current, solved, wrong),
                          const SizedBox(height: AppSpacing.lg),
                          _feedback(solved, wrong),
                        ],
                      ),
              ),
            ],
          ),
        );

        // The card is meant to fill what the answers leave, which is a bounded
        // height; inside a scroll view it takes the larger of the viewport
        // and what the content needs, so a window that is too small scrolls
        // instead of overflowing.
        return Scrollbar(
          controller: _scroll,
          // A page that scrolls should say so: a thumb that appears only on
          // touch is invisible to a child who has not touched it (§4.3).
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scroll,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: wide ? content : ContentWidthCap(child: content),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _answers(QuizRoundQuestion current, bool solved, List<int> wrong) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < current.options.length; i++) ...[
          if (i > 0) const SizedBox(height: AppQuizSizes.answerGap),
          _AnswerButton(
            key: ValueKey('quizAnswer$i'),
            index: i,
            text: current.options[i],
            state: solved && i == current.answerIndex
                ? _AnswerState.right
                : wrong.contains(i)
                ? _AnswerState.wrong
                : solved
                ? _AnswerState.other
                : _AnswerState.open,
            onTap: () => widget.onChoose(i),
          ),
        ],
      ],
    );
  }

  Widget _feedback(bool solved, List<int> wrong) {
    final isLast = widget.round.index == widget.round.questions.length - 1;
    // An IndexedStack is as tall as its tallest child, whatever is showing and
    // whatever the text size, so the answers above never move when the slot
    // changes. It also lays out, paints, hit-tests and reads out only the
    // child at [index], so the hidden ones cannot be tapped or heard.
    return IndexedStack(
      key: _feedbackKey,
      index: solved
          ? 2
          : wrong.isEmpty
          ? 0
          : 1,
      alignment: Alignment.center,
      children: [
        const _IdleHint(),
        const _TryAgainBox(),
        _SolvedFeedback(
          label: isLast ? finishLabel : nextLabel,
          onNext: widget.onNext,
        ),
      ],
    );
  }
}

/// The narrowest view that gets two columns. A 600 dp tablet held upright is
/// wider than a phone but too narrow to split in half.
const double _twoColumnMinWidth = 720;

/// The scheme for a role seed, for the brightness being drawn.
ColorScheme _role(BuildContext context, Color Function(AppPalette) seed) {
  final brightness = Theme.of(context).brightness;
  return AppTheme.roleScheme(seed(AppPalette.of(brightness)), brightness);
}

/// The system text scale, held to [AppQuizSizes.textCeiling] for text drawn at
/// [fontSize], so the quiz never draws below its design size and never
/// beyond the ceiling.
TextScaler _scaler(BuildContext context, double fontSize) => MediaQuery.of(
  context,
).textScaler.clamp(maxScaleFactor: AppQuizSizes.textCeiling / fontSize);

/// Back, the progress bar and the counter.
class _TopRow extends StatelessWidget {
  const _TopRow({required this.round, required this.onBack});

  final QuizRound round;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final count = round.questions.length;
    return SizedBox(
      height: AppTapTargets.min,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back, size: AppIconSizes.large),
            style: IconButton.styleFrom(
              backgroundColor: colors.surfaceContainerHigh,
              foregroundColor: colors.onSurface,
              fixedSize: const Size.square(AppTapTargets.min),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            // One label for the bar and the counter together: the segments
            // and "3 / 10" are the same fact twice.
            child: Semantics(
              container: true,
              label: 'Question ${round.index + 1} of $count',
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    Expanded(child: _ProgressBar(round: round)),
                    const SizedBox(width: AppSpacing.lg),
                    Text(
                      '${round.index + 1} / $count',
                      textScaler: _scaler(context, 22),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One segment per question: solved filled, the current one ringed, the rest
/// faint.
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.round});

  final QuizRound round;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < round.questions.length; i++) ...[
          if (i > 0) const SizedBox(width: AppQuizSizes.progressGap),
          Expanded(
            child: Container(
              height: AppQuizSizes.progressHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(
                  AppQuizSizes.progressRadius,
                ),
                color: round.isSolved(i)
                    ? colors.primary
                    : i == round.index
                    ? colors.primaryContainer
                    : colors.surfaceContainerHighest,
                // The current segment's ring is the shape cue, so position
                // never rests on colour alone.
                border: i == round.index
                    ? Border.all(
                        color: colors.primary,
                        width: AppBorders.selected,
                      )
                    : null,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The question, on a tinted surface rather than a container colour so it
/// cannot be mistaken for the second answer, which is the arcade container.
class _QuestionCard extends StatelessWidget {
  const _QuestionCard({required this.text, required this.fontSize});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final arcade = _role(context, (p) => p.arcade);
    return Container(
      decoration: BoxDecoration(
        color: arcade.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppQuizSizes.radius),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl - 2,
        AppSpacing.xl,
        AppSpacing.xl - 2,
        AppSpacing.xl - AppSpacing.xs,
      ),
      alignment: Alignment.topLeft,
      child: Semantics(
        header: true,
        child: Text(
          text,
          textScaler: _scaler(context, fontSize),
          style: TextStyle(
            fontSize: fontSize,
            height: AppQuizSizes.lineHeight,
            fontWeight: FontWeight.w700,
            color: arcade.onSurface,
          ),
        ),
      ),
    );
  }
}

enum _AnswerState { open, right, wrong, other }

/// One answer. Built from a [Material] and an [InkWell] rather than a button
/// so that locking it does not turn it the disabled grey: the state colours
/// have to survive the lock.
///
/// Its place sets its colour and shape (circle, triangle, square), so colour
/// never says which answer is which on its own.
class _AnswerButton extends StatelessWidget {
  const _AnswerButton({
    super.key,
    required this.index,
    required this.text,
    required this.state,
    required this.onTap,
  });

  final int index;
  final String text;
  final _AnswerState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme;
    final role = _role(context, (p) => [p.sudoku, p.arcade, p.draw][index % 3]);
    final wrong = state == _AnswerState.wrong;
    final right = state == _AnswerState.right;
    // A wrong try greys out, never reddens: nothing here is a failure (§1).
    final background = wrong
        ? surface.surfaceContainerHighest
        : role.primaryContainer;
    final foreground = wrong
        ? surface.onSurfaceVariant
        : role.onPrimaryContainer;
    final locked = state != _AnswerState.open;

    final label = right
        ? '$text, right answer'
        : wrong
        ? '$text, not this one'
        : text;
    final radius = BorderRadius.circular(AppQuizSizes.radius);

    Widget body = Material(
      color: background,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        onTap: locked ? null : onTap,
        customBorder: RoundedRectangleBorder(borderRadius: radius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppQuizSizes.answerMinHeight,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 16, 12),
            child: Row(
              children: [
                _shape(foreground),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        text,
                        textScaler: _scaler(context, AppQuizSizes.answer),
                        style: TextStyle(
                          fontSize: AppQuizSizes.answer,
                          height: AppQuizSizes.lineHeight,
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      if (wrong)
                        Text(
                          notThisOneNote,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: foreground,
                          ),
                        ),
                    ],
                  ),
                ),
                if (right || wrong) ...[
                  const SizedBox(width: AppSpacing.md),
                  _badge(right: right, role: role, surface: surface),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (right) {
      // The ring is painted outside the answer's own box, so it appears
      // without anything moving (§1, "nothing jumps").
      const outset = AppQuizSizes.ring + AppQuizSizes.ringGap;
      body = Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -outset,
            right: -outset,
            top: -outset,
            bottom: -outset,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(
                      AppQuizSizes.radius + outset,
                    ),
                    side: BorderSide(
                      color: surface.onSurface,
                      width: AppQuizSizes.ring,
                    ),
                  ),
                ),
              ),
            ),
          ),
          body,
        ],
      );
    } else if (state == _AnswerState.other) {
      body = Opacity(opacity: 0.4, child: body);
    }

    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      enabled: !locked,
      label: label,
      onTap: locked ? null : onTap,
      child: body,
    );
  }

  Widget _shape(Color color) {
    final ShapeBorder border = switch (index % 3) {
      0 => const CircleBorder(),
      1 => StarBorder.polygon(sides: 3),
      _ => RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    };
    return SizedBox.square(
      dimension: AppQuizSizes.shape,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: color, shape: border),
      ),
    );
  }

  Widget _badge({
    required bool right,
    required ColorScheme role,
    required ColorScheme surface,
  }) {
    return Container(
      width: AppQuizSizes.badge,
      height: AppQuizSizes.badge,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: right ? role.onPrimaryContainer : surface.surfaceContainer,
      ),
      child: Icon(
        right ? Icons.check : Icons.close,
        size: AppIconSizes.standard,
        color: right ? role.primaryContainer : surface.onSurfaceVariant,
      ),
    );
  }
}

/// What the slot says before anything has been tried.
class _IdleHint extends StatelessWidget {
  const _IdleHint();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        tapAnAnswerHint,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: AppTypeScale.body,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// What the slot says after a wrong try: kind, and with a smile.
class _TryAgainBox extends StatelessWidget {
  const _TryAgainBox();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl - AppSpacing.xs,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadii.button),
        ),
        child: Row(
          children: [
            Icon(Icons.sentiment_satisfied, size: 36, color: colors.primary),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(
                tryAgainMessage,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the slot says once the question is solved: praise, then *Next* or
/// *Finish*. The only [FilledButton] on the screen.
class _SolvedFeedback extends StatelessWidget {
  const _SolvedFeedback({required this.label, required this.onNext});

  final String label;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Green for a good answer, as the right answer's colour is the Sudoku
    // role; the star and the words say it too.
    final success = _role(context, (p) => p.sudoku);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.star, size: 30, color: success.primary),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  wellDoneMessage,
                  style: TextStyle(
                    fontSize: 26,
                    height: AppTypeScale.headingHeight,
                    fontWeight: FontWeight.w600,
                    color: success.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Theme(
          data: theme.copyWith(colorScheme: success),
          child: BigButton(
            icon: Icons.arrow_forward,
            label: label,
            onPressed: onNext,
          ),
        ),
      ],
    );
  }
}
