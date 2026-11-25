// The Maths generator (`PLAN-quiz-maths.md` §4.2).
//
// The quiz's first rule is that a wrong "right answer" never reaches a child.
// A bank question meets it by a person's check; a generated one meets it by
// construction, and this file is the check. It re-parses each question's
// *text* and recomputes the answer itself, so a bug in the generator's
// arithmetic, or a question worded differently from the numbers it was built
// from, fails here rather than being agreed with.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/game_rng.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/quiz/model/maths_generator.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/model/quiz_round.dart';

const int _seeds = 400;

final RegExp _shape = RegExp(r'^What is (\d+) ([+−×÷]) (\d+)\?$');

/// What a question asks, read back from its words alone.
({QuizMathsOp op, int left, int right}) _parse(String text) {
  final m = _shape.firstMatch(text);
  expect(m, isNotNull, reason: 'unexpected question wording: "$text"');
  final op = switch (m!.group(2)) {
    '+' => QuizMathsOp.add,
    '−' => QuizMathsOp.subtract,
    '×' => QuizMathsOp.multiply,
    _ => QuizMathsOp.divide,
  };
  return (op: op, left: int.parse(m.group(1)!), right: int.parse(m.group(3)!));
}

/// Checks every rule of `PLAN-quiz-maths.md` §1 and §4.2 on one round.
void _checkRound(QuizRound round, QuizMathsProgress settings) {
  expect(round.isMaths, isTrue);
  expect(round.isMixed, isFalse);
  expect(round.questions, hasLength(quizRoundLength));
  final facts = <String>{};
  for (final rq in round.questions) {
    final q = rq.question;
    final text = q.q;
    final (:op, :left, :right) = _parse(text);
    expect(settings.ops, contains(op), reason: text);

    final int expected;
    switch (op) {
      case QuizMathsOp.add:
        expect(left, greaterThanOrEqualTo(1), reason: text);
        expect(right, greaterThanOrEqualTo(1), reason: text);
        expect(left + right, lessThanOrEqualTo(settings.upTo), reason: text);
        expected = left + right;
      case QuizMathsOp.subtract:
        expect(left, lessThanOrEqualTo(settings.upTo), reason: text);
        expect(right, inInclusiveRange(1, left), reason: text);
        expected = left - right;
      case QuizMathsOp.multiply:
        expect(left, inInclusiveRange(1, 12), reason: text);
        expect(right, inInclusiveRange(1, 12), reason: text);
        expect(
          settings.tables.contains(left) || settings.tables.contains(right),
          isTrue,
          reason: '$text uses no chosen table',
        );
        expected = left * right;
      case QuizMathsOp.divide:
        expect(settings.tables, contains(right), reason: text);
        expect(left % right, 0, reason: '$text is not exact');
        expect(left ~/ right, inInclusiveRange(1, 12), reason: text);
        expected = left ~/ right;
    }
    expect(expected, greaterThanOrEqualTo(0), reason: text);
    expect(q.a, '$expected', reason: text);

    // The same fact in either order is one fact.
    final key = op == QuizMathsOp.multiply
        ? '${op.name} ${left < right ? left : right} '
              '${left < right ? right : left}'
        : '${op.name} $left $right';
    expect(facts.add(key), isTrue, reason: 'repeated in a round: $text');

    expect(q.wrong, hasLength(wrongAnswerCount), reason: text);
    final wrong = [for (final w in q.wrong) int.parse(w)];
    expect(wrong.toSet(), hasLength(wrongAnswerCount), reason: text);
    expect(wrong, isNot(contains(expected)), reason: text);
    expect(wrong.every((w) => w >= 0), isTrue, reason: '$text: $wrong');

    expect(q.checked, isTrue);
    expect(text.length, lessThanOrEqualTo(maxQuestionLength));
    for (final answer in [q.a, ...q.wrong]) {
      expect(answer.length, lessThanOrEqualTo(maxAnswerLength));
    }

    // Presented: the answer and two distinct wrong ones.
    expect(rq.options, hasLength(3));
    expect(rq.options.toSet(), hasLength(3), reason: text);
    expect(rq.options[rq.answerIndex], q.a);
  }
}

void _sweep(QuizMathsProgress settings) {
  for (var seed = 0; seed < _seeds; seed++) {
    _checkRound(mathsRound(settings, GameRng(seed))!, settings);
  }
}

