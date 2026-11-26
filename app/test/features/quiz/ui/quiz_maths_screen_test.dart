// The Maths screen and a Maths round, driven through the real app
// (`PLAN-quiz-maths.md` §4.5): settings written to the profile, Start's
// disabled states, the Quiz menu over an empty catalog, and a whole round to
// the card with the score saved.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/clock.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_codec.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/features/quiz/data/providers.dart';
import 'package:zibo_games/features/quiz/ui/quiz_maths_screen.dart';
import 'package:zibo_games/features/quiz/ui/quiz_style.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../quiz_fixtures.dart';

SaveData _saveWith(QuizProgress quiz) {
  final save = freshSave();
  return save.copyWith(profiles: [save.profiles.first.copyWith(quiz: quiz)]);
}

Future<(ProviderContainer, MemorySaveStore)> _open(
  WidgetTester tester,
  String route, {
  QuizProgress quiz = const QuizProgress(),
}) async {
  tester.view.physicalSize = const Size(400, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemorySaveStore(initial: _saveWith(quiz));
  final container = await pumpApp(
    tester,
    store: store,
    overrides: [
      nowProvider.overrideWithValue(() => DateTime.utc(2026, 11, 25, 9)),
    ],
  );
  unawaited(
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(route),
  );
  await tester.pumpAndSettle();
  return (container, store);
}

QuizMathsProgress _maths(ProviderContainer c) =>
    c.read(activeProfileProvider).quiz.maths;

BigButton _button(WidgetTester tester, String label) =>
    tester.widget<BigButton>(find.widgetWithText(BigButton, label));

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The right answer to the question on screen, worked out from its text.
String _answerOnScreen(WidgetTester tester) {
  final shape = RegExp(r'^What is (\d+) (.) (\d+)\?$');
  final text = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? '')
      .firstWhere(shape.hasMatch);
  final m = shape.firstMatch(text)!;
  final (a, b) = (int.parse(m[1]!), int.parse(m[3]!));
  return switch (m[2]) {
    '+' => '${a + b}',
    '−' => '${a - b}',
    '×' => '${a * b}',
    _ => '${a ~/ b}',
  };
}

