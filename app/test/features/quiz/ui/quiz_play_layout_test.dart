// The text-size test (`PLAN-phase-10-quiz.md` §4.8): the longest text the
// content rules allow, at 200 % text on a 360x640 window, must leave every
// answer and Next whole inside the window without scrolling.
//
// It runs the real route, in its real chrome (back control, progress dots),
// because a bare question widget has room the screen does not.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/quiz/data/providers.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/ui/quiz_play_screen.dart';
import 'package:zibo_games/features/quiz/ui/quiz_style.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';

/// Three answers of exactly [maxAnswerLength] characters, ordinary words.
const _cap30 = [
  'The enormous friendly mountain',
  "Professor Digory Kirke's house",
  'The silver chair in the castle',
];

/// Every question of every pack in the bank, as raw text.
List<({String q, List<String> answers})> _realBank() {
  final out = <({String q, List<String> answers})>[];
  for (final dir in ['assets/quiz/store', 'assets/quiz/private']) {
    for (final file in Directory(dir).listSync().whereType<File>()) {
      if (!file.path.endsWith('.json') || file.path.endsWith('index.json')) {
        continue;
      }
      final pack = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final title in pack['titles'] as List<dynamic>) {
        for (final q
            in (title as Map<String, dynamic>)['questions'] as List<dynamic>) {
          final m = q as Map<String, dynamic>;
          out.add((
            q: m['q'] as String,
            answers: [m['a'] as String, ...(m['wrong'] as List).cast<String>()],
          ));
        }
      }
    }
  }
  return out;
}

/// A catalog of one title whose every question is the same text, so whichever
/// ten the picker draws put the worst case on screen. [answers] are the three
/// to show, longest first; the first is the right one.
QuizCatalog _catalogOf(String question, List<String> answers) => QuizCatalog(
  series: [
    QuizSeries(
      id: 'worst',
      name: 'worst',
      collection: QuizCollection.book,
      audience: QuizAudience.store,
      titles: [
        QuizTitle(
          id: 'worst.case',
          name: 'worst',
          questions: [
            for (var n = 1; n <= 12; n++)
              QuizQuestion(
                id: 'worst.case.${n.toString().padLeft(3, '0')}',
                level: 1,
                checked: true,
                q: question,
                a: answers[0],
                // Three wrong answers of which two are shown: the second and
                // third longest, so the three longest always appear.
                wrong: [answers[1], answers[2], answers[2]],
                source: 's',
              ),
          ],
        ),
      ],
    ),
  ],
);

/// Pumps the play route at 360x640 and 200 % text, taps the right answer (the
/// widest state: it carries the tick), and asserts that nothing overflowed,
/// that nothing scrolls, and that every answer and Next lie wholly inside the
/// window. Returns the bottom edge of Next, for the report.
Future<double> _expectFits(
  WidgetTester tester,
  String question,
  List<String> answers,
) async {
  const window = Size(360, 640);
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = 2;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

  await pumpApp(
    tester,
    store: MemorySaveStore(initial: freshSave()),
    overrides: [
      quizCatalogProvider.overrideWithValue(_catalogOf(question, answers)),
      nowProvider.overrideWithValue(testClock),
    ],
  );
  unawaited(
    tester
        .state<NavigatorState>(find.byType(Navigator))
        .pushNamed(
          AppRoutes.quizPlay,
          arguments: const QuizPlayArgs.title('worst.case'),
        ),
  );
  await tester.pumpAndSettle();

  // Scrolled to if it has to be, so a failure reports where everything is
  // rather than a missed tap.
  await tester.ensureVisible(find.text(answers[0]));
  await tester.tap(find.text(answers[0]));
  await tester.pumpAndSettle();
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  final extent = scrollable.position.maxScrollExtent;
  scrollable.position.jumpTo(0);
  await tester.pump();

  expect(tester.takeException(), isNull);
  expect(find.text(nextLabel), findsOneWidget);

  void expectWithin(Finder f, String what) {
    final r = tester.getRect(f);
    expect(r.left, greaterThanOrEqualTo(0), reason: what);
    expect(r.top, greaterThanOrEqualTo(0), reason: what);
    expect(r.right, lessThanOrEqualTo(window.width), reason: what);
    expect(r.bottom, lessThanOrEqualTo(window.height), reason: what);
  }

  for (var i = 0; i < 3; i++) {
    expectWithin(find.byKey(ValueKey('quizAnswer$i')), 'answer $i');
  }
  expectWithin(find.byType(FilledButton), 'Next');
  expect(extent, 0, reason: 'the page needed to scroll');
  return tester.getRect(find.byType(FilledButton)).bottom;
}

