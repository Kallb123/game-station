// The loader's contract (`PLAN-phase-10-quiz.md` §4.2, §6 PR 2): the release
// filter and ten-question threshold, and that a bad pack, a missing private
// directory or a broken index never throws to the caller (`AGENTS.md`).
//
// A fake in-memory bundle stands in for `rootBundle`, so each case builds
// exactly the bank it needs. The last test loads the real bank from disk, which
// is what proves the shipped packs are ones the loader accepts rather than ones
// it silently skips.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/quiz/data/quiz_catalog_loader.dart';
import 'package:zibo_games/features/quiz/model/quiz_catalog.dart';

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

String _index(List<String> series, [List<String> withdrawn = const []]) =>
    jsonEncode({'format': 1, 'series': series, 'withdrawnTitles': withdrawn});

/// A pack of [series] with one title per entry of [titles] (title slug ->
/// number of checked questions, then number of unchecked ones).
String _pack(String series, Map<String, (int, int)> titles) => jsonEncode({
  'format': 1,
  'series': series,
  'name': series,
  'collection': 'book',
  'titles': [
    for (final e in titles.entries)
      {
        'id': '$series.${e.key}',
        'name': e.key,
        'questions': [
          for (var n = 1; n <= e.value.$1 + e.value.$2; n++)
            {
              'id': '$series.${e.key}.${n.toString().padLeft(3, '0')}',
              'level': 1,
              'checked': n <= e.value.$1,
              'q': 'Question $n?',
              'a': 'Right',
              'wrong': ['One', 'Two', 'Three'],
              'source': 'Somewhere',
            },
        ],
      },
  ],
});

Future<QuizCatalog> _load(
  Map<String, String> files, {
  bool checkedOnly = true,
}) => QuizCatalogLoader(
  bundle: _FakeBundle(files),
  checkedOnly: checkedOnly,
).load();

List<String> _titleIds(QuizCatalog c) => [
  for (final t in c.offeredTitles) t.id,
];

