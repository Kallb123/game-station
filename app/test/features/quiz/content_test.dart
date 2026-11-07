// The content test (`PLAN-phase-10-quiz.md` §4.3): the real bank must be sound,
// and every rule that says so must be shown to fail.
//
// `AGENTS.md`: a guard needs its own test. A rule that never fires passes the
// real bank just as well as one that works, so each rule is also run against a
// deliberately broken copy of a minimal bank under `fixtures/`, and the
// `valid` fixture proves those copies are otherwise clean, so the only thing
// reported is the deliberate break.
//
// Tests run with the working directory at `app/`, so the real bank is read
// straight off disk with `dart:io` whatever flavour is under test; a private
// pack is checked on every run even though a store build would not bundle it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/model/quiz_pack.dart';

import 'quiz_bank_check.dart';

/// Fixture directory -> a substring of each problem it must report, and
/// nothing else. Where a rule cannot be broken without breaking another (a
/// title id copied into a second pack also has the wrong prefix there), both
/// are listed, so a fixture still fails for exactly the reasons named.
const _fixtures = <String, List<String>>{
  'extra-dir-at-root': ['unexpected entry in the bank root: extra'],
  'extra-file-at-root': ['unexpected entry in the bank root: README.md'],
  'non-json-file': ['private/notes.txt: not a .json file'],
  'unlisted-file': ['private/other.json: not listed in index.json'],
  'missing-file': ['private/ghost.json: listed in index.json but there is no'],
  'missing-index': ['private/index.json: missing'],
  'series-in-both': [
    'series "demo" is in both store/ and private/',
    'duplicate title id "demo.one"',
    'duplicate question id "demo.one.001"',
  ],
  'duplicate-series-in-index': ['duplicate series id "demo"'],
  'bad-json': ['not valid JSON'],
  'missing-field': ['missing field "source"'],
  'wrong-type': ['field "checked" must be a boolean'],
  'bad-format': ['unsupported format 2'],
  'series-not-filename': ['series "other" does not match file name "demo"'],
  'bad-collection': ['collection "comic" is not one of'],
  'bad-title-id': ['title id does not match'],
  'title-id-wrong-prefix': ['title id must start with "demo."'],
  'bad-question-id': ['question id must be "demo.one." and exactly three'],
  'duplicate-title-id-in-pack': ['duplicate title id "demo.one"'],
  'duplicate-question-id': ['duplicate question id "demo.one.001"'],
  'duplicate-title-id-across-packs': [
    'title id must start with "second."',
    'duplicate title id "demo.one", also in private/demo.json',
    'duplicate question id "demo.one.001", also in private/demo.json',
  ],
  'bad-level': ['level 3 is not 1 or 2'],
  'question-too-long': ['q is 101 characters, longer than 60'],
  'answer-too-long': ['a is 36 characters, longer than 35'],
  'wrong-answer-too-long': ['wrong[1] is 36 characters, longer than 35'],
  'empty-text': ['q is empty'],
  'wrong-not-three': ['wrong must hold exactly 3 answers, not 2'],
  'duplicate-answers': ['duplicate answers'],
  'all-of-the-above': ['is an all/none of the above'],
  'both': ['begins with "both"'],
  'positional-answer': ['names an option position'],
  'url-in-pack': ["contains '://'"],
  'unknown-withdrawn-title': ['"demo.ghost" names no title in the bank'],
};

void main() {
  final realBank = Directory('assets/quiz');

  test('the real bank has no problems', () {
    final problems = checkQuizBank(realBank);
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('prints the coverage table', () {
    // ignore: avoid_print
    print('\n${quizCoverageTable(realBank)}');
  });

  group('each rule fails against its fixture', () {
    final fixtureRoot = Directory('test/features/quiz/fixtures');

    test('the table names every fixture directory, and only those', () {
      final onDisk = fixtureRoot
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path.split(Platform.pathSeparator).last)
          .toSet();
      expect(onDisk, {..._fixtures.keys, 'valid'});
    });

    test('valid: a minimal bank reports nothing', () {
      final problems = checkQuizBank(Directory('${fixtureRoot.path}/valid'));
      expect(problems, isEmpty, reason: problems.join('\n'));
    });

    for (final entry in _fixtures.entries) {
      test('${entry.key}: ${entry.value.join(' + ')}', () {
        final problems = checkQuizBank(
          Directory('${fixtureRoot.path}/${entry.key}'),
        );
        final reason = 'got:\n${problems.join('\n')}';
        expect(problems, hasLength(entry.value.length), reason: reason);
        for (final expected in entry.value) {
          expect(
            problems.where((p) => p.contains(expected)),
            hasLength(1),
            reason: 'expected one problem containing "$expected"; $reason',
          );
        }
      });
    }
  });

  test('prints the bank parse time, scaled to 1000 questions', () {
    // §4.2 sets the bar at 100 ms on CI, past which parsing moves to
    // `compute`. No assertion: a timing bound on a shared runner is flaky,
    // and the number is recorded by hand in the plan's §8.
    final packs = _syntheticBank(series: 10, titlesPerSeries: 5, perTitle: 20);
    final questionCount = 10 * 5 * 20;

    List<QuizSeries> parseAll() => [
      for (final e in packs.entries)
        parseQuizPack(e.value, seriesId: e.key, audience: QuizAudience.store),
    ];

    // Same path as the loader: parse every pack, build the catalog, filter.
    int runOnce() {
      final watch = Stopwatch()..start();
      final catalog = QuizCatalog(series: parseAll()).withCheckedOnly();
      watch.stop();
      expect(catalog.offeredTitles, hasLength(50));
      return watch.elapsedMicroseconds;
    }

    runOnce(); // warm-up, so JIT start-up is not counted.
    final runs = [for (var i = 0; i < 7; i++) runOnce()]..sort();
    final medianMicros = runs[runs.length ~/ 2];
    final scaled = medianMicros / 1000 * (1000 / questionCount);
    // ignore: avoid_print
    print(
      'quiz bank parse, scaled to 1000 questions: '
      '${scaled.toStringAsFixed(1)} ms',
    );
  });
}

/// Packs in the real format: [series] files of [titlesPerSeries] titles of
/// [perTitle] questions each, keyed by series id.
Map<String, String> _syntheticBank({
  required int series,
  required int titlesPerSeries,
  required int perTitle,
}) {
  String three(int n) => n.toString().padLeft(3, '0');
  return {
    for (var s = 0; s < series; s++)
      'series-$s': jsonEncode({
        'format': 1,
        'series': 'series-$s',
        'name': 'Series $s',
        'collection': 'book',
        'titles': [
          for (var t = 0; t < titlesPerSeries; t++)
            {
              'id': 'series-$s.title-$t',
              'name': 'Title $t',
              'questions': [
                for (var n = 1; n <= perTitle; n++)
                  {
                    'id': 'series-$s.title-$t.${three(n)}',
                    'level': 1 + n % 2,
                    'checked': n % 5 != 0,
                    'q': 'What is the name of the kind teacher in chapter $n?',
                    'a': 'Miss Honey',
                    'wrong': ['Miss Trunchbull', 'Mrs Phelps', 'Miss Spider'],
                    'source': 'Chapter $n, "Miss Honey"',
                  },
              ],
            },
        ],
      }),
  };
}