/// A question of exactly [length] characters made of ordinary words, ending in
/// a question mark: whole words from a fixed sentence, then one filler word of
/// the length that is left. Wrapping depends on where the spaces fall, so a
/// run of one letter would prove nothing.
String _questionOf(int length) {
  const words = [
    'Which',
    'of',
    'the',
    'three',
    'brave',
    'children',
    'found',
    'the',
    'hidden',
    'silver',
    'key',
    'inside',
    'the',
    'old',
    'wooden',
    'clock',
    'tower',
    'before',
    'the',
    'winter',
    'storm',
    'came',
    'to',
    'the',
    'town',
    'and',
    'the',
    'long',
    'night',
    'began',
  ];
  const filler = {
    1: 'a',
    2: 'my',
    3: 'one',
    4: 'door',
    5: 'house',
    6: 'garden',
    7: 'kitchen',
    8: 'mountain',
  };
  final target = length - 1; // Room for the question mark.
  final used = [words.first];
  var chars = words.first.length;
  for (final w in words.skip(1)) {
    final left = target - (chars + 1 + w.length);
    // Stop where what remains can still be one filler word (or nothing).
    if (left != 0 && left < 2) break;
    if (left < 0) break;
    used.add(w);
    chars += 1 + w.length;
  }
  final gap = target - chars;
  if (gap > 0) used.add(filler[gap - 1]!);
  return '${used.join(' ')}?';
}

/// Roboto, the face Android draws the app in, loaded for the test. `flutter
/// test` otherwise draws everything in Ahem, whose glyphs are each one em wide:
/// about twice the width of real text, so a layout test in it says "does not
/// fit" about text that fits comfortably on a phone.
///
/// Read from the Flutter SDK's own `material_fonts` artifact rather than
/// committed here: the pinned SDK fixes the version, and CI's SDK has the same
/// files. A missing file fails the test rather than silently measuring Ahem.
Future<void> _loadRoboto() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) fail('FLUTTER_ROOT is unset; run this under flutter test');
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final loader = FontLoader('Roboto');
  // Medium because Material 3 draws button labels at w500.
  for (final name in ['Regular', 'Medium', 'Bold']) {
    final file = File('$dir/Roboto-$name.ttf');
    if (!file.existsSync()) fail('no ${file.path}');
    loader.addFont(
      file.readAsBytes().then((bytes) => ByteData.view(bytes.buffer)),
    );
  }
  await loader.load();
}

void main() {
  setUpAll(_loadRoboto);

  test('the caps used below are the caps in the catalog', () {
    expect(_questionOf(maxQuestionLength).length, maxQuestionLength);
    for (final n in [40, 60, 80, 99, 100]) {
      expect(_questionOf(n).length, n);
    }
    for (final a in _cap30) {
      expect(a.length, maxAnswerLength);
    }
  });

  // Every question rather than only the longest: where a line breaks depends
  // on the words, so a shorter question can take more lines than a longer one.
  // Each is shown with its own three longest answers, the worst set a round
  // can draw for it. This is what holds a content pull request to the screen,
  // where the content test only counts characters.
  for (final entry in _realBank()) {
    testWidgets('fits: ${entry.q}', (tester) async {
      final answers = [...entry.answers]
        ..sort((a, b) => b.length.compareTo(a.length));
      await _expectFits(tester, entry.q, answers.take(3).toList());
    });
  }

  testWidgets("the real bank's longest question and answers fit", (
    tester,
  ) async {
    final bank = _realBank();
    expect(bank, isNotEmpty);
    final question = bank
        .map((e) => e.q)
        .reduce((a, b) => b.length > a.length ? b : a);
    final answers = {for (final e in bank) ...e.answers}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final longest = answers.take(3).toList();

    final bottom = await _expectFits(tester, question, longest);
    // ignore: avoid_print
    print(
      'real bank: question ${question.length} chars, answers '
      '${longest.map((a) => a.length).toList()}, Next ends at $bottom of 640',
    );
  });

  testWidgets('text exactly at the caps fits', (tester) async {
    final bottom = await _expectFits(
      tester,
      _questionOf(maxQuestionLength),
      _cap30,
    );
    // ignore: avoid_print
    print(
      'caps: question $maxQuestionLength, answers $maxAnswerLength, Next '
      'ends at $bottom of 640',
    );
  });
}
