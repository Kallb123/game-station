// Tests of the picker (`PLAN-phase-10-quiz.md` §4.6, §6 PR 5): what a round
// draws, in what order, and with which options. No widgets, no bundle.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/game_rng.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/model/quiz_picker.dart';
import 'package:zibo_games/features/quiz/model/quiz_round.dart';

import 'quiz_fixtures.dart';

QuizProgress _known(Iterable<String> ids) => QuizProgress(known: ids.toSet());

List<String> _ids(QuizRound r) => [for (final q in r.questions) q.question.id];

QuizProgress _playThrough(QuizRound round, QuizProgress progress) {
  for (var i = 0; i < round.questions.length; i++) {
    round.answer(0);
    if (i < round.questions.length - 1) round.advance();
  }
  return round.applyTo(progress);
}

void main() {
  test('a round is no longer than the smallest offered title', () {
    // `QuizTitleCursor.draw` passes over questions the round has asked; with
    // a round longer than a title, it would pass over every one forever.
    expect(quizRoundLength, lessThanOrEqualTo(minQuestionsPerTitle));
  });

  group('titleOrder', () {
    test('is a permutation, seed-stable, file-order independent', () {
      final title = fixtureTitle('t.a', 24);
      final reversed = QuizTitle(
        id: title.id,
        name: title.name,
        questions: title.questions.reversed.toList(),
      );
      final order = titleOrder(title, 5);
      expect(
        order.map((q) => q.id).toList()..sort(),
        title.questions.map((q) => q.id).toList()..sort(),
      );
      expect(titleOrder(title, 5).map((q) => q.id), order.map((q) => q.id));
      expect(titleOrder(reversed, 5).map((q) => q.id), order.map((q) => q.id));
      final others = [
        for (var s = 6; s < 12; s++) titleOrder(title, s).map((q) => q.id),
      ];
      expect(others.any((o) => !_same(o, order.map((q) => q.id))), isTrue);
    });
  });

  group('one title cycles through every question', () {
    test('the cursor asks all 24 before any repeat, over three cycles', () {
      final title = fixtureTitle('t.a', 24);
      final cursor = QuizTitleCursor(title, null, GameRng(1));
      final rng = GameRng(2);
      final drawn = [for (var i = 0; i < 72; i++) cursor.draw(rng, {}).id];
      for (var block = 0; block < 3; block++) {
        final ids = drawn.sublist(block * 24, block * 24 + 24);
        expect(ids.toSet(), hasLength(24), reason: 'block $block');
      }
    });

    test('back-to-back rounds: the first 24 asks are a permutation and no '
        'order repeats a question', () {
      final picker = QuizPicker(
        QuizCatalog(
          series: [
            fixtureSeries('t', [fixtureTitle('t.a', 24)]),
          ],
        ),
      );
      var progress = const QuizProgress();
      final asks = <String>[];
      // Which order each ask came from: the seed the cursor held when it was
      // drawn. A round that crosses a reseed asks from two orders.
      final bySeed = <int, List<String>>{};
      for (var round = 0; asks.length < 72; round++) {
        final r = picker.singleTitleRound(
          't.a',
          progress,
          GameRng(100 + round),
        )!;
        expect(_ids(r).toSet(), hasLength(10), reason: 'round $round');
        final inDrawOrder = [...r.questions]
          ..sort((a, b) => a.drawIndex.compareTo(b.drawIndex));
        for (final q in inDrawOrder) {
          asks.add(q.question.id);
          bySeed.putIfAbsent(q.seedAfter, () => []).add(q.question.id);
        }
        progress = _playThrough(r, progress);
      }
      expect(asks.take(24).toSet(), hasLength(24));
      expect(bySeed.length, greaterThanOrEqualTo(3));
      bySeed.forEach((seed, ids) {
        expect(ids.toSet(), hasLength(ids.length), reason: 'order $seed');
      });
    });
  });

  group('changed pool', () {
    final title = fixtureTitle('t.a', 24);
    final picker = QuizPicker(
      QuizCatalog(
        series: [
          fixtureSeries('t', [title]),
        ],
      ),
    );

    test('restarts the order under the same seed', () {
      final progress = const QuizProgress(
        titles: {'t.a': QuizTitleProgress(seed: 7, next: 5, pool: 23)},
      );
      final r = picker.singleTitleRound('t.a', progress, GameRng(1))!;
      final expected = titleOrder(title, 7).sublist(0, 10).map((q) => q.id);
      expect(_ids(r), expected);
      final after = _playThrough(r, progress).titles['t.a']!;
      expect((after.seed, after.next, after.pool), (7, 10, 24));
    });

    test('an unchanged pool continues from next', () {
      final progress = const QuizProgress(
        titles: {'t.a': QuizTitleProgress(seed: 7, next: 5, pool: 24)},
      );
      final r = picker.singleTitleRound('t.a', progress, GameRng(1))!;
      expect(_ids(r), titleOrder(title, 7).sublist(5, 15).map((q) => q.id));
    });
  });

  group('a single-title round never repeats within itself', () {
    for (final (pool, next) in [(10, 4), (24, 20), (24, 23), (11, 10)]) {
      test('pool $pool, next $next', () {
        final title = fixtureTitle('t.a', pool);
        final picker = QuizPicker(
          QuizCatalog(
            series: [
              fixtureSeries('t', [title]),
            ],
          ),
        );
        final progress = QuizProgress(
          titles: {'t.a': QuizTitleProgress(seed: 3, next: next, pool: pool)},
        );
        for (var s = 0; s < 200; s++) {
          final r = picker.singleTitleRound('t.a', progress, GameRng(s))!;
          expect(_ids(r).toSet(), hasLength(10), reason: 'rng seed $s');
        }
      });
    }
  });

  group('mixed rounds', () {
    final picker = QuizPicker(fixtureCatalog());
    final all = _known([narniaId, ...dahlIds]);

    test('five Narnia and five Dahl, alternating, Dahl across all books', () {
      for (var s = 0; s < 20; s++) {
        final r = picker.mixedRound(all, GameRng(s))!;
        final series = [for (final q in r.questions) seriesOf(q.titleId)];
        expect(series.where((x) => x == 'narnia'), hasLength(5));
        expect(series.where((x) => x == 'dahl'), hasLength(5));
        for (var i = 0; i < 10; i += 2) {
          expect(series[i], isNot(series[i + 1]), reason: 'seed $s');
        }
        expect({
          for (final q in r.questions)
            if (seriesOf(q.titleId) == 'dahl') q.titleId,
        }, hasLength(4));
        expect(_ids(r).toSet(), hasLength(10));
        expect(r.isMixed, isTrue);
      }
    });

    test('draws only from ticked, offered titles', () {
      final catalog = QuizCatalog(
        series: [
          fixtureSeries('s', [
            fixtureTitle('s.ticked', 12),
            fixtureTitle('s.unticked', 12),
            fixtureTitle('s.withdrawn', 12),
            fixtureTitle('s.small', 9),
          ]),
        ],
        withdrawnTitles: {'s.withdrawn'},
      );
      final p = QuizPicker(catalog);
      final progress = _known([
        's.ticked',
        's.withdrawn',
        's.small',
        'gone.unknown',
      ]);
      for (var s = 0; s < 20; s++) {
        final r = p.mixedRound(progress, GameRng(s))!;
        expect({for (final q in r.questions) q.titleId}, {'s.ticked'});
      }
    });

    test('null when nothing offered is ticked', () {
      final catalog = QuizCatalog(
        series: [
          fixtureSeries('s', [
            fixtureTitle('s.a', 12),
            fixtureTitle('s.withdrawn', 12),
            fixtureTitle('s.small', 9),
          ]),
        ],
        withdrawnTitles: {'s.withdrawn'},
      );
      final p = QuizPicker(catalog);
      expect(p.mixedRound(const QuizProgress(), GameRng(1)), isNull);
      expect(
        p.mixedRound(_known(['s.withdrawn', 's.small', 'x.y']), GameRng(1)),
        isNull,
      );
    });

    test('single-title: null if not offered, allowed if unticked', () {
      final catalog = QuizCatalog(
        series: [
          fixtureSeries('s', [
            fixtureTitle('s.a', 12),
            fixtureTitle('s.withdrawn', 12),
            fixtureTitle('s.small', 9),
          ]),
        ],
        withdrawnTitles: {'s.withdrawn'},
      );
      final p = QuizPicker(catalog);
      const none = QuizProgress();
      expect(p.singleTitleRound('s.withdrawn', none, GameRng(1)), isNull);
      expect(p.singleTitleRound('s.small', none, GameRng(1)), isNull);
      expect(p.singleTitleRound('nope.nope', none, GameRng(1)), isNull);
      final r = p.singleTitleRound('s.a', none, GameRng(1))!;
      expect(r.titleId, 's.a');
      expect(r.isMixed, isFalse);
      expect(r.questions, hasLength(quizRoundLength));
    });
  });

  group('presentation', () {
    test('level 1 precedes level 2, equal levels keep draw order', () {
      final title = fixtureTitle('t.a', 24, levelOf: (n) => n.isEven ? 2 : 1);
      final picker = QuizPicker(
        QuizCatalog(
          series: [
            fixtureSeries('t', [title]),
          ],
        ),
      );
      for (var s = 0; s < 100; s++) {
        final r = picker.singleTitleRound(
          't.a',
          const QuizProgress(),
          GameRng(s),
        )!;
        final levels = [for (final q in r.questions) q.question.level];
        expect(levels, [...levels]..sort(), reason: 'seed $s');
        for (var i = 1; i < 10; i++) {
          if (levels[i] == levels[i - 1]) {
            expect(
              r.questions[i].drawIndex,
              greaterThan(r.questions[i - 1].drawIndex),
              reason: 'seed $s position $i',
            );
          }
        }
      }
    });

    test('options are distinct, hold the answer, and vary', () {
      final picker = QuizPicker(fixtureCatalog());
      final progress = _known([narniaId, ...dahlIds]);
      final wrongSeen = <String>{};
      final positions = <int>{};
      for (var s = 0; s < 200; s++) {
        final r = picker.mixedRound(progress, GameRng(s))!;
        for (final q in r.questions) {
          expect(q.options, hasLength(3));
          expect(q.options.toSet(), hasLength(3));
          expect(q.options[q.answerIndex], q.question.a);
          final others = [
            for (var i = 0; i < 3; i++)
              if (i != q.answerIndex) q.options[i],
          ];
          expect(others.every(q.question.wrong.contains), isTrue);
          wrongSeen.addAll(others.where((o) => o.startsWith('W 1 ')));
          if (q.question.a == 'A 1') positions.add(q.answerIndex);
        }
      }
      expect(wrongSeen, {'W 1 a', 'W 1 b', 'W 1 c'});
      expect(positions, {0, 1, 2});
    });

    test('same rng seed and progress give an identical round', () {
      final picker = QuizPicker(fixtureCatalog());
      final progress = _known([narniaId, ...dahlIds]);
      final a = picker.mixedRound(progress, GameRng(9))!;
      final b = picker.mixedRound(progress, GameRng(9))!;
      expect(_ids(a), _ids(b));
      expect(
        [for (final q in a.questions) q.options],
        [for (final q in b.questions) q.options],
      );
      final c = picker.mixedRound(progress, GameRng(10))!;
      expect(_ids(c), isNot(_ids(a)));
    });
  });

  test('a mixed round then a single-title round re-asks nothing', () {
    final title = fixtureTitle('t.a', 24);
    final picker = QuizPicker(
      QuizCatalog(
        series: [
          fixtureSeries('t', [title]),
        ],
      ),
    );
    for (var s = 0; s < 50; s++) {
      final mixed = picker.mixedRound(_known(['t.a']), GameRng(s))!;
      final progress = _playThrough(mixed, _known(['t.a']));
      final single = picker.singleTitleRound(
        't.a',
        progress,
        GameRng(s + 1000),
      )!;
      // 10 + 10 of 24 stay within one order.
      expect(_ids(mixed).toSet().intersection(_ids(single).toSet()), isEmpty);
    }
  });

  test('a round that runs off the end of an order skips what it has asked', () {
    // next 20 of 24 leaves four in the old order; the fresh order must not
    // re-ask any of those four, whatever the new shuffle does.
    final title = fixtureTitle('t.a', 24);
    final picker = QuizPicker(
      QuizCatalog(
        series: [
          fixtureSeries('t', [title]),
        ],
      ),
    );
    var skipped = false;
    for (var seed = 0; seed < 200; seed++) {
      final progress = QuizProgress(
        titles: {'t.a': QuizTitleProgress(seed: seed, next: 20, pool: 24)},
      );
      final r = picker.singleTitleRound('t.a', progress, GameRng(seed))!;
      expect(_ids(r).toSet(), hasLength(10));
      final newSeed = r.questions.firstWhere((q) => q.drawIndex == 9).seedAfter;
      final head = titleOrder(title, newSeed).take(6).map((q) => q.id);
      final tail = titleOrder(title, seed).skip(20).map((q) => q.id).toSet();
      if (head.any(tail.contains)) skipped = true;
    }
    expect(
      skipped,
      isTrue,
      reason: 'the scenario must occur to prove anything',
    );
  });
}

bool _same(Iterable<String> a, Iterable<String> b) {
  final x = a.toList();
  final y = b.toList();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}
