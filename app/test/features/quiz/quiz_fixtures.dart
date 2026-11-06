// Fixture catalogs for the picker and round tests, built in code so no test
// needs the asset bundle (`PLAN-phase-10-quiz.md` §6, PR 5).

import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';

/// A title of [count] questions; [levelOf] gives each question's level
/// (default all 1, so presented order equals draw order). Questions are
/// listed in reverse id order, which the picker must not depend on.
QuizTitle fixtureTitle(String id, int count, {int Function(int n)? levelOf}) =>
    QuizTitle(
      id: id,
      name: id,
      questions: [
        for (var n = count; n >= 1; n--)
          QuizQuestion(
            id: '$id.${n.toString().padLeft(3, '0')}',
            level: levelOf?.call(n) ?? 1,
            checked: true,
            q: 'Q $n of $id',
            a: 'A $n',
            wrong: ['W $n a', 'W $n b', 'W $n c'],
            source: 's',
          ),
      ],
    );

QuizSeries fixtureSeries(String id, List<QuizTitle> titles) => QuizSeries(
  id: id,
  name: id,
  collection: QuizCollection.book,
  audience: QuizAudience.store,
  titles: titles,
);

const narniaId = 'narnia.lion-witch-wardrobe';
const dahlIds = [
  'dahl.matilda',
  'dahl.bfg',
  'dahl.james-giant-peach',
  'dahl.charlie-chocolate-factory',
];

/// One Narnia title and four Dahl titles, 24 questions each.
QuizCatalog fixtureCatalog({
  int count = 24,
  Set<String> withdrawn = const {},
}) => QuizCatalog(
  series: [
    fixtureSeries('narnia', [fixtureTitle(narniaId, count)]),
    fixtureSeries('dahl', [for (final id in dahlIds) fixtureTitle(id, count)]),
  ],
  withdrawnTitles: withdrawn,
);

/// The series part of a title id.
String seriesOf(String titleId) => titleId.split('.').first;