void main() {
  group('every answer is right and every wrong answer wrong', () {
    for (final op in QuizMathsOp.values) {
      if (op == QuizMathsOp.add || op == QuizMathsOp.subtract) {
        for (final upTo in quizMathsUpToChoices) {
          test('${op.name} up to $upTo', () {
            _sweep(QuizMathsProgress(ops: {op}, upTo: upTo));
          });
        }
      } else {
        // One table at a time: the smallest pools, so the no-repeat rule is
        // tested where it is tightest.
        test('${op.name}, each table alone', () {
          for (var t = 1; t <= quizMathsMaxTable; t++) {
            _sweep(QuizMathsProgress(ops: {op}, tables: {t}));
          }
        });
      }
    }

    test('everything at once', () {
      _sweep(
        QuizMathsProgress(
          ops: QuizMathsOp.values.toSet(),
          tables: {for (var t = 1; t <= 12; t++) t},
          upTo: 100,
        ),
      );
    });
  });

  test('every playable setting has more facts per operation than a round '
      'takes', () {
    for (final op in QuizMathsOp.values) {
      for (final upTo in quizMathsUpToChoices) {
        for (var t = 1; t <= quizMathsMaxTable; t++) {
          final facts = mathsFacts(
            op,
            QuizMathsProgress(ops: {op}, tables: {t}, upTo: upTo),
          );
          expect(
            facts.length,
            greaterThan(quizRoundLength),
            reason: '${op.name}, table $t, up to $upTo',
          );
        }
      }
    }
  });

  test('operations take turns, so each is asked two or three times', () {
    const settings = QuizMathsProgress(
      ops: {
        QuizMathsOp.add,
        QuizMathsOp.subtract,
        QuizMathsOp.multiply,
        QuizMathsOp.divide,
      },
      tables: {7},
      upTo: 100,
    );
    for (var seed = 0; seed < 50; seed++) {
      final round = mathsRound(settings, GameRng(seed))!;
      final counts = <QuizMathsOp, int>{};
      for (final q in round.questions) {
        final op = _parse(q.question.q).op;
        counts[op] = (counts[op] ?? 0) + 1;
      }
      expect(counts.keys.toSet(), settings.ops);
      expect(counts.values.every((c) => c == 2 || c == 3), isTrue);
    }
  });

  test('multiplying asks both orders of a fact over many rounds', () {
    const settings = QuizMathsProgress(
      ops: {QuizMathsOp.multiply},
      tables: {3},
    );
    final seen = <String>{};
    for (var seed = 0; seed < 50; seed++) {
      for (final q in mathsRound(settings, GameRng(seed))!.questions) {
        seen.add(q.question.q);
      }
    }
    expect(seen, contains('What is 3 × 7?'));
    expect(seen, contains('What is 7 × 3?'));
  });

  test('a seeded round is the same round twice', () {
    const settings = QuizMathsProgress(
      ops: {QuizMathsOp.add, QuizMathsOp.multiply},
      tables: {2, 5},
      upTo: 20,
    );
    List<String> shown(QuizRound r) => [
      for (final q in r.questions) '${q.question.q} ${q.options.join('/')}',
    ];
    expect(
      shown(mathsRound(settings, GameRng(42))!),
      shown(mathsRound(settings, GameRng(42))!),
    );
    expect(
      shown(mathsRound(settings, GameRng(42))!),
      isNot(shown(mathsRound(settings, GameRng(43))!)),
    );
  });

  group('an unplayable setting makes no round', () {
    test('with no operation', () {
      expect(mathsRound(const QuizMathsProgress(ops: {}), GameRng(1)), isNull);
    });

    test('with times tables or dividing on and no table chosen', () {
      for (final op in [QuizMathsOp.multiply, QuizMathsOp.divide]) {
        final settings = QuizMathsProgress(
          ops: {QuizMathsOp.add, op},
          tables: const {},
        );
        expect(settings.isPlayable, isFalse);
        expect(mathsRound(settings, GameRng(1)), isNull);
      }
    });

    test('adding alone needs no table', () {
      const settings = QuizMathsProgress(ops: {QuizMathsOp.add}, tables: {});
      expect(settings.isPlayable, isTrue);
      expect(mathsRound(settings, GameRng(1)), isNotNull);
    });
  });

  group('applyTo', () {
    QuizRound finished() {
      final round = mathsRound(const QuizMathsProgress(), GameRng(5))!;
      for (var i = 0; i < round.questions.length; i++) {
        // A wrong try on the first two, so the score is 8.
        if (i < 2) round.answer((round.current.answerIndex + 1) % 3);
        round.answer(round.current.answerIndex);
        if (i < round.questions.length - 1) round.advance();
      }
      return round;
    }

    const before = QuizProgress(
      known: {'a.b'},
      titles: {'a.b': QuizTitleProgress(seed: 1, next: 2, pool: 12)},
      mixed: QuizMixedProgress(rounds: 4, best: 6),
      maths: QuizMathsProgress(ops: {QuizMathsOp.add}, rounds: 2, best: 5),
    );

    test('a finished round counts and raises the best, and nothing else '
        'changes', () {
      final after = finished().applyTo(before);
      expect(
        after,
        before.copyWith(maths: before.maths.copyWith(rounds: 3, best: 8)),
      );
    });

    test('a lower score keeps the best', () {
      final high = before.copyWith(maths: before.maths.copyWith(best: 10));
      expect(finished().applyTo(high).maths.best, 10);
    });

    test('a quit round writes nothing', () {
      final round = mathsRound(const QuizMathsProgress(), GameRng(5))!;
      round.answer(round.current.answerIndex);
      expect(round.applyTo(before), same(before));
    });
  });
}
