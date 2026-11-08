// The store packs against the release filter (`PLAN-phase-10-quiz.md` §6 PR 12,
// §4.5): over the real `assets/quiz/store/` directory, a catalog with every
// question unchecked offers nothing and the Arcade menu shows no Quiz card;
// with ten of one title's questions checked it offers that title and the card
// appears.
//
// The checked flags are rewritten in memory, so this does not depend on how far
// the owner has got through checking the shipped questions; what it pins is that
// those packs, as a store build carries them, are shaped so the filter and the
// ten-question threshold act on them. No private file is read: a store build
// carries none.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/arcade/arcade_menu_screen.dart';
import 'package:zibo_games/features/quiz/data/quiz_catalog_loader.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';

import '../arcade/arcade_menu_screen_test.dart' show pumpMenu;

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this.files);

  final Map<String, String> files;

  @override
  Future<ByteData> load(String key) async {
    final text = files[key];
    if (text == null) throw FlutterError('Unable to load asset: $key');
    final bytes = Uint8List.fromList(utf8.encode(text));
    return ByteData.sublistView(bytes);
  }
}

const _storeDir = 'assets/quiz/store';

/// Every file of the store directory, as the bundle would serve it.
Map<String, String> _readStore() => {
  for (final f in Directory(_storeDir).listSync().whereType<File>())
    '$_storeDir/${f.path.split(Platform.pathSeparator).last}': f
        .readAsStringSync(),
};

/// [files] with every question's `checked` forced, except that the first
/// [checkedCount] questions of [checkedTitle] are set true when it is given.
Map<String, String> _withChecked(
  Map<String, String> files, {
  String? checkedTitle,
  int checkedCount = minQuestionsPerTitle,
}) {
  final out = Map<String, String>.of(files);
  for (final entry in files.entries) {
    if (entry.key.endsWith('/index.json')) continue;
    final pack = jsonDecode(entry.value) as Map<String, Object?>;
    for (final title in pack['titles']! as List<Object?>) {
      final t = title as Map<String, Object?>;
      final questions = t['questions']! as List<Object?>;
      for (var i = 0; i < questions.length; i++) {
        (questions[i]! as Map<String, Object?>)['checked'] =
            t['id'] == checkedTitle && i < checkedCount;
      }
    }
    out[entry.key] = jsonEncode(pack);
  }
  return out;
}

Future<QuizCatalog> _load(Map<String, String> files) =>
    QuizCatalogLoader(bundle: _FakeBundle(files), checkedOnly: true).load();

void main() {
  final files = _readStore();
  final index =
      jsonDecode(files['$_storeDir/index.json']!) as Map<String, Object?>;
  final listed = (index['series']! as List<Object?>).cast<String>();

  // Read from the index rather than named, so it holds if the owner reorders.
  String? firstTitle;
  var firstTitleQuestions = 0;
  if (listed.isNotEmpty) {
    final pack =
        jsonDecode(files['$_storeDir/${listed.first}.json']!)
            as Map<String, Object?>;
    final title =
        (pack['titles']! as List<Object?>).first! as Map<String, Object?>;
    firstTitle = title['id']! as String;
    firstTitleQuestions = (title['questions']! as List<Object?>).length;
  }

  group('store packs under the release filter', () {
    late final QuizCatalog none;
    late final QuizCatalog ten;

    test(
      'the store has a title with the ten questions the threshold needs',
      () {
        expect(listed, isNotEmpty);
        expect(firstTitleQuestions, greaterThanOrEqualTo(minQuestionsPerTitle));
      },
    );

    setUpAll(() async {
      none = await _load(_withChecked(files));
      ten = await _load(_withChecked(files, checkedTitle: firstTitle));
    });

    test('with every question unchecked, nothing is offered', () {
      expect(none.offeredTitles, isEmpty);
    });

    test('with ten of one title checked, only that title is offered', () {
      expect([for (final t in ten.offeredTitles) t.id], [firstTitle]);
    });

    testWidgets('the Arcade menu shows no Quiz card over the unchecked store', (
      tester,
    ) async {
      await pumpMenu(tester, catalog: none);

      expect(find.text(quizCardTitle), findsNothing);
    });

    testWidgets('the Arcade menu shows the Quiz card once ten are checked', (
      tester,
    ) async {
      await pumpMenu(tester, catalog: ten);

      expect(find.text(quizCardTitle), findsOneWidget);
    });
  });
}
