import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/ui/quiz_style.dart';

import '../quiz_fixtures.dart';

void main() {
  test('stars: every finished round earns one, 8 and up earns three', () {
    expect(
      [
        for (final s in [0, 4, 5, 7, 8, 10]) quizStars(s),
      ],
      [1, 1, 2, 2, 3, 3],
    );
  });

  test('score and best labels', () {
    expect(quizScoreLabel(7), '7 out of 10');
    expect(quizBestLabel(8), 'Best 8 out of 10');
  });

  test('collection words and glyphs', () {
    expect(
      [for (final c in QuizCollection.values) quizCollectionLabel(c)],
      ['Books', 'TV', 'Films', 'Topics'],
    );
    expect(
      [for (final c in QuizCollection.values) quizAllLabel(c)],
      [
        "I've read them all",
        "I've watched them all",
        "I've watched them all",
        'Quiz me on them all',
      ],
    );
    expect(quizCollectionIcon(QuizCollection.film), Icons.movie);
  });

  test('neighbouring series take different colours', () {
    final catalog = fixtureCatalog();
    final colours = {
      for (final s in catalog.series)
        quizSeriesColor(catalog, s, Brightness.light),
    };
    expect(colours, hasLength(catalog.series.length));
  });

  testWidgets('QuizStars draws count stars under one semantics label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: QuizStars(count: 3))),
    );

    expect(find.byIcon(Icons.star), findsNWidgets(3));
    expect(find.bySemanticsLabel('3 of 3 stars'), findsOneWidget);
    handle.dispose();
  });
}
