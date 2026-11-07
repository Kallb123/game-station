// Tests of the round as a play session and of `applyTo`, which decides what a
// finished or quit round writes to the save (`PLAN-phase-10-quiz.md` §4.7).

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/game_rng.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/model/quiz_picker.dart';
import 'package:zibo_games/features/quiz/model/quiz_round.dart';

import 'quiz_fixtures.dart';

QuizPicker _picker(QuizTitle title) => QuizPicker(
  QuizCatalog(
    series: [
      fixtureSeries('t', [title]),
    ],
  ),
);

/// Solves the first [count] questions, each with a wrong try first unless
/// [firstGo], and advances between them.
void _answer(QuizRound r, int count, {bool firstGo = true}) {
  for (var i = 0; i < count; i++) {
    final a = r.current.answerIndex;
    if (!firstGo) r.answer((a + 1) % 3);
    r.answer(a);
    if (i < r.questions.length - 1 && i < count - 1) r.advance();
  }
}

void main() {
  group('QuizRound', () {
    late QuizRound round;
    setUp(() {
      round = _picker(
        fixtureTitle('t.a', 24),
      ).singleTitleRound('t.a', const QuizProgress(), GameRng(1))!;
    });

    test('is ten questions of three options, unmodifiable', () {
      expect(round.questions, hasLength(10));
      expect(
        () => round.questions.add(round.questions.first),
        throwsA(anything),
      );
      expect(() => round.current.options.add('x'), throwsA(anything));
      expect(round.index, 0);
      expect(round.isSolved(0), isFalse);
      expect(round.wrongTriesAt(0), isEmpty);
    });

    test('answer reports right or wrong and updates score', () {
      expect(round.answer(round.current.answerIndex), isTrue);
      expect(round.score, 1);
      expect(round.isSolved(0), isTrue);
      round.advance();
      expect(round.answer((round.current.answerIndex + 1) % 3), isFalse);
      expect(round.score, 1);
      expect(round.solvedCount, 1);
      expect(round.isSolved(1), isFalse);
    });

    test('a wrong answer can be followed by another', () {
      final a = round.current.answerIndex;
      final w1 = (a + 1) % 3;
      final w2 = (a + 2) % 3;
      expect(round.answer(w1), isFalse);
      expect(round.answer(w2), isFalse);
      expect(round.wrongTriesAt(0), [w1, w2]);
      expect(round.isSolved(0), isFalse);
      expect(round.answer(a), isTrue);
      expect(round.isSolved(0), isTrue);
      expect(round.wrongTriesAt(0), [w1, w2]);
      expect(() => round.wrongTriesAt(0).add(0), throwsA(anything));
    });

    test('repeating a wrong option throws', () {
      final w = (round.current.answerIndex + 1) % 3;
      round.answer(w);
      expect(() => round.answer(w), throwsStateError);
      expect(round.wrongTriesAt(0), [w]);
    });

    test('answering after solving, or out of range, throws', () {
      expect(() => round.answer(3), throwsRangeError);
      expect(() => round.answer(-1), throwsRangeError);
      round.answer(round.current.answerIndex);
      expect(() => round.answer(0), throwsStateError);
      expect(() => round.answer(round.current.answerIndex), throwsStateError);
    });

    test('score counts only questions solved on the first go', () {
      _answer(round, 1);
      round.advance();
      _answer(round, 1, firstGo: false);
      expect(round.solvedCount, 2);
      expect(round.score, 1);
    });

    test('advance needs a solved question and a next question', () {
      expect(round.advance, throwsStateError);
      round.answer((round.current.answerIndex + 1) % 3);
      expect(round.advance, throwsStateError);
      round.answer(round.current.answerIndex);
      round.advance();
      expect(round.index, 1);
      round = _picker(
        fixtureTitle('t.a', 24),
      ).singleTitleRound('t.a', const QuizProgress(), GameRng(1))!;
      _answer(round, 10);
      expect(round.index, 9);
      expect(round.advance, throwsStateError);
    });

    test('is complete after ten solved, not before', () {
      _answer(round, 9);
      expect(round.isComplete, isFalse);
      round.advance();
      round.answer((round.current.answerIndex + 1) % 3);
      expect(round.isComplete, isFalse);
      round.answer(round.current.answerIndex);
      expect(round.isComplete, isTrue);
    });
  });

  group('applyTo', () {
    final title = fixtureTitle('t.a', 24);
    final picker = _picker(title);

    QuizRound single(QuizProgress p, [int seed = 1]) =>
        picker.singleTitleRound('t.a', p, GameRng(seed))!;

    test('a complete single-title round bumps rounds and keeps the best', () {
      const before = QuizProgress(
        titles: {
          't.a': QuizTitleProgress(
            seed: 7,
            next: 0,
            pool: 24,
            rounds: 2,
            best: 9,
          ),
        },
      );
      final r = single(before);
      _answer(r, 10, firstGo: false);
      final low = r.applyTo(before).titles['t.a']!;
      expect((low.rounds, low.best, low.next), (3, 9, 10));

      final r2 = single(before);
      _answer(r2, 10);
      expect(r2.applyTo(before).titles['t.a']!.best, 10);
      expect(r2.applyTo(before).mixed, before.mixed);
    });

    test('a complete mixed round bumps mixed only', () {
      final p = QuizProgress(
        known: const {'t.a'},
        mixed: const QuizMixedProgress(rounds: 1, best: 4),
      );
      final r = picker.mixedRound(p, GameRng(1))!;
      _answer(r, 10);
      final after = r.applyTo(p);
      expect(after.mixed, const QuizMixedProgress(rounds: 2, best: 10));
      final e = after.titles['t.a']!;
      expect((e.rounds, e.best, e.next, e.pool), (0, 0, 10, 24));
    });

    test('a quit after one answer advances that title and no counter', () {
      final r = single(const QuizProgress());
      _answer(r, 1);
      final first = r.current.question.id;
      final after = r.applyTo(const QuizProgress());
      final e = after.titles['t.a']!;
      expect((e.rounds, e.best), (0, 0));
      expect(after.mixed, const QuizMixedProgress());
      final next = single(after, 2);
      expect(next.questions.map((q) => q.question.id), isNot(contains(first)));
      expect(titleOrder(title, e.seed)[e.next - 1].id, first);
    });

    test(
      'a quit with wrong tries on the current question keeps the cursor',
      () {
        final r = single(const QuizProgress());
        _answer(r, 3);
        final third = r.current;
        r.advance();
        r.answer((r.current.answerIndex + 1) % 3);
        final e = r.applyTo(const QuizProgress()).titles['t.a']!;
        expect(
          (e.seed, e.next, e.pool),
          (third.seedAfter, third.nextAfter, third.poolAfter),
        );

        // Wrong tries alone leave the save as it was.
        final only = single(const QuizProgress());
        only.answer((only.current.answerIndex + 1) % 3);
        expect(only.applyTo(const QuizProgress()), const QuizProgress());
      },
    );

    test('nothing answered returns progress equal to the input', () {
      const p = QuizProgress(
        known: {'t.a'},
        titles: {'t.a': QuizTitleProgress(seed: 1, next: 2, pool: 24)},
      );
      expect(single(p).applyTo(p), p);
    });

    test('known and unrelated titles are untouched, input not mutated', () {
      final p = QuizProgress(
        known: const {'t.a', 'later.build'},
        titles: {
          'x.y': const QuizTitleProgress(
            seed: 4,
            next: 1,
            pool: 12,
            rounds: 5,
            best: 6,
          ),
        },
      );
      final r = single(p);
      _answer(r, 10);
      final after = r.applyTo(p);
      expect(after.known, p.known);
      expect(after.titles['x.y'], p.titles['x.y']);
      expect(p.titles.keys, ['x.y']);
      expect(after.titles.containsKey('t.a'), isTrue);
    });

    test('uses the greatest draw index, not the last answered', () {
      // Level 2 on odd ids: the level sort puts level 1 first, so an answered
      // prefix of the presented order need not hold the latest draws. Find a
      // round and a prefix whose latest-drawn question is not its last.
      final p = _picker(
        fixtureTitle('t.a', 24, levelOf: (n) => n.isOdd ? 2 : 1),
      );
      for (var seed = 0; seed < 200; seed++) {
        final probe = p.singleTitleRound(
          't.a',
          const QuizProgress(),
          GameRng(seed),
        )!;
        for (var k = 2; k <= 10; k++) {
          final prefix = probe.questions.sublist(0, k);
          final top = prefix.reduce(
            (a, b) => a.drawIndex > b.drawIndex ? a : b,
          );
          final last = prefix.last;
          if (top == last) continue;

          final r = p.singleTitleRound(
            't.a',
            const QuizProgress(),
            GameRng(seed),
          )!;
          _answer(r, k);
          final e = r.applyTo(const QuizProgress()).titles['t.a']!;
          expect(
            (e.seed, e.next, e.pool),
            (top.seedAfter, top.nextAfter, top.poolAfter),
          );
          expect(e.next, isNot(last.nextAfter));
          return;
        }
      }
      fail('no seed produced a prefix whose latest draw is not its last');
    });
  });
}
