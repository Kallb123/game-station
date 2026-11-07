// The text-size test (`PLAN-quiz-screen.md` §1, §4.4): the longest text the
// content rules allow must fit the screen the way the plan promises.
//
// At 100 % text, on a 360x760 phone and a 960x528 tablet, the page must not
// scroll: every answer and Next sit whole inside the window. At 200 % text on
// the old 360x640 phone the clamped type cannot fit, so the page may scroll,
// but nothing may overflow and Next must have been scrolled into view.
//
// Each run plays the worst state, not an idle one: two wrong answers (two
// "Not this one" lines) and then the right one (tick badge and Next), because
// that is the tallest the screen ever gets. It runs the real route in its real
// chrome (back control, progress bar), because a bare question widget has room
// the screen does not. The caps in `quiz_catalog.dart` are whatever this test
// shows to fit.

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

/// Three answers of exactly [maxAnswerLength] characters, ordinary words. A
/// cap is only as good as the words it was measured with: three answers of
/// 34 characters each built round one 15-letter word wrap to a line more and
/// overflow the phone window, which is what the real-bank tests below are for.
const _atAnswerCap = [
  'The enormous friendly mountain lion',
  "Professor Kirke's big country house",
  'The silver chair in the dark castle',
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

/// The windows the no-scroll guarantee holds in, at 100 % text
/// (`PLAN-quiz-screen.md` §1): a current phone after its bars, and a Fire HD 8
/// sideways after its bars.
const _noScrollWindows = [Size(360, 760), Size(960, 528)];

/// The old phone window, held to "nothing overflows, and Next can be reached"
/// at 200 % text, where the clamped type cannot fit any phone without scrolling.
const _bigTextWindow = Size(360, 640);

/// Pumps the play route in [window] at [textScale], then plays the worst state:
/// two wrong answers (two "Not this one" lines) and then the right one (the
/// tick badge and the Next button), all showing at once. The round shuffles the
/// order of the options, so each answer is found by its text, not its position.
///
/// Asserts that nothing overflowed and that Next exists, and leaves the page as
/// the child would see it. Returns nothing; callers read the rects.
Future<void> _playWorstState(
  WidgetTester tester,
  String question,
  List<String> answers, {
  required Size window,
  required double textScale,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
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

  // Which slot holds which answer. Two slots can hold the same wrong text, so
  // the right one is the one slot whose text is the right answer's.
  String textAt(int i) => tester
      .widget<Text>(
        find.descendant(
          of: find.byKey(ValueKey('quizAnswer$i')),
          matching: find.byType(Text),
        ),
      )
      .data!;
  final right = [
    for (var i = 0; i < 3; i++)
      if (textAt(i) == answers[0]) i,
  ].single;
  final wrong = [
    for (var i = 0; i < 3; i++)
      if (i != right) i,
  ];

  for (final i in [...wrong, right]) {
    final slot = find.byKey(ValueKey('quizAnswer$i'));
    // Scrolled to if it has to be (200 % text), so a failure reports where
    // everything is rather than a missed tap.
    await tester.ensureVisible(slot);
    await tester.tap(slot);
    await tester.pumpAndSettle();
  }
  expect(tester.takeException(), isNull);
  expect(find.text(nextLabel), findsOneWidget);
}

void _expectWithin(WidgetTester tester, Finder f, Size window, String what) {
  final r = tester.getRect(f);
  expect(r.left, greaterThanOrEqualTo(0), reason: what);
  expect(r.top, greaterThanOrEqualTo(0), reason: what);
  expect(r.right, lessThanOrEqualTo(window.width), reason: what);
  expect(r.bottom, lessThanOrEqualTo(window.height), reason: what);
}

/// The guarantee: at 100 % text in [window] the page does not scroll and every
/// answer and Next lie wholly inside it. Returns the bottom edge of Next.
Future<double> _expectFitsWithoutScrolling(
  WidgetTester tester,
  String question,
  List<String> answers,
  Size window,
) async {
  await _playWorstState(
    tester,
    question,
    answers,
    window: window,
    textScale: 1,
  );
  final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
  expect(
    scrollable.position.maxScrollExtent,
    0,
    reason: 'the page needed to scroll in $window',
  );
  for (var i = 0; i < 3; i++) {
    _expectWithin(
      tester,
      find.byKey(ValueKey('quizAnswer$i')),
      window,
      'answer $i',
    );
  }
  _expectWithin(tester, find.byType(FilledButton), window, 'Next');
  return tester.getRect(find.byType(FilledButton)).bottom;
}

/// At 200 % text nothing overflows, and the screen has scrolled Next into view
/// by itself once the question was solved. Scrolling is allowed.
Future<double> _expectReachableAtBigText(
  WidgetTester tester,
  String question,
  List<String> answers,
) async {
  await _playWorstState(
    tester,
    question,
    answers,
    window: _bigTextWindow,
    textScale: 2,
  );
  _expectWithin(
    tester,
    find.byType(FilledButton),
    _bigTextWindow,
    'Next, at 200 % text',
  );
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
    for (final n in [40, 60, 65, 80, 99, 100]) {
      expect(_questionOf(n).length, n);
    }
    for (final a in _atAnswerCap) {
      expect(a.length, maxAnswerLength);
    }
  });

  // Every question rather than only the longest: where a line breaks depends
  // on the words, so a shorter question can take more lines than a longer one.
  // Each is shown with its own three longest answers, the worst set a round
  // can draw for it. This is what holds a content pull request to the screen,
  // where the content test only counts characters.
  for (final entry in _realBank()) {
    List<String> longest() => ([
      ...entry.answers,
    ]..sort((a, b) => b.length.compareTo(a.length))).take(3).toList();
    for (final window in _noScrollWindows) {
      testWidgets('fits ${window.width.toInt()}x${window.height.toInt()}: '
          '${entry.q}', (tester) async {
        await _expectFitsWithoutScrolling(tester, entry.q, longest(), window);
      });
    }
    testWidgets('reachable at 200 %: ${entry.q}', (tester) async {
      await _expectReachableAtBigText(tester, entry.q, longest());
    });
  }

  group("the real bank's longest question and answers", () {
    final bank = _realBank();
    final question = bank
        .map((e) => e.q)
        .reduce((a, b) => b.length > a.length ? b : a);
    final answers = {for (final e in bank) ...e.answers}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final longest = answers.take(3).toList();

    for (final window in _noScrollWindows) {
      testWidgets('fit ${window.width.toInt()}x${window.height.toInt()}', (
        tester,
      ) async {
        final bottom = await _expectFitsWithoutScrolling(
          tester,
          question,
          longest,
          window,
        );
        // ignore: avoid_print
        print(
          'real bank: question ${question.length} chars, answers '
          '${longest.map((a) => a.length).toList()}, Next ends at $bottom of '
          '${window.height} (${window.width.toInt()} wide)',
        );
      });
    }
    testWidgets('are reachable at 200 %', (tester) async {
      final bottom = await _expectReachableAtBigText(tester, question, longest);
      // ignore: avoid_print
      print('real bank at 200 %: Next ends at $bottom of 640');
    });
  });

  group('text exactly at the caps', () {
    for (final window in _noScrollWindows) {
      testWidgets('fits ${window.width.toInt()}x${window.height.toInt()}', (
        tester,
      ) async {
        final bottom = await _expectFitsWithoutScrolling(
          tester,
          _questionOf(maxQuestionLength),
          _atAnswerCap,
          window,
        );
        // ignore: avoid_print
        print(
          'caps: question $maxQuestionLength, answers $maxAnswerLength, Next '
          'ends at $bottom of ${window.height} (${window.width.toInt()} wide)',
        );
      });
    }
    testWidgets('is reachable at 200 %', (tester) async {
      final bottom = await _expectReachableAtBigText(
        tester,
        _questionOf(maxQuestionLength),
        _atAnswerCap,
      );
      // ignore: avoid_print
      print('caps at 200 %: Next ends at $bottom of 640');
    });
  });
}