void main() {
  testWidgets('the Quiz menu over an empty catalog offers only Maths', (
    tester,
  ) async {
    await _open(tester, AppRoutes.quiz);

    expect(find.text(mathsLabel), findsOneWidget);
    expect(find.text(quizMeLabel), findsNothing);
    expect(find.text(pickOneLabel), findsNothing);
    expect(find.text(myShelfLabel), findsNothing);

    await _tap(tester, find.text(mathsLabel));
    expect(find.text(mathsStartLabel), findsOneWidget);
  });

  testWidgets('the Quiz menu over a catalog offers the bank and Maths', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [quizCatalogProvider.overrideWithValue(fixtureCatalog())],
    );
    unawaited(
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pushNamed(AppRoutes.quiz),
    );
    await tester.pumpAndSettle();

    for (final label in [quizMeLabel, pickOneLabel, myShelfLabel, mathsLabel]) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
  });

  testWidgets('the defaults: adding and taking away within 10, tables hidden', (
    tester,
  ) async {
    await _open(tester, AppRoutes.quizMaths);

    expect(_button(tester, mathsStartLabel).onPressed, isNotNull);
    expect(_button(tester, mathsOpLabel(QuizMathsOp.add)).selected, isTrue);
    expect(
      _button(tester, mathsOpLabel(QuizMathsOp.subtract)).selected,
      isTrue,
    );
    expect(
      _button(tester, mathsOpLabel(QuizMathsOp.multiply)).selected,
      isFalse,
    );
    expect(find.text(mathsUpToHeading), findsOneWidget);
    expect(find.text(mathsTablesHeading), findsNothing);
    expect(find.bySemanticsLabel('Up to 10'), findsOneWidget);
  });

  testWidgets('toggles write the profile and show what they need', (
    tester,
  ) async {
    final (container, _) = await _open(tester, AppRoutes.quizMaths);

    await _tap(tester, find.text(mathsOpLabel(QuizMathsOp.multiply)));
    expect(_maths(container).ops, contains(QuizMathsOp.multiply));
    expect(find.text(mathsTablesHeading), findsOneWidget);

    // 7 on, 2 off.
    await _tap(tester, find.byKey(const ValueKey('mathsTable7')));
    await _tap(tester, find.byKey(const ValueKey('mathsTable2')));
    expect(_maths(container).tables, {5, 7, 10});

    await _tap(tester, find.byKey(const ValueKey('mathsUpTo20')));
    expect(_maths(container).upTo, 20);

    // Adding and taking away off: the size has nothing to apply to.
    await _tap(tester, find.text(mathsOpLabel(QuizMathsOp.add)));
    await _tap(tester, find.text(mathsOpLabel(QuizMathsOp.subtract)));
    expect(_maths(container).ops, {QuizMathsOp.multiply});
    expect(find.text(mathsUpToHeading), findsNothing);
  });

  testWidgets('Start is disabled, and says why, with nothing to ask', (
    tester,
  ) async {
    await _open(
      tester,
      AppRoutes.quizMaths,
      quiz: const QuizProgress(
        maths: QuizMathsProgress(ops: {QuizMathsOp.divide}, tables: {3}),
      ),
    );
    expect(_button(tester, mathsStartLabel).onPressed, isNotNull);

    // Dividing on with no table known.
    await _tap(tester, find.byKey(const ValueKey('mathsTable3')));
    expect(_button(tester, mathsStartLabel).onPressed, isNull);
    expect(find.text(mathsPickTableHint), findsOneWidget);

    // Nothing on at all.
    await _tap(tester, find.text(mathsOpLabel(QuizMathsOp.divide)));
    expect(_button(tester, mathsStartLabel).onPressed, isNull);
    expect(find.text(mathsPickOpHint), findsOneWidget);
    expect(find.text(mathsTablesHeading), findsNothing);
  });

  // The sweep sees only the defaults, which hide the times-table grid.
  for (final size in const [Size(360, 640), Size(640, 360)]) {
    testWidgets('every section fits at 200 % text on $size', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(
        tester,
        AppRoutes.quizMaths,
        quiz: QuizProgress(
          maths: QuizMathsProgress(
            ops: QuizMathsOp.values.toSet(),
            tables: {for (var t = 1; t <= 12; t++) t},
          ),
        ),
      );
      tester.view.physicalSize = size;
      await tester.pumpAndSettle();

      // An overflow is reported as an exception, which fails the test.
      // The list builds lazily, so the grid is scrolled to, not looked up.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('mathsTable12')),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.pumpAndSettle();
      final square = tester.getSize(find.byKey(const ValueKey('mathsTable12')));
      expect(square.width, greaterThanOrEqualTo(72));
      expect(square.height, greaterThanOrEqualTo(72));
    });
  }

  testWidgets('a Maths round reaches the card and saves only Maths', (
    tester,
  ) async {
    const before = QuizProgress(
      known: {'a.b'},
      mixed: QuizMixedProgress(rounds: 2, best: 7),
      maths: QuizMathsProgress(
        ops: {QuizMathsOp.multiply, QuizMathsOp.divide},
        tables: {6, 7},
      ),
    );
    final (container, store) = await _open(
      tester,
      AppRoutes.quizMaths,
      quiz: before,
    );

    await _tap(tester, find.text(mathsStartLabel));
    for (var i = 0; i < 10; i++) {
      final answer = _answerOnScreen(tester);
      final button =
          [
            for (var o = 0; o < 3; o++) find.byKey(ValueKey('quizAnswer$o')),
          ].firstWhere(
            (b) => find
                .descendant(of: b, matching: find.text(answer))
                .evaluate()
                .isNotEmpty,
          );
      await _tap(tester, button);
      if (i < 9) await _tap(tester, find.text(nextLabel));
    }
    // Pumped past rather than settled: the card's confetti is still falling.
    await tester.tap(find.text(finishLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('10 out of 10'), findsOneWidget);
    await container.read(progressRepositoryProvider).flush();
    final saved = decodeSave(store.contents!).profiles.first.quiz;
    expect(
      saved,
      before.copyWith(maths: before.maths.copyWith(rounds: 1, best: 10)),
    );

    // Back on the Maths screen, the best shows.
    await tester.tap(find.text(backToQuizLabel));
    await tester.pumpAndSettle();
    expect(find.text(quizBestLabel(10)), findsOneWidget);
  });
}
