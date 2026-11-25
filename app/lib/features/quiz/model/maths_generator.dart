// Generated arithmetic questions for the quiz's Maths topic
// (`PLAN-quiz-maths.md` §4.2).
//
// Pure Dart like the rest of `model/`. Nothing here is stored: a round is made
// fresh from the profile's settings each time, so the generator can change in
// any release without a save migration. Every answer is right by
// construction, and `maths_generator_test.dart` re-parses the question text to
// check it rather than trusting the numbers below.

import '../../../core/game_rng.dart';
import '../../../core/storage/save_data.dart';
import 'quiz_catalog.dart';
import 'quiz_picker.dart';
import 'quiz_round.dart';

/// The symbols a question is written with: the true minus, times and
/// division signs, which screen readers read as words.
const Map<QuizMathsOp, String> quizMathsSymbols = {
  QuizMathsOp.add: '+',
  QuizMathsOp.subtract: '−',
  QuizMathsOp.multiply: '×',
  QuizMathsOp.divide: '÷',
};

/// The largest multiplier in a times table: 12, as the tables go to 12 × 12.
const int quizMathsMaxMultiplier = 12;

/// One arithmetic fact: `a op b`.
class MathsFact {
  const MathsFact(this.op, this.a, this.b);

  final QuizMathsOp op;
  final int a;
  final int b;

  int get answer => switch (op) {
    QuizMathsOp.add => a + b,
    QuizMathsOp.subtract => a - b,
    QuizMathsOp.multiply => a * b,
    QuizMathsOp.divide => a ~/ b,
  };
}

/// Every fact [op] can ask about under [settings], in a fixed order.
///
/// Whole numbers only (§1): taking away never goes below zero, and dividing
/// is built as `(t × k) ÷ t` so it is always exact. Multiplying facts are
/// unordered pairs, stored smaller first, so that with the 3 and 4 tables both
/// chosen `3 × 4` and `4 × 3` are one fact and a round cannot ask it twice.
List<MathsFact> mathsFacts(QuizMathsOp op, QuizMathsProgress settings) {
  final n = settings.upTo;
  final tables = settings.tables.toList()..sort();
  return switch (op) {
    QuizMathsOp.add => [
      for (var a = 1; a < n; a++)
        for (var b = 1; a + b <= n; b++) MathsFact(op, a, b),
    ],
    QuizMathsOp.subtract => [
      for (var a = 1; a <= n; a++)
        for (var b = 1; b <= a; b++) MathsFact(op, a, b),
    ],
    QuizMathsOp.multiply => [
      for (var a = 1; a <= quizMathsMaxMultiplier; a++)
        for (var b = a; b <= quizMathsMaxMultiplier; b++)
          if (tables.contains(a) || tables.contains(b)) MathsFact(op, a, b),
    ],
    QuizMathsOp.divide => [
      for (final t in tables)
        for (var k = 1; k <= quizMathsMaxMultiplier; k++)
          MathsFact(op, t * k, t),
    ],
  };
}

/// A round of [quizRoundLength] generated questions, or null when [settings]
/// is not playable.
///
/// The chosen operations are shuffled and taken in turn, so a round over
/// four asks each two or three times however many facts each has; adding up
/// to 100 would otherwise crowd out a single times table. Facts are drawn
/// without replacement by a partial Fisher–Yates, a fixed number of steps
/// rather than a retry loop (§3).
///
/// The rng is consumed in this order, so a seeded test pins a round: the
/// operation shuffle; then per question the fact draw, the operand order for
/// multiplying, and the wrong-answer shuffle; then the options of each
/// question in order.
QuizRound? mathsRound(QuizMathsProgress settings, GameRng rng) {
  if (!settings.isPlayable) return null;
  final ops = [
    for (final op in QuizMathsOp.values)
      if (settings.ops.contains(op)) op,
  ];
  quizShuffle(ops, rng);

  final facts = {for (final op in ops) op: mathsFacts(op, settings)};
  final drawnFrom = {for (final op in ops) op: 0};
  final questions = <QuizQuestion>[];
  for (var i = 0; i < quizRoundLength; i++) {
    final op = ops[i % ops.length];
    final pool = facts[op]!;
    // Every playable setting has at least 12 facts per operation, more than
    // the 10 one round can take from it, so the pool never runs out.
    final taken = drawnFrom[op]!;
    final j = taken + rng.nextInt(pool.length - taken);
    final fact = pool[j];
    pool[j] = pool[taken];
    pool[taken] = fact;
    drawnFrom[op] = taken + 1;

    questions.add(_question(fact, rng, settings));
  }

  return QuizRound.maths(
    questions: [
      for (var i = 0; i < questions.length; i++) _present(questions[i], i, rng),
    ],
  );
}

QuizRoundQuestion _present(QuizQuestion q, int index, GameRng rng) {
  final (options, answerIndex) = presentOptions(q, rng);
  return QuizRoundQuestion(
    question: q,
    titleId: mathsRoundTitleId,
    options: options,
    answerIndex: answerIndex,
    drawIndex: index,
    // Never read: a Maths round has no title order (`QuizRound.applyTo`).
    seedAfter: 0,
    nextAfter: 0,
    poolAfter: 0,
  );
}

/// What a Maths question gives as its title, for code that groups by title.
/// Not a bank title id and never stored.
const String mathsRoundTitleId = 'maths';

QuizQuestion _question(MathsFact fact, GameRng rng, QuizMathsProgress s) {
  var (left, right) = (fact.a, fact.b);
  // A times fact is stored smaller first; either order is the same fact, and
  // a child should meet both.
  if (fact.op == QuizMathsOp.multiply && left != right && rng.nextInt(2) == 1) {
    (left, right) = (right, left);
  }
  final answer = fact.answer;
  return QuizQuestion(
    id: 'maths.${fact.op.name}.$left.$right',
    level: 1,
    // Right by construction (§1); the generator test is the check.
    checked: true,
    q: 'What is $left ${quizMathsSymbols[fact.op]} $right?',
    a: '$answer',
    wrong: [for (final w in _wrongAnswers(fact, rng, s)) '$w'],
    source: 'generated',
  );
}

/// Three near misses: distinct, not negative and not the answer (§4.2).
List<int> _wrongAnswers(MathsFact fact, GameRng rng, QuizMathsProgress s) {
  final answer = fact.answer;
  final candidates = switch (fact.op) {
    QuizMathsOp.add || QuizMathsOp.subtract => [
      answer - 2,
      answer - 1,
      answer + 1,
      answer + 2,
      if (s.upTo >= 100) ...[answer - 10, answer + 10],
      // The commonest slip: doing the other one.
      if (fact.op == QuizMathsOp.add) fact.a - fact.b else fact.a + fact.b,
    ],
    QuizMathsOp.multiply => [
      answer - fact.a,
      answer + fact.a,
      answer - fact.b,
      answer + fact.b,
      fact.a + fact.b,
    ],
    QuizMathsOp.divide => [
      answer - 2,
      answer - 1,
      answer + 1,
      answer + 2,
      fact.b,
    ],
  };
  final kept = <int>[];
  for (final c in candidates) {
    if (c >= 0 && c != answer && !kept.contains(c)) kept.add(c);
  }
  quizShuffle(kept, rng);
  final wrong = kept.take(wrongAnswerCount).toList();
  // Only a tiny answer can leave fewer than three; the next numbers up fill
  // in, deterministically.
  for (var c = answer + 1; wrong.length < wrongAnswerCount; c++) {
    if (!wrong.contains(c)) wrong.add(c);
  }
  return wrong;
}
