// One round of the quiz as a play session: ten questions already drawn,
// ordered and given their options, plus the answers a child has chosen so far
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
  /// answered (§4.7).
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
      _chosen = List<int?>.filled(questions.length, null);

  /// The title id of a single-title round, or null for a mixed round.
  final String? titleId;

  /// Questions in presented order.
  final List<QuizRoundQuestion> questions;

  final List<int?> _chosen;
  int _index = 0;

  bool get isMixed => titleId == null;

  /// The question on screen.
  int get index => _index;

  QuizRoundQuestion get current => questions[_index];

  /// The option chosen for question [i], or null if it is unanswered.
  int? chosenAt(int i) => _chosen[i];

  /// Records [option] for [current] and returns whether it is the right one.
  bool answer(int option) {
    RangeError.checkValueInInterval(
      option,
      0,
      current.options.length - 1,
      'option',
    );
    if (_chosen[_index] != null) {
      throw StateError('Question $_index is already answered');
    }
    _chosen[_index] = option;
    return option == current.answerIndex;
  }

  /// Moves to the next question.
  void advance() {
    if (_chosen[_index] == null) {
      throw StateError('Question $_index is not answered');
    }
    if (_index == questions.length - 1) {
      throw StateError('Question $_index is the last');
    }
    _index++;
  }

  int get answeredCount => _chosen.where((c) => c != null).length;

  /// Right answers so far.
  int get score {
    var right = 0;
    for (var i = 0; i < questions.length; i++) {
      if (_chosen[i] == questions[i].answerIndex) right++;
    }
    return right;
  }

  bool get isComplete => answeredCount == questions.length;

  /// [current] with this round's effect applied: what is written when the
  /// round ends and when it is quit (§4.7).
  ///
  /// Applied to the profile's current progress rather than a copy taken when
  /// the round began, so a shelf tick made meanwhile is not overwritten;
  /// `known` is never touched.
  ///
  /// A title's cursor takes the snapshot of its answered question with the
  /// greatest *draw* index. The level sort means answered questions need not
  /// be a prefix of the draws; an unanswered question drawn earlier is passed
  /// over for this cycle, which is better than asking an answered one first
  /// next time.
  QuizProgress applyTo(QuizProgress current) {
    final latest = <String, QuizRoundQuestion>{};
    for (var i = 0; i < questions.length; i++) {
      if (_chosen[i] == null) continue;
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
