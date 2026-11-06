// The scored variant of `CompletionCard`, used by the quiz. The timed
// variant is covered through the Sudoku and Tracks completion tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/ui/completion_card.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    VoidCallback? onNext,
    VoidCallback? onBack,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompletionCard.score(
          score: 7,
          outOf: 10,
          stars: 2,
          nextLabel: 'Play again',
          onNext: onNext,
          backLabel: 'Back to Quiz',
          onBack: onBack ?? () {},
        ),
      ),
    ),
  );

  testWidgets('shows the score, the stars and no timed rows', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCard(tester, onNext: () {});

    expect(find.text(completionTitle), findsOneWidget);
    expect(find.text('7 out of 10'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNWidgets(2));
    expect(find.bySemanticsLabel('2 of 3 stars'), findsOneWidget);
    expect(find.text(completionTimeLabel), findsNothing);
    expect(find.text(completionMistakesLabel), findsNothing);
    expect(find.text(nextPuzzleLabel), findsNothing);
    handle.dispose();
  });

  testWidgets('the two buttons call back, and a null next hides one', (
    tester,
  ) async {
    var next = 0;
    var back = 0;
    await pumpCard(tester, onNext: () => next++, onBack: () => back++);

    await tester.tap(find.text('Play again'));
    await tester.tap(find.text('Back to Quiz'));
    expect((next, back), (1, 1));

    await pumpCard(tester);
    expect(find.text('Play again'), findsNothing);
    expect(find.text('Back to Quiz'), findsOneWidget);
  });
}
