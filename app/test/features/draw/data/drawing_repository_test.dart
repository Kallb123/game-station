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

  // The three calls a players-file transfer needs (`PLAN-transfer.md` §4).
  group('for transfer', () {
    test(
      'deleteAllFor removes the folder and leaves other profiles alone',
      () async {
        await repository.save('p1', _drawing('d1'));
        await repository.save('p2', _drawing('d1'));

        await repository.deleteAllFor('p1');

        expect(Directory('${root.path}/drawings/p1').existsSync(), isFalse);
        expect(await repository.load('p2', 'd1'), isNotNull);
        expect(repository.profileBytes('p1'), 0);
      },
    );

    test('deleteAllFor does nothing when there is no folder', () async {
      await repository.deleteAllFor('nobody');
    });

    test('readAllRaw returns each file\'s text by drawing id', () async {
      await repository.save('p1', _drawing('d1'));
      await repository.save('p1', _drawing('d2'));

      final raw = await repository.readAllRaw('p1');

      expect(raw.keys.toSet(), {'d1', 'd2'});
      expect(raw['d1'], encodeDrawing(_drawing('d1')));
    });

    test('readAllRaw is empty for a profile with no folder', () async {
      expect(await repository.readAllRaw('nobody'), isEmpty);
    });

    test('readAllRaw leaves out .tmp files and unreadable ones', () async {
      await repository.save('p1', _drawing('d1'));
      File('${root.path}/drawings/p1/d2.json.tmp').writeAsStringSync('{');
      File('${root.path}/drawings/p1/d3.json').writeAsBytesSync([0xff, 0xfe]);
      File('${root.path}/drawings/p1/notes.txt').writeAsStringSync('hi');
      Directory('${root.path}/drawings/p1/d4.json').createSync();

      expect((await repository.readAllRaw('p1')).keys, ['d1']);
    });

    test('readAllRaw returns text that is not a drawing, undecoded', () async {
      await repository.writeRaw('p1', 'd1', 'not json');

      expect(await repository.readAllRaw('p1'), {'d1': 'not json'});
    });

    test('writeRaw creates the folder and writes atomically', () async {
      final text = encodeDrawing(_drawing('d1'));

      await repository.writeRaw('p1', 'd1', text);

      expect(await repository.load('p1', 'd1'), _drawing('d1'));
      expect(
        File('${root.path}/drawings/p1/d1.json.tmp').existsSync(),
        isFalse,
      );
    });

    test('writeRaw replaces what was there', () async {
      await repository.writeRaw('p1', 'd1', 'old');
      await repository.writeRaw('p1', 'd1', 'new');

      expect(await repository.readAllRaw('p1'), {'d1': 'new'});
    });
  });

  // Staging: an import builds a profile's drawings beside the live folder and
  // swaps them in only once every write has succeeded (`PLAN-transfer.md` §3.2).
  group('staging', () {
    test('staged files are invisible to every live read', () async {
      await repository.save('p1', _drawing('d1'));
      final bytes = repository.profileBytes('p1');

      await repository.startStaging('p1');
      await repository.writeRawStaged(
        'p1',
        'd2',
        encodeDrawing(_drawing('d2')),
      );

      expect((await repository.readAllRaw('p1')).keys, ['d1']);
      expect((await repository.listDecodable('p1')).map((d) => d.id), ['d1']);
      expect(repository.profileBytes('p1'), bytes);
    });

    test('commit replaces the live folder with the staged one', () async {
      await repository.save('p1', _drawing('old'));
      await repository.startStaging('p1');
      await repository.writeRawStaged(
        'p1',
        'd2',
        encodeDrawing(_drawing('d2')),
      );

      await repository.commitStaged('p1');

      expect((await repository.readAllRaw('p1')).keys, ['d2']);
      expect(
        Directory('${root.path}/drawings/p1.incoming').existsSync(),
        isFalse,
      );
    });

    test(
      'committing an empty staging folder leaves an empty profile',
      () async {
        await repository.save('p1', _drawing('old'));
        await repository.startStaging('p1');

        await repository.commitStaged('p1');

        expect(await repository.readAllRaw('p1'), isEmpty);
        expect(repository.profileBytes('p1'), 0);
      },
    );

    test('discard removes only the staging folder', () async {
      await repository.save('p1', _drawing('d1'));
      await repository.startStaging('p1');
      await repository.writeRawStaged('p1', 'd2', 'x');

      await repository.discardStaged('p1');
      await repository.discardStaged('p1'); // Twice is fine.

      expect(
        Directory('${root.path}/drawings/p1.incoming').existsSync(),
        isFalse,
      );
      expect((await repository.readAllRaw('p1')).keys, ['d1']);
    });

    test('startStaging clears what a crashed attempt left', () async {
      File('${root.path}/drawings/p1.incoming/stale.json')
        ..createSync(recursive: true)
        ..writeAsStringSync('{}');

      await repository.startStaging('p1');
      await repository.commitStaged('p1');

      expect(await repository.readAllRaw('p1'), isEmpty);
    });
  });
}
