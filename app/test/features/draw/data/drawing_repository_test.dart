// [DrawingRepository]'s tests, over a real temp directory — the same shape
// as `save_store_test.dart`, because both write through
// `writeFileAtomically` and both have to survive a corrupt file without
// taking anything else down with it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/draw/data/drawing_codec.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';

Drawing _drawing(String id) => Drawing(
  id: id,
  createdAt: DateTime.utc(2026, 8, 11),
  strokes: const [
    Stroke(colorIndex: 1, sizeIndex: 1, points: [Offset(1, 1), Offset(2, 2)]),
  ],
);

void main() {
  late Directory root;
  late DrawingRepository repository;

  setUp(() {
    root = Directory.systemTemp.createTempSync('zibo_games_drawings');
    repository = DrawingRepository(root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a saved drawing is read back as it was written', () async {
    final drawing = _drawing('d1');

    await repository.save('p1', drawing);
    final loaded = await repository.load('p1', 'd1');

    expect(loaded, drawing);
  });

  test('load returns null for a drawing that does not exist', () async {
    expect(await repository.load('p1', 'd9'), isNull);
  });

  test(
    'load returns null for a profile with no drawings folder at all',
    () async {
      expect(await repository.load('nobody', 'd1'), isNull);
    },
  );

  test('a drawing lives under drawings/<profileId>/<id>.json', () async {
    await repository.save('p1', _drawing('d1'));

    expect(File('${root.path}/drawings/p1/d1.json').existsSync(), isTrue);
  });

  test('saving replaces what was there under the same id', () async {
    await repository.save('p1', _drawing('d1'));
    final updated = _drawing('d1').copyWith(
      strokes: const [
        Stroke(colorIndex: 5, sizeIndex: 0, points: [Offset(9, 9)]),
      ],
    );

    await repository.save('p1', updated);

    expect(await repository.load('p1', 'd1'), updated);
  });

  test('two profiles keep separate drawings under the same id', () async {
    await repository.save('p1', _drawing('d1'));
    final other = _drawing('d1').copyWith(
      strokes: const [
        Stroke(colorIndex: 2, sizeIndex: 2, points: [Offset(4, 4)]),
      ],
    );
    await repository.save('p2', other);

    expect(await repository.load('p1', 'd1'), _drawing('d1'));
    expect(await repository.load('p2', 'd1'), other);
  });

  test('delete removes the file; a missing one is not an error', () async {
    await repository.save('p1', _drawing('d1'));

    await repository.delete('p1', 'd1');

    expect(await repository.load('p1', 'd1'), isNull);
    await repository.delete('p1', 'd1'); // does not throw
  });

  group('listDecodable', () {
    test('lists every drawing that decodes', () async {
      await repository.save('p1', _drawing('d1'));
      await repository.save('p1', _drawing('d2'));

      final drawings = await repository.listDecodable('p1');

      expect(drawings, unorderedEquals([_drawing('d1'), _drawing('d2')]));
    });

    test('an empty list for a profile with no drawings', () async {
      expect(await repository.listDecodable('p1'), isEmpty);
    });

    test(
      'a corrupted drawing file is skipped, the rest are still listed',
      () async {
        await repository.save('p1', _drawing('d1'));
        await repository.save('p1', _drawing('d2'));
        File(
          '${root.path}/drawings/p1/d3.json',
        ).writeAsStringSync('{not valid json');

        final drawings = await repository.listDecodable('p1');

        expect(drawings, unorderedEquals([_drawing('d1'), _drawing('d2')]));
      },
    );

    test('a non-JSON file in the folder is ignored', () async {
      await repository.save('p1', _drawing('d1'));
      final dir = Directory('${root.path}/drawings/p1');
      File('${dir.path}/thumb.png').writeAsStringSync('not a drawing');

      final drawings = await repository.listDecodable('p1');

      expect(drawings, [_drawing('d1')]);
    });
  });

  test('encodedSize matches the bytes the codec would write', () {
    final drawing = _drawing('d1');

    expect(
      repository.encodedSize(drawing),
      utf8.encode(encodeDrawing(drawing)).length,
    );
  });

  group('profileBytes', () {
    test('zero for a profile with no drawings folder at all', () {
      expect(repository.profileBytes('p1'), 0);
    });

    test(
      "sums every file actually on disk, not the codec's own estimate",
      () async {
        await repository.save('p1', _drawing('d1'));
        await repository.save('p1', _drawing('d2'));

        final dir = Directory('${root.path}/drawings/p1');
        final onDisk = dir
            .listSync()
            .whereType<File>()
            .map((file) => file.lengthSync())
            .fold(0, (total, length) => total + length);

        expect(repository.profileBytes('p1'), onDisk);
        expect(onDisk, greaterThan(0));
      },
    );

    test('drops to what remains after a delete', () async {
      await repository.save('p1', _drawing('d1'));
      await repository.save('p1', _drawing('d2'));
      final withBoth = repository.profileBytes('p1');

      await repository.delete('p1', 'd1');

      expect(repository.profileBytes('p1'), lessThan(withBoth));
      expect(repository.profileBytes('p1'), greaterThan(0));
    });

    test('two profiles are counted separately', () async {
      await repository.save('p1', _drawing('d1'));
      await repository.save('p2', _drawing('d1'));
      await repository.save('p2', _drawing('d2'));

      expect(
        repository.profileBytes('p2'),
        greaterThan(repository.profileBytes('p1')),
      );
    });
  });
}
