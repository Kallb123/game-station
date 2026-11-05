// Parsing and validating a quiz pack or index (`PLAN-phase-10-quiz.md` §4.2,
// §4.3).
//
// One validator serves two callers: the loader, which skips a pack that fails
// and logs why, and the content test, which turns every problem into a CI
// failure. Sharing it is the point: a rule that only the test knew would let a
// bad pack through on a device, and a rule only the loader knew would let one
// into `main`. It collects every problem in a pack rather than stopping at the
// first, so one run tells a content author everything to fix.

import 'dart:convert';

import 'quiz_catalog.dart';

/// A pack or index that cannot be used, with every reason found.
class QuizFormatException implements Exception {
  /// Creates an exception; [problems] must not be empty.
  QuizFormatException(List<String> problems)
    : problems = List.unmodifiable(problems);

  /// Human-readable problems, one per line of a test failure.
  final List<String> problems;

  @override
  String toString() => 'QuizFormatException: ${problems.join('; ')}';
}

final RegExp _titleIdShape = RegExp(r'^[a-z0-9-]+\.[a-z0-9-]+$');

// "all of the above", "none of these", and so on: options are shuffled
// (§4.6), so an answer that refers to the other options becomes nonsense.
final RegExp _aggregateAnswer = RegExp(
  r'^(all|none)\s+of\s+(the\s+)?(above|these|them)\b',
);

// "Both" alone or leading ("Both of them", "Both A and B"). A word boundary
// keeps a name like "Bothwell" legal.
final RegExp _bothAnswer = RegExp(r'^both\b');

// An answer naming where an option sits: "the first one", "the last answer",
// "option A", "answer 2", "choice c". Deliberately narrow: it needs the
// ordinal followed by one/option/answer/choice, so "The Last Battle" and "The
// Middle" are fine. A false positive costs a reworded answer; a false
// negative costs a nonsense question once the options are shuffled.
final RegExp _positionalAnswer = RegExp(
  r'^(the\s+)?(first|second|third|1st|2nd|3rd|last|top|middle|bottom|left|right)\s+(one|option|answer|choice)\b'
  r'|^(option|answer|choice)\s+([a-c]|[1-3])\b',
);

/// Parses an `index.json`; throws [QuizFormatException] if it is unusable.
QuizIndex parseQuizIndex(String json) {
  final problems = <String>[];
  final root = _decodeObject(json, problems);
  if (root == null) throw QuizFormatException(problems);

  _checkFormat(root, 'index', problems);
  final series = _stringList(root, 'series', 'index', problems);
  final withdrawn = _stringList(root, 'withdrawnTitles', 'index', problems);
  if (series != null) {
    final seen = <String>{};
    for (final id in series) {
      if (id.trim().isEmpty) {
        problems.add('index: a series id is empty');
      } else if (!seen.add(id)) {
        problems.add('index: duplicate series id "$id"');
      }
    }
  }
  if (problems.isNotEmpty) throw QuizFormatException(problems);
  return QuizIndex(series: series!, withdrawnTitles: withdrawn!);
}

