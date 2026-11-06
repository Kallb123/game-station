// My shelf (`PLAN-phase-10-quiz.md` §4.5).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/quiz/data/providers.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/ui/quiz_shelf_screen.dart';
import 'package:zibo_games/routes.dart';

import '../../../app_harness.dart';
import '../quiz_fixtures.dart';

Future<ProviderContainer> openShelf(
  WidgetTester tester, {
  SaveData? save,
  MemorySaveStore? store,
  QuizCatalog? catalog,
}) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = await pumpApp(
    tester,
    store: store ?? MemorySaveStore(initial: save ?? freshSave()),
    overrides: [
      quizCatalogProvider.overrideWithValue(catalog ?? fixtureCatalog()),
    ],
  );
  unawaited(
    Navigator.of(
      tester.element(find.byType(Scaffold).first),
    ).pushNamed(AppRoutes.quizShelf),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a tick is written through the repository and the store', (
    tester,
  ) async {
    final store = MemorySaveStore(initial: freshSave());
    final container = await openShelf(tester, store: store);

    await tester.tap(find.text(narniaId));
    await tester.pump();
    expect(container.read(activeProfileProvider).quiz.known, {narniaId});
    expect((await store.load()).data.profiles.single.quiz.known, isEmpty);

    // Past the 500 ms debounce.
    await tester.pump(const Duration(milliseconds: 600));
    expect((await store.load()).data.profiles.single.quiz.known, {narniaId});
  });

  testWidgets('tiles are one checked semantics node each', (tester) async {
    final handle = tester.ensureSemantics();
    await openShelf(tester);
    expect(
      tester.getSemantics(find.text(narniaId)),
      matchesSemantics(
        label: narniaId,
        isButton: true,
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    await tester.tap(find.text(narniaId));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text(narniaId)),
      matchesSemantics(
        label: narniaId,
        isButton: true,
        hasCheckedState: true,
        isChecked: true,
        hasTapAction: true,
      ),
    );
    handle.dispose();
  });

  testWidgets('ticking on one profile leaves another profile alone', (
    tester,
  ) async {
    final container = await openShelf(tester);
    final repo = container.read(progressRepositoryProvider);
    final a = repo.activeProfile.id;
    final b = repo.createProfile(name: 'Bea', avatar: AvatarId.cat).id;
    repo.selectProfile(a);
    await tester.pumpAndSettle();

    await tester.tap(find.text(narniaId));
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, {narniaId});

    repo.selectProfile(b);
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, isEmpty);
    expect(find.byIcon(Icons.check_box), findsNothing);

    repo.selectProfile(a);
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, {narniaId});
    expect(find.byIcon(Icons.check_box), findsOneWidget);
    // Lets the debounced write fire so no timer outlives the test.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets("I've read them all ticks the series, again unticks it", (
    tester,
  ) async {
    final container = await openShelf(tester);
    final all = find.text("I've read them all");
    expect(all, findsNWidgets(2));

    // The second series is Dahl's.
    await tester.tap(all.last);
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, dahlIds.toSet());

    await tester.tap(all.last);
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, isEmpty);

    // Partly ticked: ticks the rest rather than clearing.
    await tester.tap(find.text(dahlIds.first));
    await tester.pumpAndSettle();
    await tester.tap(all.last);
    await tester.pumpAndSettle();
    expect(container.read(activeProfileProvider).quiz.known, dahlIds.toSet());
  });

  testWidgets('the collection switch needs more than one collection', (
    tester,
  ) async {
    await openShelf(tester);
    expect(find.text('Books'), findsNothing);
    expect(find.text('TV'), findsNothing);
  });

  testWidgets('switching collection shows that collection\'s series', (
    tester,
  ) async {
    await openShelf(tester, catalog: fixtureMultiCollectionCatalog());
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('TV'), findsOneWidget);
    expect(find.text('narnia'), findsOneWidget);
    expect(find.text('show.one'), findsNothing);

    await tester.tap(find.text('TV'));
    await tester.pumpAndSettle();
    expect(find.text('show'), findsOneWidget);
    expect(find.text('show.one'), findsOneWidget);
    expect(find.text("I've watched them all"), findsOneWidget);
    expect(find.text('narnia'), findsNothing);
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
    await openShelf(tester, catalog: catalog);
    expect(find.text('dahl.matilda'), findsOneWidget);
    expect(find.text('dahl.bfg'), findsNothing);
    expect(find.text('dahl.thin'), findsNothing);
  });

  testWidgets('a withdrawn title is not ticked by the whole-series button', (
    tester,
  ) async {
    final container = await openShelf(
      tester,
      catalog: fixtureCatalog(withdrawn: {dahlIds.first}),
    );
    await tester.tap(find.text("I've read them all").last);
    await tester.pumpAndSettle();
    expect(
      container.read(activeProfileProvider).quiz.known,
      dahlIds.skip(1).toSet(),
    );
  });

  testWidgets('a played title shows its best', (tester) async {
    final save = freshSave();
    final profile = save.profiles.single.copyWith(
      quiz: const QuizProgress(
        titles: {
          narniaId: QuizTitleProgress(
            seed: 1,
            next: 10,
            pool: 24,
            rounds: 2,
            best: 7,
          ),
        },
      ),
    );
    await openShelf(tester, save: save.copyWith(profiles: [profile]));
    expect(find.text('Best 7 out of 10'), findsOneWidget);
  });

  testWidgets('an empty catalog shows one gentle line', (tester) async {
    await openShelf(tester, catalog: QuizCatalog.empty());
    expect(find.text(quizNothingYetMessage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
