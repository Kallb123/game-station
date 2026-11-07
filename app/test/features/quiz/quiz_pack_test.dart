// Unit tests of the pack and index parser (`PLAN-phase-10-quiz.md` §4.2, §4.3).
//
// `content_test.dart` proves each rule fires through the whole-bank checker;
// these pin the parser's own contract: what a good pack becomes, that it
// reports every problem rather than the first, and the edges of the answer
// patterns, which are the part most likely to be wrong in either direction.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/model/quiz_pack.dart';

Map<String, Object?> _question({
  String id = 'demo.one.001',
  Object? level = 1,
  Object? checked = true,
  String q = 'What colour is the sky?',
  String a = 'Blue',
  List<String> wrong = const ['Red', 'Green', 'Yellow'],
  String source = 'Any atlas',
}) => {
  'id': id,
  'level': level,
  'checked': checked,
  'q': q,
  'a': a,
  'wrong': wrong,
  'source': source,
};

String _pack({List<Map<String, Object?>>? questions}) => jsonEncode({
  'format': 1,
  'series': 'demo',
  'name': 'Demo',
  'collection': 'topic',
  'titles': [
    {
      'id': 'demo.one',
      'name': 'One',
      'questions': questions ?? [_question()],
    },
  ],
});

QuizSeries _parse(String json) =>
    parseQuizPack(json, seriesId: 'demo', audience: QuizAudience.store);

List<String> _problems(String json) {
  try {
    _parse(json);
  } on QuizFormatException catch (e) {
    return e.problems;
  }
  return const [];
}

List<String> _answerProblems({
  String a = 'Blue',
  List<String> wrong = const ['Red', 'Green', 'Yellow'],
}) => _problems(
  _pack(
    questions: [_question(a: a, wrong: wrong)],
  ),
);

void main() {
  group('parseQuizPack', () {
    test('turns a good pack into values', () {
      final series = _parse(_pack());
      expect(series.id, 'demo');
      expect(series.collection, QuizCollection.topic);
      expect(series.audience, QuizAudience.store);
      final question = series.titles.single.questions.single;
      expect(question.id, 'demo.one.001');
      expect(question.a, 'Blue');
      expect(question.wrong, ['Red', 'Green', 'Yellow']);
      expect(question.checked, isTrue);
    });

    test('collects every problem rather than the first', () {
      final problems = _problems(
        _pack(
          questions: [
            _question(q: 'x' * 101, level: 3),
            _question(id: 'demo.one.002', wrong: ['a', 'b']),
          ],
        ),
      );
      expect(problems.length, greaterThanOrEqualTo(3));
    });

    test('rejects a top level that is not an object', () {
      expect(_problems('[]'), ['top level must be a JSON object']);
    });

    test('rejects text that is not JSON', () {
      expect(_problems('{"format": 1,'), [startsWith('not valid JSON')]);
    });

    test('trims before checking length and emptiness', () {
      expect(_answerProblems(a: '  Blue  '), isEmpty);
      expect(_answerProblems(a: ' ' * 40), [contains('a is empty')]);
      expect(_answerProblems(a: '${'y' * 35}   '), isEmpty);
    });

    test('compares answers after trimming and lowercasing', () {
      expect(_answerProblems(a: 'Blue', wrong: ['  BLUE', 'Red', 'Green']), [
        contains('duplicate answers'),
      ]);
    });

    test('rejects an answer that refers to the other options', () {
      for (final bad in [
        'All of the above',
        'none of the above',
        'All of these',
        'None of them',
        'Both',
        'Both A and B',
        'The first one',
        'the last answer',
        'Option A',
        'answer 2',
        'The middle one',
        'the top option',
      ]) {
        expect(
          _answerProblems(wrong: ['Red', 'Green', bad]),
          hasLength(1),
          reason: bad,
        );
      }
    });

    test('accepts answers that only resemble those patterns', () {
      for (final fine in [
        'The Last Battle',
        'Bothwell',
        'All the king\'s men',
        'The Middle',
        'None',
        'Option',
        'Second Life',
      ]) {
        expect(
          _answerProblems(wrong: ['Red', 'Green', fine]),
          isEmpty,
          reason: fine,
        );
      }
    });

    test('rejects an unknown collection and a mistyped level', () {
      final json = jsonEncode({
        'format': 1,
        'series': 'demo',
        'name': 'Demo',
        'collection': 'game',
        'titles': [
          {
            'id': 'demo.one',
            'name': 'One',
            'questions': [_question(level: '1')],
          },
        ],
      });
      final problems = _problems(json);
      expect(problems, contains(contains('collection "game"')));
      expect(problems, contains(contains('"level" must be an integer')));
    });

    test('accepts a title with no questions', () {
      expect(
        _parse(_pack(questions: const [])).titles.single.questions,
        isEmpty,
      );
    });
  });

  group('parseQuizIndex', () {
    String index({Object? series = const ['a', 'b'], Object? withdrawn}) =>
        jsonEncode({
          'format': 1,
          'series': series,
          'withdrawnTitles': withdrawn ?? const <String>[],
        });

    test('reads series in order and withdrawn titles', () {
      final parsed = parseQuizIndex(index(withdrawn: ['a.x']));
      expect(parsed.series, ['a', 'b']);
      expect(parsed.withdrawnTitles, ['a.x']);
    });

    test('rejects a wrong format, duplicates, empties and wrong types', () {
      expect(
        () => parseQuizIndex(
          '{"format": 2, "series": [], '
          '"withdrawnTitles": []}',
        ),
        throwsA(isA<QuizFormatException>()),
      );
      expect(
        () => parseQuizIndex(index(series: ['a', 'a'])),
        throwsA(isA<QuizFormatException>()),
      );
      expect(
        () => parseQuizIndex(index(series: ['a', ' '])),
        throwsA(isA<QuizFormatException>()),
      );
      expect(
        () => parseQuizIndex(index(series: 'a')),
        throwsA(isA<QuizFormatException>()),
      );
      expect(
        () => parseQuizIndex(index(withdrawn: [1])),
        throwsA(isA<QuizFormatException>()),
      );
      expect(() => parseQuizIndex('nope'), throwsA(isA<QuizFormatException>()));
    });
  });
}