/// Parses one pack file; throws [QuizFormatException] listing every problem.
///
/// [seriesId] is the file name without `.json` and the pack's `series` must
/// equal it, so a copied pack cannot silently shadow another (§4.3).
QuizSeries parseQuizPack(
  String json, {
  required String seriesId,
  required QuizAudience audience,
}) {
  final problems = <String>[];

  // The bank has no URLs at all (§1); `check_offline.dart` scans `app/lib` and
  // would never see one here.
  if (json.contains('://')) {
    problems.add("pack contains '://'; no URLs belong in quiz text");
  }

  final root = _decodeObject(json, problems);
  if (root == null) throw QuizFormatException(problems);

  _checkFormat(root, 'pack', problems);

  final series = _string(root, 'series', 'pack', problems);
  if (series != null && series != seriesId) {
    problems.add('pack: series "$series" does not match file name "$seriesId"');
  }
  final name = _string(root, 'name', 'pack', problems);
  if (name != null && name.trim().isEmpty) {
    problems.add('pack: name is empty');
  }

  QuizCollection? collection;
  final collectionName = _string(root, 'collection', 'pack', problems);
  if (collectionName != null) {
    for (final c in QuizCollection.values) {
      if (c.name == collectionName) collection = c;
    }
    if (collection == null) {
      problems.add(
        'pack: collection "$collectionName" is not one of '
        '${QuizCollection.values.map((c) => c.name).join(', ')}',
      );
    }
  }

  final titles = <QuizTitle>[];
  final titleIds = <String>{};
  final questionIds = <String>{};
  final rawTitles = _list(root, 'titles', 'pack', problems);
  if (rawTitles != null) {
    for (var i = 0; i < rawTitles.length; i++) {
      final title = _parseTitle(
        rawTitles[i],
        where: 'titles[$i]',
        seriesPrefix: series ?? seriesId,
        titleIds: titleIds,
        questionIds: questionIds,
        problems: problems,
      );
      if (title != null) titles.add(title);
    }
  }

  if (problems.isNotEmpty) throw QuizFormatException(problems);
  return QuizSeries(
    id: series!,
    name: name!,
    collection: collection!,
    audience: audience,
    titles: titles,
  );
}

QuizTitle? _parseTitle(
  Object? raw, {
  required String where,
  required String seriesPrefix,
  required Set<String> titleIds,
  required Set<String> questionIds,
  required List<String> problems,
}) {
  if (raw is! Map<String, Object?>) {
    problems.add('$where: must be an object');
    return null;
  }
  final id = _string(raw, 'id', where, problems);
  final label = id == null ? where : '$where ($id)';
  final name = _string(raw, 'name', label, problems);
  if (name != null && name.trim().isEmpty) {
    problems.add('$label: name is empty');
  }
  if (id != null) {
    if (!_titleIdShape.hasMatch(id)) {
      problems.add('$label: title id does not match ${_titleIdShape.pattern}');
    } else if (!id.startsWith('$seriesPrefix.')) {
      problems.add('$label: title id must start with "$seriesPrefix."');
    }
    if (!titleIds.add(id)) problems.add('$label: duplicate title id "$id"');
  }

  final questions = <QuizQuestion>[];
  final rawQuestions = _list(raw, 'questions', label, problems);
  if (rawQuestions != null) {
    for (var i = 0; i < rawQuestions.length; i++) {
      final question = _parseQuestion(
        rawQuestions[i],
        where: '$label questions[$i]',
        titleId: id,
        questionIds: questionIds,
        problems: problems,
      );
      if (question != null) questions.add(question);
    }
  }
  if (id == null || name == null || rawQuestions == null) return null;
  return QuizTitle(id: id, name: name, questions: questions);
}

