// The Quiz menu (`PLAN-phase-10-quiz.md` §4.5), driven through the app.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/core/ui/big_button.dart';
import 'package:zibo_games/features/quiz/data/providers.dart';
import 'package:zibo_games/features/quiz/ui/quiz_style.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../quiz_fixtures.dart';

void main() {
  testWidgets('Quiz me is disabled until something is ticked on the shelf', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = await pumpApp(
      tester,
      store: MemorySaveStore(initial: freshSave()),
      overrides: [quizCatalogProvider.overrideWithValue(fixtureCatalog())],
    );
    unawaited(
      Navigator.of(
        tester.element(find.byType(Scaffold).first),
      ).pushNamed(AppRoutes.quiz),
    );
    await tester.pumpAndSettle();

    BigButton button(String label) =>
        tester.widget<BigButton>(find.widgetWithText(BigButton, label));
    expect(button(quizMeLabel).onPressed, isNull);
    expect(find.text(tickShelfHint), findsOneWidget);
    expect(button(myShelfLabel).selected, isTrue);

    await tester.tap(find.text(myShelfLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(narniaId));
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, {narniaId});

    Navigator.of(tester.element(find.byType(Scaffold).last)).pop();
    await tester.pumpAndSettle();
    expect(button(quizMeLabel).onPressed, isNotNull);
    expect(find.text(tickShelfHint), findsNothing);
    expect(button(myShelfLabel).selected, isFalse);
  });

  testWidgets('a tick on a withdrawn title does not enable Quiz me', (
    tester,
  ) async {
    final save = freshSave();
    final profile = save.profiles.single.copyWith(
      quiz: const QuizProgress(known: {narniaId}),
    );
    await pumpApp(
      tester,
      store: MemorySaveStore(initial: save.copyWith(profiles: [profile])),
      overrides: [
        quizCatalogProvider.overrideWithValue(
          fixtureCatalog(withdrawn: {narniaId}),
        ),
      ],
    );
    unawaited(
      Navigator.of(
        tester.element(find.byType(Scaffold).first),
      ).pushNamed(AppRoutes.quiz),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<BigButton>(find.widgetWithText(BigButton, quizMeLabel))
          .onPressed,
      isNull,
    );
  });
}
