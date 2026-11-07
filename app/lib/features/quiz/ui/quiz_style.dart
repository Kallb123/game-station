// The quiz screens' shared look and words (`PLAN-phase-10-quiz.md` §4.5).
//
// The quiz imports nothing from `features/arcade/`, so the labels the play
// screen shares in spirit with `GameShell` are the quiz's own constants here
// (§3).

import 'package:flutter/material.dart';

import '../../../core/ui/theme.dart';
import '../../../core/ui/tokens.dart';
import '../model/quiz_catalog.dart';
import '../model/quiz_round.dart';

const String quizTitle = 'Quiz';
const String quizMeLabel = 'Quiz me';
const String pickOneLabel = 'Pick one';
const String myShelfLabel = 'My shelf';
const String tickShelfHint = "Tick what you've read on your shelf";
const String nextLabel = 'Next';
const String finishLabel = 'Finish';
const String playAgainLabel = 'Play again';
const String backToQuizLabel = 'Back to Quiz';
const String quizQuitTitle = 'Stop playing?';
const String quizKeepPlayingLabel = 'Keep playing';
const String quizStopLabel = 'Stop';
const String tapAnAnswerHint = 'Tap an answer';
const String tryAgainMessage = 'Good try! Have another go.';
const String notThisOneNote = 'Not this one';
const String wellDoneMessage = 'Yes! Well done!';

/// Gives the quiz's screens the arcade role colour, as the arcade menu does
/// for its own content (§4.5).
class QuizTheme extends StatelessWidget {
  const QuizTheme({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: AppTheme.roleScheme(
          AppPalette.of(theme.brightness).arcade,
          theme.brightness,
        ),
      ),
      child: child,
    );
  }
}

/// The glyph for a kind of title.
IconData quizCollectionIcon(QuizCollection collection) => switch (collection) {
  QuizCollection.book => Icons.menu_book,
  QuizCollection.tv => Icons.tv,
  QuizCollection.film => Icons.movie,
  QuizCollection.topic => Icons.public,
};

/// The plural heading for a kind of title.
String quizCollectionLabel(QuizCollection collection) => switch (collection) {
  QuizCollection.book => 'Books',
  QuizCollection.tv => 'TV',
  QuizCollection.film => 'Films',
  QuizCollection.topic => 'Topics',
};

/// The tick-everything button for a series of [collection].
String quizAllLabel(QuizCollection collection) => switch (collection) {
  QuizCollection.book => "I've read them all",
  QuizCollection.tv || QuizCollection.film => "I've watched them all",
  QuizCollection.topic => 'Quiz me on them all',
};

/// A series' colour. The pack format has none, so it is borrowed from the
/// avatar swatches by the series' place in the catalog: stable for a build and
/// different for neighbours.
Color quizSeriesColor(
  QuizCatalog catalog,
  QuizSeries series,
  Brightness brightness,
) {
  final swatches = AppPalette.of(brightness).avatarSwatches;
  final index = catalog.series.indexOf(series);
  return swatches[(index < 0 ? 0 : index) % swatches.length];
}

/// Stars for a finished round: 3 for 8-10, 2 for 5-7, 1 below. Never none,
/// because a finished round is not a failure (§1).
int quizStars(int score) => score >= 8 ? 3 : (score >= 5 ? 2 : 1);

/// `7 out of 10`.
String quizScoreLabel(int score) => '$score out of $quizRoundLength';

/// `Best 7 out of 10`.
String quizBestLabel(int best) => 'Best ${quizScoreLabel(best)}';

/// [count] filled stars of three. Never the only carrier of the fact: callers
/// put the score text beside it.
class QuizStars extends StatelessWidget {
  const QuizStars({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Semantics(
      container: true,
      label: '$count of 3 stars',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < count; i++)
              Icon(Icons.star, size: AppIconSizes.large, color: color),
          ],
        ),
      ),
    );
  }
}

/// Shown on the play screen when a round cannot be made.
const String nothingToAskMessage = 'No questions to ask yet';