QuizQuestion? _parseQuestion(
  Object? raw, {
  required String where,
  required String? titleId,
  required Set<String> questionIds,
  required List<String> problems,
}) {
  if (raw is! Map<String, Object?>) {
    problems.add('$where: must be an object');
    return null;
  }
  final id = _string(raw, 'id', where, problems);
  final label = id == null ? where : '$where ($id)';
  if (id != null) {
    if (titleId != null &&
        !RegExp('^${RegExp.escape(titleId)}\\.\\d{3}\$').hasMatch(id)) {
      problems.add(
        '$label: question id must be "$titleId." and exactly three digits',
      );
    }
    if (!questionIds.add(id)) {
      problems.add('$label: duplicate question id "$id"');
    }
  }

  final level = raw['level'];
  if (level == null) {
    problems.add('$label: missing field "level"');
  } else if (level is! int) {
    problems.add('$label: field "level" must be an integer');
  } else if (level != 1 && level != 2) {
    problems.add('$label: level $level is not 1 or 2');
  }

  final checked = raw['checked'];
  if (checked == null) {
    problems.add('$label: missing field "checked"');
  } else if (checked is! bool) {
    problems.add('$label: field "checked" must be a boolean');
  }

  final q = _string(raw, 'q', label, problems);
  if (q != null) _checkText(q, 'q', maxQuestionLength, label, problems);

  final a = _string(raw, 'a', label, problems);
  if (a != null) _checkText(a, 'a', maxAnswerLength, label, problems);

  final source = _string(raw, 'source', label, problems);
  if (source != null && source.trim().isEmpty) {
    problems.add('$label: source is empty');
  }

  final wrong = _stringList(raw, 'wrong', label, problems);
  if (wrong != null) {
    if (wrong.length != wrongAnswerCount) {
      problems.add(
        '$label: wrong must hold exactly $wrongAnswerCount answers, '
        'not ${wrong.length}',
      );
    }
    for (var i = 0; i < wrong.length; i++) {
      _checkText(wrong[i], 'wrong[$i]', maxAnswerLength, label, problems);
    }
  }

  if (a != null && wrong != null) {
    final answers = [a, ...wrong];
    final folded = <String>{};
    for (final answer in answers) {
      if (!folded.add(answer.trim().toLowerCase())) {
        problems.add('$label: duplicate answers, "${answer.trim()}" repeats');
      }
      final text = answer.trim().toLowerCase();
      if (_aggregateAnswer.hasMatch(text)) {
        problems.add('$label: answer "$answer" is an all/none of the above');
      } else if (_bothAnswer.hasMatch(text)) {
        problems.add('$label: answer "$answer" begins with "both"');
      } else if (_positionalAnswer.hasMatch(text)) {
        problems.add('$label: answer "$answer" names an option position');
      }
    }
  }

  if (id == null ||
      level is! int ||
      checked is! bool ||
      q == null ||
      a == null ||
      source == null ||
      wrong == null) {
    return null;
  }
  return QuizQuestion(
    id: id,
    level: level,
    checked: checked,
    q: q,
    a: a,
    wrong: wrong,
    source: source,
  );
}

// Length is measured on the trimmed string in UTF-16 code units. That
// over-counts an emoji or a rare character, which only errs towards shorter
// text, the safe side of a cap that exists to protect the layout.
void _checkText(
  String text,
  String field,
  int max,
  String label,
  List<String> problems,
) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    problems.add('$label: $field is empty');
  } else if (trimmed.length > max) {
    problems.add(
      '$label: $field is ${trimmed.length} characters, longer than $max',
    );
  }
}

Map<String, Object?>? _decodeObject(String json, List<String> problems) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    problems.add('not valid JSON: ${e.message}');
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    problems.add('top level must be a JSON object');
    return null;
  }
  return decoded;
}

void _checkFormat(
  Map<String, Object?> map,
  String where,
  List<String> problems,
) {
  final format = map['format'];
  if (format == null) {
    problems.add('$where: missing field "format"');
  } else if (format != quizPackFormat) {
    problems.add(
      '$where: unsupported format $format, expected $quizPackFormat',
    );
  }
}

String? _string(
  Map<String, Object?> map,
  String key,
  String where,
  List<String> problems,
) {
  final value = map[key];
  if (value == null) {
    problems.add('$where: missing field "$key"');
    return null;
  }
  if (value is! String) {
    problems.add('$where: field "$key" must be a string');
    return null;
  }
  return value;
}

List<Object?>? _list(
  Map<String, Object?> map,
  String key,
  String where,
  List<String> problems,
) {
  final value = map[key];
  if (value == null) {
    problems.add('$where: missing field "$key"');
    return null;
  }
  if (value is! List<Object?>) {
    problems.add('$where: field "$key" must be a list');
    return null;
  }
  return value;
}

List<String>? _stringList(
  Map<String, Object?> map,
  String key,
  String where,
  List<String> problems,
) {
  final list = _list(map, key, where, problems);
  if (list == null) return null;
  final out = <String>[];
  var ok = true;
  for (final item in list) {
    if (item is String) {
      out.add(item);
    } else {
      ok = false;
    }
  }
  if (!ok) {
    problems.add('$where: field "$key" must hold only strings');
    return null;
  }
  return out;
}
