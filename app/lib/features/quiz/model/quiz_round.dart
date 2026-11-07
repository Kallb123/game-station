// One round of the quiz as a play session: ten questions already drawn,
// ordered and given their options, plus how far a child has got with them
// (`PLAN-phase-10-quiz.md` §4.6).
//
// Pure Dart like the rest of `model/`: `QuizPicker` builds a round, the screen
// (PR 6) drives it, and `applyTo` is the only place a round's effect on the
// save is worked out, so it is tested without a widget or a store.

import '../../../core/storage/save_data.dart';
import 'quiz_catalog.dart';

/// Questions in a round. No more than [minQuestionsPerTitle], so every offered
/// title's order holds a question the round has not yet asked (§4.6).
const int quizRoundLength = 10;

/// One question as presented: its three options and where the right one sits.
class QuizRoundQuestion {
  /// Creates a presented question; [options] is copied so it stays immutable.
  QuizRoundQuestion({
    required this.question,
    required this.titleId,
    required List<String> options,
    required this.answerIndex,
    required this.drawIndex,
    required this.seedAfter,
    required this.nextAfter,
    required this.poolAfter,
  }) : options = List.unmodifiable(options);

  final QuizQuestion question;

  /// The title the question was drawn from; a mixed round has several.
  final String titleId;

  /// Exactly three: the right answer and two wrong ones, in shown order.
  final List<String> options;

  /// Position of [QuizQuestion.a] in [options].
  final int answerIndex;

  /// Where this question fell in the round's draw order. Presented order is
  /// level-sorted, so only this says which of two questions of one title was
  /// taken later from its shuffled order.
  final int drawIndex;

  /// The title's cursor just after this question was drawn: the values that
  /// go in the save if this is the last question of its title that was
  /// solved (§4.7).
  final int seedAfter;
  final int nextAfter;
  final int poolAfter;
}

/// A round being played.
class QuizRound {
  /// Creates a round over [questions] in presented order. [titleId] is the
  /// title of a single-title round, or null for a mixed one.
  QuizRound({required this.titleId, required List<QuizRoundQuestion> questions})
    : questions = List.unmodifiable(questions),
      _solved = List<bool>.filled(questions.length, false),
      _wrong = List.generate(questions.length, (_) => <int>[]);

  /// The title id of a single-title round, or null for a mixed round.
  final String? titleId;

  /// Questions in presented order.
  final List<QuizRoundQuestion> questions;

  final List<bool> _solved;
  final List<List<int>> _wrong;
  int _index = 0;

  bool get isMixed => titleId == null;

  /// The question on screen.
  int get index => _index;

  QuizRoundQuestion get current => questions[_index];

  /// Whether question [i] has been answered rightly.
  bool isSolved(int i) => _solved[i];

  /// The wrong options tried on question [i], in tap order. A question is
  /// only ever solved by its right option, so these are never the answer.
  List<int> wrongTriesAt(int i) => List.unmodifiable(_wrong[i]);

  /// Records [option] for [current] and returns whether it is the right one.
  ///
  /// A wrong option does not end the question: the child may try another, so
  /// a wrong answer costs a go rather than the question (§1). A tried option
  /// is refused because the screen locks it, and a second tap would only be
  /// a bug.
  bool answer(int option) {
    RangeError.checkValueInInterval(
      option,
      0,
      current.options.length - 1,
      'option',
    );
    if (_solved[_index]) {
      throw StateError('Question $_index is already solved');
    }
    if (_wrong[_index].contains(option)) {
      throw StateError('Option $option was already tried on question $_index');
    }
    if (option == current.answerIndex) {
      _solved[_index] = true;
      return true;
    }
    _wrong[_index].add(option);
    return false;
  }

  /// Moves to the next question, which needs the current one solved: with
  /// retries, "answered" no longer means "done".
  void advance() {
    if (!_solved[_index]) {
      throw StateError('Question $_index is not solved');
    }
    if (_index == questions.length - 1) {
      throw StateError('Question $_index is the last');
    }
    _index++;
  }

  /// Questions solved, however many tries they took.
  int get solvedCount => _solved.where((s) => s).length;

  /// Questions solved with no wrong try: the score stays a measure of what
  /// the child knew, not of how long they kept guessing.
  int get score {
    var right = 0;
    for (var i = 0; i < questions.length; i++) {
      if (_solved[i] && _wrong[i].isEmpty) right++;
    }
    return right;
  }

  bool get isComplete => solvedCount == questions.length;

  /// [current] with this round's effect applied: what is written when the
  /// round ends and when it is quit (§4.7).
  ///
  /// Applied to the profile's current progress rather than a copy taken when
  /// the round began, so a shelf tick made meanwhile is not overwritten;
  /// `known` is never touched.
  ///
  /// A title's cursor takes the snapshot of its solved question with the
  /// greatest *draw* index. The level sort means solved questions need not
  /// be a prefix of the draws; an unsolved question drawn earlier is passed
  /// over for this cycle, which is better than asking a solved one first
  /// next time. A question with only wrong tries counts as unsolved, so it is
  /// asked again.
  QuizProgress applyTo(QuizProgress current) {
    final latest = <String, QuizRoundQuestion>{};
    for (var i = 0; i < questions.length; i++) {
      if (!_solved[i]) continue;
      final q = questions[i];
      final held = latest[q.titleId];
      if (held == null || q.drawIndex > held.drawIndex) latest[q.titleId] = q;
    }
    if (latest.isEmpty) return current;

    final titles = Map<String, QuizTitleProgress>.of(current.titles);
    for (final entry in latest.entries) {
      final old = current.titles[entry.key];
      titles[entry.key] = QuizTitleProgress(
        seed: entry.value.seedAfter,
        next: entry.value.nextAfter,
        pool: entry.value.poolAfter,
        rounds: old?.rounds ?? 0,
        best: old?.best ?? 0,
      );
    }

    var mixed = current.mixed;
    if (isComplete) {
      final s = score;
      final id = titleId;
      if (id == null) {
        mixed = QuizMixedProgress(
          rounds: mixed.rounds + 1,
          best: s > mixed.best ? s : mixed.best,
        );
      } else {
        final e = titles[id]!;
        titles[id] = QuizTitleProgress(
          seed: e.seed,
          next: e.next,
          pool: e.pool,
          rounds: e.rounds + 1,
          best: s > e.best ? s : e.best,
        );
      }
    }
    return QuizProgress(
      known: current.known,
      titles: Map.unmodifiable(titles),
      mixed: mixed,
    );
  }
}
