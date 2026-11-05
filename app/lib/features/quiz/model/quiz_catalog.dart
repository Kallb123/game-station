// The quiz bank as the rest of the app sees it: immutable values, no Flutter.
//
// Pure Dart on purpose (`PLAN-phase-10-quiz.md` §5): the release filter, the
// ten-question threshold and the shelf order are all rules a child's trust in
// the quiz rests on, so they live where a plain `test()` runs them in
// milliseconds. Only reading bytes out of the asset bundle needs Flutter, and
// that stays in `data/quiz_catalog_loader.dart`.

/// A title is offered only with this many loaded questions: one round
/// (`PLAN-phase-10-quiz.md` §1). One constant so a test can pin it.
const int minQuestionsPerTitle = 10;

/// Longest question, in characters of the trimmed text (§1, §4.3).
const int maxQuestionLength = 100;

/// Longest answer, right or wrong, in characters of the trimmed text (§1).
const int maxAnswerLength = 30;

/// The only pack and index `format` this code reads (§4.2).
const int quizPackFormat = 1;

/// Wrong answers every question carries; a round shows two of them (§4.2).
const int wrongAnswerCount = 3;

/// What kind of thing a series is. Sets the tick's word and the icon (§4.1).
enum QuizCollection { book, tv, film, topic }

/// Which directory a pack lives in, and so which builds carry it (§4.9).
enum QuizAudience { store, private }

/// One multiple-choice question.
class QuizQuestion {
  /// Creates a question; [wrong] is copied so the value stays immutable.
  QuizQuestion({
    required this.id,
    required this.level,
    required this.checked,
    required this.q,
    required this.a,
    required List<String> wrong,
    required this.source,
  }) : wrong = List.unmodifiable(wrong);

  /// `<title id>.<three digits>`, unique across the bank and never reused.
  final String id;

  /// 1 for a child who has had the book read to them, 2 for a close read.
  final int level;

  /// True only once a person has verified question, answer and every wrong
  /// answer against the source (§4.2).
  final bool checked;

  /// The question text.
  final String q;

  /// The right answer.
  final String a;

  /// Exactly [wrongAnswerCount] wrong answers.
  final List<String> wrong;

  /// Where the answer is found, for the checker; never shown to a child.
  final String source;
}

/// What a child ticks and picks, and what a question belongs to (§4.1).
class QuizTitle {
  /// Creates a title; [questions] is copied so the value stays immutable.
  QuizTitle({
    required this.id,
    required this.name,
    required List<QuizQuestion> questions,
  }) : questions = List.unmodifiable(questions);

  /// `<series>.<slug>`, frozen once shipped.
  final String id;

  /// The name shown on the shelf.
  final String name;

  /// Questions in file order.
  final List<QuizQuestion> questions;

  /// A copy holding only the questions that pass [keep].
  QuizTitle where(bool Function(QuizQuestion) keep) =>
      QuizTitle(id: id, name: name, questions: questions.where(keep).toList());
}

/// One pack file: a book series, a show, a group of films or a topic.
class QuizSeries {
  /// Creates a series; [titles] is copied so the value stays immutable.
  QuizSeries({
    required this.id,
    required this.name,
    required this.collection,
    required this.audience,
    required List<QuizTitle> titles,
  }) : titles = List.unmodifiable(titles);

  /// The pack's file name without `.json`.
  final String id;

  /// The name shown on the shelf.
  final String name;

  /// What kind of thing this is.
  final QuizCollection collection;

  /// The directory the pack came from.
  final QuizAudience audience;

  /// Titles in reading order.
  final List<QuizTitle> titles;
}

/// One directory's `index.json`: which packs it lists, in shelf order, and
/// which titles are withdrawn (§4.1, §4.2).
class QuizIndex {
  /// Creates an index; both lists are copied.
  QuizIndex({
    required List<String> series,
    required List<String> withdrawnTitles,
  }) : series = List.unmodifiable(series),
       withdrawnTitles = List.unmodifiable(withdrawnTitles);

  /// Series ids in shelf order.
  final List<String> series;

  /// Title ids that stay in saves but are not shown.
  final List<String> withdrawnTitles;
}

/// Every loaded series, in shelf order, and the rules for what is offered.
class QuizCatalog {
  /// Creates a catalog from [series] already in shelf order: store series
  /// first, then private, each in its index's order (§4.2).
  QuizCatalog({
    required List<QuizSeries> series,
    Set<String> withdrawnTitles = const {},
  }) : series = List.unmodifiable(series),
       withdrawnTitles = Set.unmodifiable(withdrawnTitles);

  /// A catalog with nothing in it; what a failed load yields.
  QuizCatalog.empty() : this(series: const []);

  /// Series in shelf order.
  final List<QuizSeries> series;

  /// Title ids withdrawn by either index.
  final Set<String> withdrawnTitles;

  /// Titles a child can see: not withdrawn and with at least
  /// [minQuestionsPerTitle] questions, in shelf order.
  ///
  /// The count is of loaded questions, so after [withCheckedOnly] it is a
  /// count of checked ones, which is the whole point of the threshold (§1).
  List<QuizTitle> get offeredTitles => [
    for (final s in series)
      for (final t in s.titles)
        if (!withdrawnTitles.contains(t.id) &&
            t.questions.length >= minQuestionsPerTitle)
          t,
  ];

  /// The title with [id], withdrawn or not, or null.
  QuizTitle? titleById(String id) {
    for (final s in series) {
      for (final t in s.titles) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  /// The series that holds the title [titleId], or null.
  QuizSeries? seriesOfTitle(String titleId) {
    for (final s in series) {
      for (final t in s.titles) {
        if (t.id == titleId) return s;
      }
    }
    return null;
  }

  /// A copy without any unchecked question: the release-build filter, here
  /// rather than in the loader so it is tested without a bundle (§4.2).
  QuizCatalog withCheckedOnly() => QuizCatalog(
    series: [
      for (final s in series)
        QuizSeries(
          id: s.id,
          name: s.name,
          collection: s.collection,
          audience: s.audience,
          titles: [for (final t in s.titles) t.where((q) => q.checked)],
        ),
    ],
    withdrawnTitles: withdrawnTitles,
  );
}
