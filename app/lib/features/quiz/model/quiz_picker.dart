// Builds a round: which questions, in what order, with which options
// (`PLAN-phase-10-quiz.md` §4.6).
//
// All randomness comes from the `GameRng` the caller passes, and is consumed
// in a fixed order (see [QuizPicker.mixedRound]), so a seeded test replays.

import '../../../core/game_rng.dart';
import '../../../core/storage/save_data.dart';
import 'quiz_catalog.dart';
import 'quiz_round.dart';

/// Fisher–Yates, the one shuffle every choice in this feature goes through so
/// the rng is consumed the same way everywhere.
void _shuffle<T>(List<T> items, GameRng rng) {
  for (var i = items.length - 1; i > 0; i--) {
    final j = rng.nextInt(i + 1);
    final held = items[i];
    items[i] = items[j];
    items[j] = held;
  }
}

/// [title]'s questions in the order seed [seed] gives: sorted by id first, so
/// the order does not depend on how the pack file happens to list them.
List<QuizQuestion> titleOrder(QuizTitle title, int seed) {
  final order = [...title.questions]..sort((a, b) => a.id.compareTo(b.id));
  _shuffle(order, GameRng(seed));
  return order;
}

/// A title's place in its order during one round: the stored `seed`, `next`
/// and `pool` (§4.6, §4.7), advanced as questions are drawn.
class QuizTitleCursor {
  /// Starts from [stored], or from a fresh seed taken from [rng] if the title
  /// has no entry. A [stored] pool that differs from the loaded question count
  /// keeps its seed and restarts at 0: questions were added, checked or
  /// withdrawn.
  QuizTitleCursor(this.title, QuizTitleProgress? stored, GameRng rng)
    : pool = title.questions.length,
      seed = stored?.seed ?? rng.nextUint32(),
      next = stored != null && stored.pool == title.questions.length
          ? stored.next
          : 0 {
    _order = titleOrder(title, seed);
  }

  final QuizTitle title;
  int seed;
  int next;
  final int pool;
  late List<QuizQuestion> _order;

  /// The next question not in [askedThisRound].
  ///
  /// A round can run off the end of an order part way through (a mixed round
  /// left `next` at 20 of 24, then a single-title round starts), and the fresh
  /// shuffle can put a question already asked this round near its front.
  /// Passing over it keeps a round free of repeats; it costs that question one
  /// turn in the new order, which it has just had (§4.6). It terminates
  /// because a title holds at least [minQuestionsPerTitle] questions, no fewer
  /// than [quizRoundLength], and fewer than that are asked before any draw;
  /// `quiz_picker_test.dart` fails if the two constants stop agreeing.
  QuizQuestion draw(GameRng rng, Set<String> askedThisRound) {
    while (true) {
      if (next >= pool) {
        seed = rng.nextUint32();
        next = 0;
        _order = titleOrder(title, seed);
      }
      final q = _order[next++];
      if (!askedThisRound.contains(q.id)) return q;
    }
  }
}

/// Builds [QuizRound]s over a catalog.
class QuizPicker {
  QuizPicker(this.catalog);

  final QuizCatalog catalog;

  /// Ten questions from [titleId]'s order, or null if the title is not offered.
  /// Ticking is not required: a child may pick a book from the shelf.
  QuizRound? singleTitleRound(
    String titleId,
    QuizProgress progress,
    GameRng rng,
  ) {
    QuizTitle? title;
    for (final t in catalog.offeredTitles) {
      if (t.id == titleId) title = t;
    }
    if (title == null) return null;
    return _build(titleId, progress, rng, [
      for (var i = 0; i < quizRoundLength; i++) title,
    ]);
  }

  /// Ten questions across the ticked, offered titles, or null if there are
  /// none.
  ///
  /// The rng is consumed in this order, so a seeded test is reproducible: the
  /// series shuffle, then each series' title shuffle in that shuffled order,
  /// then the ten draws in draw order (fresh seeds and reseeds as they come
  /// up), then, after the level sort, the options of each question in
  /// presented order.
  QuizRound? mixedRound(QuizProgress progress, GameRng rng) {
    final offered = {for (final t in catalog.offeredTitles) t.id};
    // Lists, not the `known` set, so the order never depends on set iteration.
    final groups = <List<QuizTitle>>[];
    for (final s in catalog.series) {
      final titles = [
        for (final t in s.titles)
          if (offered.contains(t.id) && progress.known.contains(t.id)) t,
      ];
      if (titles.isNotEmpty) groups.add(titles);
    }
    if (groups.isEmpty) return null;

    _shuffle(groups, rng);
    for (final g in groups) {
      _shuffle(g, rng);
    }
    // Rotating by series first stops four ticked Dahl books and one Narnia
    // book giving four Dahl questions in five; rotating titles within a
    // series spreads a series' share over its books (§4.6).
    final taken = List<int>.filled(groups.length, 0);
    final plan = <QuizTitle>[];
    for (var i = 0; i < quizRoundLength; i++) {
      final s = i % groups.length;
      plan.add(groups[s][taken[s]++ % groups[s].length]);
    }
    return _build(null, progress, rng, plan);
  }

  QuizRound _build(
    String? roundTitleId,
    QuizProgress progress,
    GameRng rng,
    List<QuizTitle> plan,
  ) {
    final cursors = <String, QuizTitleCursor>{};
    final asked = <String>{};
    final drawn = <_Drawn>[];
    for (var i = 0; i < plan.length; i++) {
      final title = plan[i];
      final cursor = cursors[title.id] ??= QuizTitleCursor(
        title,
        progress.titles[title.id],
        rng,
      );
      final q = cursor.draw(rng, asked);
      asked.add(q.id);
      drawn.add(_Drawn(q, title.id, i, cursor.seed, cursor.next, cursor.pool));
    }

    // Dart's `List.sort` is not guaranteed stable, so draw index breaks ties.
    drawn.sort((a, b) {
      final byLevel = a.question.level.compareTo(b.question.level);
      return byLevel != 0 ? byLevel : a.drawIndex.compareTo(b.drawIndex);
    });

    return QuizRound(
      titleId: roundTitleId,
      questions: [for (final d in drawn) _present(d, rng)],
    );
  }

  /// The right answer and two of the three wrong ones, shuffled. The right
  /// answer is tracked by index, so a wrong answer that happens to equal it
  /// as text could not be mistaken for it.
  QuizRoundQuestion _present(_Drawn d, GameRng rng) {
    final q = d.question;
    final dropped = rng.nextInt(wrongAnswerCount);
    final texts = [q.a, ...q.wrong];
    final picks = [
      0,
      for (var w = 0; w < wrongAnswerCount; w++)
        if (w != dropped) w + 1,
    ];
    _shuffle(picks, rng);
    return QuizRoundQuestion(
      question: q,
      titleId: d.titleId,
      options: [for (final p in picks) texts[p]],
      answerIndex: picks.indexOf(0),
      drawIndex: d.drawIndex,
      seedAfter: d.seed,
      nextAfter: d.next,
      poolAfter: d.pool,
    );
  }
}

class _Drawn {
  _Drawn(
    this.question,
    this.titleId,
    this.drawIndex,
    this.seed,
    this.next,
    this.pool,
  );

  final QuizQuestion question;
  final String titleId;
  final int drawIndex;
  final int seed;
  final int next;
  final int pool;
}
