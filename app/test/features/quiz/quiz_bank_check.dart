// The bank-wide half of the content test (`PLAN-phase-10-quiz.md` §4.3).
//
// `parseQuizPack` validates one pack; the rules here are the ones that need
// the whole directory tree: what may sit in it, what each index lists, and ids
// that must be unique across both audiences. It takes the bank's root as an
// argument so the same function checks the real `assets/quiz` and each broken
// fixture, which is what proves every rule can actually fail (`AGENTS.md`: a
// guard needs its own test).

import 'dart:convert';
import 'dart:io';

import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';
import 'package:zibo_games/features/quiz/model/quiz_pack.dart';

const _audienceDirs = ['store', 'private'];

/// Every problem in the bank rooted at [quizRoot]; empty when it is sound.
List<String> checkQuizBank(Directory quizRoot) {
  final problems = <String>[];
  if (!quizRoot.existsSync()) {
    return ['${quizRoot.path}: directory does not exist'];
  }

  for (final entity in quizRoot.listSync()) {
    final name = _basename(entity.path);
    final isAudienceDir = entity is Directory && _audienceDirs.contains(name);
    if (!isAudienceDir) {
      problems.add('unexpected entry in the bank root: $name');
    }
  }

  final seriesByAudience = <String, List<String>>{};
  final withdrawn = <String>[];
  // id -> file that first declared it, across both directories.
  final titleOwner = <String, String>{};
  final questionOwner = <String, String>{};

  for (final audienceName in _audienceDirs) {
    final dir = Directory('${quizRoot.path}/$audienceName');
    if (!dir.existsSync()) {
      problems.add('$audienceName/: directory is missing');
      continue;
    }
    final indexFile = File('${dir.path}/index.json');
    if (!indexFile.existsSync()) {
      problems.add('$audienceName/index.json: missing');
      continue;
    }
    final QuizIndex index;
    try {
      index = parseQuizIndex(indexFile.readAsStringSync());
    } on QuizFormatException catch (e) {
      problems.addAll(e.problems.map((p) => '$audienceName/index.json: $p'));
      continue;
    }
    seriesByAudience[audienceName] = index.series;
    withdrawn.addAll(index.withdrawnTitles);

    final listed = index.series.map((s) => '$s.json').toSet();
    final present = <String>{};
    for (final entity in dir.listSync()) {
      final name = _basename(entity.path);
      if (entity is! File) {
        problems.add('$audienceName/$name: only files belong here');
      } else if (!name.endsWith('.json')) {
        problems.add('$audienceName/$name: not a .json file');
      } else if (name != 'index.json') {
        present.add(name);
        if (!listed.contains(name)) {
          problems.add('$audienceName/$name: not listed in index.json');
        }
      }
    }
    for (final series in index.series) {
      final file = '$series.json';
      final path = '$audienceName/$file';
      if (!present.contains(file)) {
        problems.add('$path: listed in index.json but there is no file');
        continue;
      }
      final text = File('${dir.path}/$file').readAsStringSync();
      try {
        parseQuizPack(
          text,
          seriesId: series,
          audience: QuizAudience.values.byName(audienceName),
        );
      } on QuizFormatException catch (e) {
        problems.addAll(e.problems.map((p) => '$path: $p'));
      }
      // Ids are read leniently, so a pack that fails another rule still has
      // its ids compared. Duplicates inside one pack were already reported by
      // the parser; only a clash with an earlier pack is new here.
      final ids = _idsIn(text);
      for (final id in ids.titles) {
        final other = titleOwner[id];
        if (other != null && other != path) {
          problems.add('$path: duplicate title id "$id", also in $other');
        }
        titleOwner.putIfAbsent(id, () => path);
      }
      for (final id in ids.questions) {
        final other = questionOwner[id];
        if (other != null && other != path) {
          problems.add('$path: duplicate question id "$id", also in $other');
        }
        questionOwner.putIfAbsent(id, () => path);
      }
    }
  }

  final store = seriesByAudience['store'] ?? const <String>[];
  for (final series in seriesByAudience['private'] ?? const <String>[]) {
    if (store.contains(series)) {
      problems.add('series "$series" is in both store/ and private/');
    }
  }

  for (final id in withdrawn) {
    if (!titleOwner.containsKey(id)) {
      problems.add('withdrawnTitles: "$id" names no title in the bank');
    }
  }
  return problems;
}

/// The bank's coverage as a markdown table, for pasting into a content pull
/// request. Packs that do not parse are left out; [checkQuizBank] reports them.
String quizCoverageTable(Directory quizRoot) {
  final out = StringBuffer()
    ..writeln('| audience | collection | series | title | checked | total |')
    ..writeln('|---|---|---|---|---:|---:|');
  for (final audienceName in _audienceDirs) {
    final indexFile = File('${quizRoot.path}/$audienceName/index.json');
    if (!indexFile.existsSync()) continue;
    final QuizIndex index;
    try {
      index = parseQuizIndex(indexFile.readAsStringSync());
    } on QuizFormatException {
      continue;
    }
    for (final series in index.series) {
      final file = File('${quizRoot.path}/$audienceName/$series.json');
      if (!file.existsSync()) continue;
      final QuizSeries pack;
      try {
        pack = parseQuizPack(
          file.readAsStringSync(),
          seriesId: series,
          audience: QuizAudience.values.byName(audienceName),
        );
      } on QuizFormatException {
        continue;
      }
      for (final title in pack.titles) {
        final checked = title.questions.where((q) => q.checked).length;
        out.writeln(
          '| $audienceName | ${pack.collection.name} | ${pack.id} | '
          '${title.name} | $checked | ${title.questions.length} |',
        );
      }
    }
  }
  return out.toString();
}

({List<String> titles, List<String> questions}) _idsIn(String text) {
  final titles = <String>[];
  final questions = <String>[];
  try {
    final root = jsonDecode(text);
    final rawTitles = root is Map<String, Object?> ? root['titles'] : null;
    if (rawTitles is List<Object?>) {
      for (final t in rawTitles) {
        if (t is! Map<String, Object?>) continue;
        final id = t['id'];
        if (id is String) titles.add(id);
        final qs = t['questions'];
        if (qs is! List<Object?>) continue;
        for (final q in qs) {
          final qid = q is Map<String, Object?> ? q['id'] : null;
          if (qid is String) questions.add(qid);
        }
      }
    }
  } on FormatException {
    // Reported by the parser.
  }
  return (titles: titles, questions: questions);
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