void main() {
  final storeA = {
    'assets/quiz/store/index.json': _index(['a']),
    'assets/quiz/store/a.json': _pack('a', {'full': (12, 0)}),
  };

  group('release filter', () {
    final files = {
      'assets/quiz/store/index.json': _index(['a']),
      'assets/quiz/store/a.json': _pack('a', {'ten': (10, 5), 'nine': (9, 5)}),
    };

    test(
      'checkedOnly drops unchecked questions and hides nine checked',
      () async {
        final catalog = await _load(files);
        expect(_titleIds(catalog), ['a.ten']);
        final ten = catalog.titleById('a.ten')!;
        expect(ten.questions, hasLength(10));
        expect(ten.questions.every((q) => q.checked), isTrue);
        expect(catalog.titleById('a.nine')!.questions, hasLength(9));
      },
    );

    test('without checkedOnly, unchecked questions are kept', () async {
      final catalog = await _load(files, checkedOnly: false);
      expect(catalog.titleById('a.ten')!.questions, hasLength(15));
      expect(_titleIds(catalog), ['a.ten', 'a.nine']);
    });

    test('offeredTitles never returns a title below the threshold', () async {
      for (final checkedOnly in [true, false]) {
        final catalog = await _load(files, checkedOnly: checkedOnly);
        for (final t in catalog.offeredTitles) {
          expect(
            t.questions.length,
            greaterThanOrEqualTo(minQuestionsPerTitle),
          );
        }
      }
    });
  });

  group('failures never throw', () {
    test('a pack with a syntax error is skipped, the others load', () async {
      final catalog = await _load({
        'assets/quiz/store/index.json': _index(['a', 'broken', 'c']),
        'assets/quiz/store/a.json': _pack('a', {'t': (10, 0)}),
        'assets/quiz/store/broken.json': '{"format": 1,',
        'assets/quiz/store/c.json': _pack('c', {'t': (10, 0)}),
      });
      expect(_titleIds(catalog), ['a.t', 'c.t']);
    });

    test('a pack that fails validation is skipped', () async {
      final bad =
          jsonDecode(_pack('bad', {'t': (10, 0)})) as Map<String, Object?>
            ..['format'] = 2;
      final catalog = await _load({
        'assets/quiz/store/index.json': _index(['bad', 'a']),
        'assets/quiz/store/bad.json': jsonEncode(bad),
        'assets/quiz/store/a.json': _pack('a', {'t': (10, 0)}),
      });
      expect(_titleIds(catalog), ['a.t']);
    });

    test('a listed pack with no file is skipped', () async {
      final catalog = await _load({
        'assets/quiz/store/index.json': _index(['ghost', 'a']),
        'assets/quiz/store/a.json': _pack('a', {'t': (10, 0)}),
      });
      expect(_titleIds(catalog), ['a.t']);
    });

    test('no private index gives a store-only catalog', () async {
      final catalog = await _load(storeA);
      expect(_titleIds(catalog), ['a.full']);
      expect(catalog.series.map((s) => s.audience), [QuizAudience.store]);
    });

    test('a broken store index gives an empty store side', () async {
      for (final broken in [
        'not json',
        _index(['a']).replaceAll('1', '9'),
      ]) {
        final catalog = await _load({
          'assets/quiz/store/index.json': broken,
          'assets/quiz/store/a.json': _pack('a', {'t': (10, 0)}),
          'assets/quiz/private/index.json': _index(['p']),
          'assets/quiz/private/p.json': _pack('p', {'t': (10, 0)}),
        });
        expect(_titleIds(catalog), ['p.t']);
      }
    });

    test('an empty bundle gives an empty catalog', () async {
      final catalog = await _load({});
      expect(catalog.series, isEmpty);
      expect(catalog.offeredTitles, isEmpty);
    });

    test('a series already loaded from store is skipped in private', () async {
      // A title id can only repeat through a repeated series id, because a
      // title id must start with its series, so this is the case that matters.
      final catalog = await _load({
        'assets/quiz/store/index.json': _index(['a']),
        'assets/quiz/store/a.json': _pack('a', {'t': (10, 0)}),
        'assets/quiz/private/index.json': _index(['a', 'b']),
        'assets/quiz/private/a.json': _pack('a', {'other': (10, 0)}),
        'assets/quiz/private/b.json': _pack('b', {'t': (10, 0)}),
      });
      expect(_titleIds(catalog), ['a.t', 'b.t']);
      expect(catalog.series.map((s) => s.audience), [
        QuizAudience.store,
        QuizAudience.private,
      ]);
    });
  });

  group('shelf order and withdrawal', () {
    test('store series come before private, each in index order', () async {
      final catalog = await _load({
        'assets/quiz/store/index.json': _index(['s2', 's1']),
        'assets/quiz/store/s1.json': _pack('s1', {'t': (10, 0)}),
        'assets/quiz/store/s2.json': _pack('s2', {'t': (10, 0)}),
        'assets/quiz/private/index.json': _index(['p2', 'p1']),
        'assets/quiz/private/p1.json': _pack('p1', {'t': (10, 0)}),
        'assets/quiz/private/p2.json': _pack('p2', {'t': (10, 0)}),
      });
      expect(catalog.series.map((s) => s.id), ['s2', 's1', 'p2', 'p1']);
      expect(_titleIds(catalog), ['s2.t', 's1.t', 'p2.t', 'p1.t']);
    });

    test('withdrawn titles from either index are not offered', () async {
      final catalog = await _load({
        'assets/quiz/store/index.json': _index(['s'], ['s.gone']),
        'assets/quiz/store/s.json': _pack('s', {
          'gone': (10, 0),
          'kept': (10, 0),
        }),
        'assets/quiz/private/index.json': _index(['p'], ['p.gone']),
        'assets/quiz/private/p.json': _pack('p', {
          'gone': (10, 0),
          'kept': (10, 0),
        }),
      });
      expect(_titleIds(catalog), ['s.kept', 'p.kept']);
      expect(catalog.withdrawnTitles, {'s.gone', 'p.gone'});
      // Withdrawn is hidden, not deleted: the title is still there to restore.
      expect(catalog.titleById('s.gone'), isNotNull);
      expect(catalog.seriesOfTitle('p.gone')!.id, 'p');
    });
  });

  test('the real bank loads with no pack skipped', () async {
    final files = <String, String>{};
    for (final audience in ['store', 'private']) {
      final dir = Directory('assets/quiz/$audience');
      for (final f in dir.listSync().whereType<File>()) {
        final name = f.path.split(Platform.pathSeparator).last;
        files['assets/quiz/$audience/$name'] = f.readAsStringSync();
      }
    }
    final listed = <String>[];
    for (final audience in ['store', 'private']) {
      final index =
          jsonDecode(files['assets/quiz/$audience/index.json']!)
              as Map<String, Object?>;
      listed.addAll([
        for (final s in index['series']! as List<Object?>) '$audience/$s',
      ]);
    }

    final catalog = await _load(files, checkedOnly: false);

    final loaded = [
      for (final s in catalog.series) '${s.audience.name}/${s.id}',
    ];
    expect(loaded, listed);
  });
}
