// Pick one (`PLAN-phase-10-quiz.md` §4.5).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/quiz/data/providers.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/ui/quiz_play_screen.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../quiz_fixtures.dart';

Future<void> openPick(
  WidgetTester tester, {
  QuizProgress quiz = const QuizProgress(),
  QuizCatalog? catalog,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final save = freshSave();
  await pumpApp(
    tester,
    store: MemorySaveStore(
      initial: save.copyWith(
        profiles: [save.profiles.single.copyWith(quiz: quiz)],
      ),
    ),
    overrides: [
      quizCatalogProvider.overrideWithValue(catalog ?? fixtureCatalog()),
    ],
  );
  unawaited(
    Navigator.of(
      tester.element(find.byType(Scaffold).first),
    ).pushNamed(AppRoutes.quizPick),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ticked titles come first within their series', (tester) async {
    await openPick(tester, quiz: QuizProgress(known: {dahlIds[2], dahlIds[3]}));
    double top(String id) => tester.getTopLeft(find.text(id)).dy;
    expect(top(dahlIds[2]), lessThan(top(dahlIds[3])));
    expect(top(dahlIds[3]), lessThan(top(dahlIds[0])));
    expect(top(dahlIds[0]), lessThan(top(dahlIds[1])));
    // Series order is untouched by ticks.
    expect(top(narniaId), lessThan(top(dahlIds[2])));
  });

  testWidgets('a title opens its own round', (tester) async {
    await openPick(tester);
    // Unticked titles can be played too.
    await tester.tap(find.text(dahlIds[1]));
    await tester.pumpAndSettle();
    final play = tester.widget<QuizPlayScreen>(find.byType(QuizPlayScreen));
    expect(play.args, QuizPlayArgs.title(dahlIds[1]));
    expect(
      ModalRoute.of(tester.element(find.byType(QuizPlayScreen)))!.settings.name,
      AppRoutes.quizPlay,
    );
  });

  testWidgets('withdrawn and under-threshold titles never appear', (
    tester,
  ) async {
    final catalog = QuizCatalog(
      series: [
        fixtureSeries('dahl', [
          fixtureTitle('dahl.matilda', 24),
          fixtureTitle('dahl.bfg', 24),
          fixtureTitle('dahl.thin', 9),
        ]),
      ],
      withdrawnTitles: {'dahl.bfg'},
    );
    await openPick(tester, catalog: catalog);
    expect(find.text('dahl.matilda'), findsOneWidget);
    expect(find.text('dahl.bfg'), findsNothing);
    expect(find.text('dahl.thin'), findsNothing);
  });

  testWidgets('a played title shows its best', (tester) async {
    await openPick(
      tester,
      quiz: const QuizProgress(
        titles: {
          narniaId: QuizTitleProgress(
            seed: 1,
            next: 10,
            pool: 24,
            rounds: 1,
            best: 7,
          ),
        },
      ),
    );
    expect(find.text('Best 7 out of 10'), findsOneWidget);
  });

  testWidgets('groups by collection with a heading each', (tester) async {
    await openPick(tester, catalog: fixtureMultiCollectionCatalog());
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('show.two'), findsOneWidget);
  });

  testWidgets('an empty catalog shows one gentle line', (tester) async {
    await openPick(tester, catalog: QuizCatalog.empty());
    expect(find.text('There are no quizzes here yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
