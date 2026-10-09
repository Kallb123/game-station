// The service over real repositories: a `ProgressRepository` on a
// `MemorySaveStore` and a `DrawingRepository` on a temp directory, so the
// codec, the import rules and the files on disk are all the real ones
// (`PLAN-transfer.md` §3.2, §5 part 1).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/progress_repository.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/drawing_codec.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';
import 'package:zibo_games/features/transfer/data/transfer_codec.dart';
import 'package:zibo_games/features/transfer/data/transfer_service.dart';

import '../../../core/storage/save_fixtures.dart';

Drawing _drawing(String id, {double x = 1}) => Drawing(
  id: id,
  createdAt: DateTime.utc(2026, 8, 11, 12),
  strokes: [
    Stroke(colorIndex: 1, sizeIndex: 1, points: [Offset(x, 1), Offset(2, 2)]),
  ],
);

/// A drawings repository whose staged writes can be made to fail.
class _FlakyDrawings extends DrawingRepository {
  _FlakyDrawings(super.root, [this.failOn]);

  /// The profile whose staged writes throw, or null for none.
  String? failOn;

  @override
  Future<void> writeRawStaged(
    String profileId,
    String drawingId,
    String contents,
  ) {
    if (profileId == failOn) throw const FileSystemException('disk full');
    return super.writeRawStaged(profileId, drawingId, contents);
  }
}

/// One side of a transfer: a repository pair and what it needs to be asserted
/// on.
class _Device {
  _Device(this.root, SaveData save, {DrawingRepository? drawings})
    : store = MemorySaveStore(initial: save),
      drawings = drawings ?? DrawingRepository(root) {
    var tick = 0;
    progress = ProgressRepository(
      store,
      initial: save,
      now: () => DateTime.utc(2026, 9, 1).add(Duration(minutes: ++tick)),
    );
    service = TransferService(
      progress: progress,
      drawings: this.drawings,
      now: () => DateTime.utc(2026, 10, 8, 9),
    );
  }

  final Directory root;
  final MemorySaveStore store;
  final DrawingRepository drawings;
  late final ProgressRepository progress;
  late final TransferService service;

  /// The device's save as a reload from its store would see it.
  Future<SaveData> reloaded() async => (await store.load()).data;
}

void main() {
  late List<Directory> roots;

  Directory newRoot() {
    final dir = Directory.systemTemp.createTempSync('zibo_games_transfer');
    roots.add(dir);
    return dir;
  }

  setUp(() => roots = []);

  tearDown(() {
    for (final dir in roots) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  /// The save everything is exported from: Ana (every field set) and Bo.
  SaveData sourceSave() {
    final save = fullSave();
    return save.copyWith(
      profiles: [
        save.profiles[0].copyWith(
          draw: const DrawProgress(
            drawingCount: 2,
            lastDrawingId: 'd2',
            bytesUsed: 1,
          ),
        ),
        save.profiles[1].copyWith(
          draw: const DrawProgress(drawingCount: 1, lastDrawingId: 'd1'),
        ),
      ],
    );
  }

  Future<_Device> source() async {
    final device = _Device(newRoot(), sourceSave());
    await device.drawings.save('p1', _drawing('d1'));
    await device.drawings.save('p1', _drawing('d2', x: 5));
    await device.drawings.save('p2', _drawing('d1', x: 9));
    return device;
  }

  /// A device on its first launch, with one untouched `Player 1`.
  _Device freshDevice({DrawingRepository? drawings, Directory? root}) =>
      _Device(
        root ?? newRoot(),
        SaveData.initial(createdAt: DateTime.utc(2026, 9, 1)),
        drawings: drawings,
      );

  Future<TransferBundle> exportAll(_Device from) async =>
      from.service.read(await from.service.exportText());

  group('exporting', () {
    test('everyone is flagged, holds every profile and its drawings', () async {
      final device = await source();

      final bundle = await exportAll(device);

      expect(bundle.everyone, isTrue);
      expect(bundle.exportedAt, DateTime.utc(2026, 10, 8, 9));
      expect(bundle.profiles, device.progress.profiles);
      expect(bundle.settings, device.progress.settings);
      expect(bundle.drawings['p1']!.keys.toSet(), {'d1', 'd2'});
      expect(bundle.drawings['p2']!.keys, ['d1']);
    });

    test('one player holds only that player', () async {
      final device = await source();

      final bundle = device.service.read(
        await device.service.exportText(profileId: 'p2'),
      );

      expect(bundle.everyone, isFalse);
      expect(bundle.profiles.map((p) => p.id), ['p2']);
      expect(bundle.drawings.keys, ['p2']);
    });

    test('a drawing file that is not a JSON object is left out', () async {
      final device = await source();
      await device.drawings.writeRaw('p1', 'd3', 'not json');
      await device.drawings.writeRaw('p1', 'd4', '[1, 2]');

      final bundle = await exportAll(device);

      expect(bundle.drawings['p1']!.keys.toSet(), {'d1', 'd2'});
    });

    test('exporting twice gives the same bytes', () async {
      final device = await source();

      expect(
        await device.service.exportText(),
        await device.service.exportText(),
      );
    });

    test('an unknown profile is an ArgumentError', () async {
      final device = await source();

      expect(
        () => device.service.exportText(profileId: 'p9'),
        throwsArgumentError,
      );
    });
  });

  group('suggested file names', () {
    test('everyone', () async {
      expect(
        (await source()).service.suggestedFileName(),
        'zibo-players-2026-10-08.zibo.json',
      );
    });

    test('one player, lower-cased and reduced to letters and digits', () async {
      final device = await source();
      device.progress.renameProfile('p1', 'Zoë & Ann 2!');

      expect(
        device.service.suggestedFileName(profileId: 'p1'),
        'zibo-zo-ann-2-2026-10-08.zibo.json',
      );
    });

    test('a name with nothing usable falls back to player', () async {
      final device = await source();
      device.progress.renameProfile('p1', '!!!');

      expect(
        device.service.suggestedFileName(profileId: 'p1'),
        'zibo-player-2026-10-08.zibo.json',
      );
    });

    test('the date is zero-padded', () async {
      final device = _Device(newRoot(), sourceSave());
      final service = TransferService(
        progress: device.progress,
        drawings: device.drawings,
        now: () => DateTime.utc(2026, 3, 4),
      );

      expect(service.suggestedFileName(), 'zibo-players-2026-03-04.zibo.json');
    });
  });

  group('reading', () {
    test('a bad file is a TransferException', () async {
      final device = await source();

      expect(
        () => device.service.read('hello'),
        throwsA(isA<TransferException>()),
      );
    });
  });

  group('previewing', () {
    test('onto a fresh device nothing is replaced', () async {
      final bundle = await exportAll(await source());

      final preview = freshDevice().service.preview(bundle);

      expect(preview.map((c) => c.incoming.name), ['Ana', 'Bo']);
      expect(preview.map((c) => c.replaces), [null, null]);
    });

    test('after a load, the same file names who it would replace', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );
      target.progress.renameProfile('p3', 'Renamed here');

      final preview = target.service.preview(bundle);

      expect(preview.map((c) => c.replaces?.id), ['p2', 'p3']);
      expect(preview[1].replaces?.name, 'Renamed here');
    });

    test('writes nothing', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      final before = target.progress.data;

      target.service.preview(bundle);

      expect(target.progress.data, before);
      expect(target.root.listSync(), isEmpty);
    });
  });

  group('importing onto a fresh device', () {
    test('drops the starter, adds both, writes drawings, activates the '
        'first imported', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: true,
      );

      // p1 is the starter's id, so the newcomers take the next two.
      final profiles = target.progress.profiles;
      expect(profiles.map((p) => (p.id, p.name)), [
        ('p2', 'Ana'),
        ('p3', 'Bo'),
      ]);
      expect(target.progress.activeProfile.id, 'p2');
      expect(target.progress.settings, bundle.settings);

      expect((await target.drawings.readAllRaw('p2')).keys.toSet(), {
        'd1',
        'd2',
      });
      expect((await target.drawings.readAllRaw('p3')).keys, ['d1']);
      expect(await target.drawings.load('p2', 'd2'), _drawing('d2', x: 5));
      expect(await target.drawings.load('p3', 'd1'), _drawing('d1', x: 9));
      expect(target.drawings.profileBytes('p1'), 0);
    });

    test('recomputes bytesUsed from disk and keeps a lastDrawingId that '
        'exists', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );

      final ana = target.progress.profiles[0];
      expect(ana.draw.bytesUsed, target.drawings.profileBytes('p2'));
      expect(ana.draw.bytesUsed, isNot(1)); // The file's number was a lie.
      expect(ana.draw.drawingCount, 2);
      expect(ana.draw.lastDrawingId, 'd2');
    });

    test('is flushed: a reload sees it', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: true,
      );

      expect(target.progress.isSaving, isFalse);
      final saved = await target.reloaded();
      expect(saved.profiles, target.progress.profiles);
      expect(saved.activeProfileId, 'p2');
    });

    test(
      'export then import yields equal sudoku, arcade and options',
      () async {
        final from = await source();
        final target = freshDevice();

        await target.service.apply(
          await exportAll(from),
          fileProfileIds: {'p1', 'p2'},
          includeSettings: true,
        );

        expect(target.progress.profiles, hasLength(2));
        for (var i = 0; i < 2; i++) {
          final sent = from.progress.profiles[i];
          final got = target.progress.profiles[i];
          expect(got.name, sent.name);
          expect(got.avatar, sent.avatar);
          expect(got.createdAt, sent.createdAt);
          expect(got.sudoku, sent.sudoku);
          expect(got.arcade, sent.arcade);
          expect(got.mistakeFeedback, sent.mistakeFeedback);
          expect(got.arcadeEasyMode, sent.arcadeEasyMode);
          expect(got.arcadeAutoFire, sent.arcadeAutoFire);
          expect(got.padSide, sent.padSide);
          expect(got.snakeCounting, sent.snakeCounting);
        }
        expect(target.progress.settings, from.progress.settings);
      },
    );
  });

  group('importing the same file again', () {
    test('replaces under the local ids, with no duplicates', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: true,
      );
      final once = target.progress.profiles;

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: true,
      );

      expect(target.progress.profiles, once);
      expect(target.progress.profiles.map((p) => p.id), ['p2', 'p3']);
      expect(
        Directory('${target.root.path}/drawings').listSync().map(
          (e) => e.uri.pathSegments.where((s) => s.isNotEmpty).last,
        ),
        unorderedEquals(['p2', 'p3']),
      );
    });

    test('overwrites local progress and drawings with the file\'s', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );
      target.progress.renameProfile('p2', 'Changed');
      target.progress.setArcadeOptions(padSide: PadSide.right);
      await target.drawings.save('p2', _drawing('d9'));

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1'},
        includeSettings: false,
      );

      final ana = target.progress.profiles[0];
      expect(ana.name, 'Ana');
      expect(ana.padSide, PadSide.left);
      expect(target.progress.profiles, hasLength(2));
      expect((await target.drawings.readAllRaw('p2')).keys.toSet(), {
        'd1',
        'd2',
      });
    });

    test('keeps the active profile where it was', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );
      target.progress.selectProfile('p3');

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );

      expect(target.progress.activeProfile.id, 'p3');
    });
  });

  group('importing some players', () {
    test('one player, leaving this device\'s settings alone', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      target.progress.updateSettings(
        const AppSettings(allowPhotoImport: false, showTimer: true),
      );
      final settings = target.progress.settings;

      await target.service.apply(
        bundle,
        fileProfileIds: {'p2'},
        includeSettings: false,
      );

      expect(target.progress.settings, settings);
      expect(target.progress.profiles.map((p) => (p.id, p.name)), [
        ('p2', 'Bo'),
      ]);
      expect(target.progress.activeProfile.id, 'p2');
      expect((await target.drawings.readAllRaw('p2')).keys, ['d1']);
      expect(await target.drawings.readAllRaw('p3'), isEmpty);
    });

    test('keeps a played local profile and adds beside it', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      target.progress.startArcadeGame('invaders');

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1'},
        includeSettings: false,
      );

      expect(target.progress.profiles.map((p) => (p.id, p.name)), [
        ('p1', 'Player 1'),
        ('p2', 'Ana'),
      ]);
      expect(target.progress.activeProfile.id, 'p1');
    });

    test('with settings asked for, applies them', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();

      await target.service.apply(
        bundle,
        fileProfileIds: {'p2'},
        includeSettings: true,
      );

      expect(target.progress.settings, bundle.settings);
    });

    test('selecting nobody is an ArgumentError and changes nothing', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      final before = target.progress.data;

      await expectLater(
        target.service.apply(
          bundle,
          fileProfileIds: {'p9'},
          includeSettings: true,
        ),
        throwsArgumentError,
      );
      expect(target.progress.data, before);
    });
  });

  group('drawings that cannot be loaded', () {
    TransferBundle withDrawings(
      TransferBundle bundle,
      Map<String, Map<String, Object?>> p1,
    ) => TransferBundle(
      exportedAt: bundle.exportedAt,
      everyone: bundle.everyone,
      settings: bundle.settings,
      profiles: bundle.profiles,
      drawings: {'p1': p1},
    );

    test('are skipped, and lastDrawingId is cleared if it named one', () async {
      final good = await exportAll(await source());
      final d1 = good.drawings['p1']!['d1']!;
      final bundle = withDrawings(good, {
        'd1': d1,
        'd2': {'id': 'd2', 'strokes': 'not a list'},
        '../evil': {...d1, 'id': '../evil'},
        'd3': {...d1, 'id': 'somebody-else'},
      });
      final target = freshDevice();

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1'},
        includeSettings: false,
      );

      expect((await target.drawings.readAllRaw('p2')).keys, ['d1']);
      expect(File('${target.root.path}/evil.json').existsSync(), isFalse);
      final draw = target.progress.profiles.single.draw;
      expect(draw.lastDrawingId, isNull); // It was d2, which did not load.
      expect(draw.drawingCount, 2);
      expect(draw.bytesUsed, target.drawings.profileBytes('p2'));
    });

    test('a file keeps the drawing fields this build does not know', () async {
      final good = await exportAll(await source());
      final d1 = {...good.drawings['p1']!['d1']!, 'fromTheFuture': 7};
      final target = freshDevice();

      await target.service.apply(
        withDrawings(good, {'d1': d1}),
        fileProfileIds: {'p1'},
        includeSettings: false,
      );

      final raw = (await target.drawings.readAllRaw('p2'))['d1']!;
      expect((jsonDecode(raw) as Map)['fromTheFuture'], 7);
      expect(decodeDrawing(raw), _drawing('d1'));
    });

    test('a drawingCount behind the file\'s own drawings is raised to the '
        'highest id, so the next drawing cannot overwrite one', () async {
      final good = await exportAll(await source());
      final d1 = good.drawings['p1']!['d1']!;
      final bundle = withDrawings(good, {
        'd1': d1,
        'd9': {...d1, 'id': 'd9'},
      });
      final target = freshDevice();

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1'},
        includeSettings: false,
      );

      expect(target.progress.profiles.single.draw.drawingCount, 9);
      expect(target.progress.nextDrawingId(), 'd10');
    });
  });

  group('leftovers', () {
    test('a new profile\'s folder is emptied first, so a deleted '
        'profile\'s pictures do not come back', () async {
      final bundle = await exportAll(await source());
      final target = freshDevice();
      // deleteProfile leaves the files, and the next id reuses the number.
      await target.drawings.save('p2', _drawing('old'));
      await target.drawings.save('p3', _drawing('old'));

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );

      expect((await target.drawings.readAllRaw('p2')).keys.toSet(), {
        'd1',
        'd2',
      });
      expect((await target.drawings.readAllRaw('p3')).keys, ['d1']);
    });

    test('a profile with no drawings in the file ends with an empty '
        'folder, not the old one', () async {
      final good = await exportAll(await source());
      final bundle = TransferBundle(
        exportedAt: good.exportedAt,
        everyone: false,
        settings: good.settings,
        profiles: [good.profiles.first],
      );
      final target = freshDevice();
      await target.drawings.save('p2', _drawing('old'));

      await target.service.apply(
        bundle,
        fileProfileIds: {'p1'},
        includeSettings: false,
      );

      expect(await target.drawings.readAllRaw('p2'), isEmpty);
      expect(target.progress.profiles.single.draw.bytesUsed, 0);
    });
  });

  group('a failure while writing', () {
    test('a drawing leaves the save, settings and active profile as they '
        'were', () async {
      final bundle = await exportAll(await source());
      final root = newRoot();
      final target = freshDevice(
        root: root,
        drawings: _FlakyDrawings(root, 'p3'), // The second newcomer.
      );
      await target.progress.flush();
      final before = target.progress.data;
      final writes = target.store.writes;

      await expectLater(
        target.service.apply(
          bundle,
          fileProfileIds: {'p1', 'p2'},
          includeSettings: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await target.progress.flush();

      expect(target.progress.data, before);
      expect(target.store.writes, writes);
      expect(target.progress.profiles.single.name, 'Player 1');
    });

    test('a replaced profile keeps its existing drawings, and no staging '
        'folder is left behind', () async {
      final bundle = await exportAll(await source());
      final root = newRoot();
      final flaky = _FlakyDrawings(root);
      final target = freshDevice(root: root, drawings: flaky);
      await target.service.apply(
        bundle,
        fileProfileIds: {'p1', 'p2'},
        includeSettings: false,
      );
      // Local changes the file does not know about: a picture and a rename.
      await flaky.save('p2', _drawing('local', x: 3));
      target.progress.renameProfile('p2', 'Mine');
      await target.progress.flush();
      final before = target.progress.data;
      final writes = target.store.writes;
      final p2Before = await flaky.readAllRaw('p2');
      final p3Before = await flaky.readAllRaw('p3');

      // p2 stages fine; p3, the second to be written, fails.
      flaky.failOn = 'p3';
      await expectLater(
        target.service.apply(
          bundle,
          fileProfileIds: {'p1', 'p2'},
          includeSettings: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      await target.progress.flush();

      expect(target.progress.data, before);
      expect(target.store.writes, writes);
      expect(await flaky.readAllRaw('p2'), p2Before);
      expect(await flaky.readAllRaw('p3'), p3Before);
      expect(p2Before.keys, contains('local'));
      expect(
        Directory('${root.path}/drawings')
            .listSync()
            .map((e) => e.path)
            .where((path) => path.endsWith('.incoming')),
        isEmpty,
      );
    });

    test(
      'a staging folder left by a crash is cleared, not merged in',
      () async {
        final bundle = await exportAll(await source());
        final root = newRoot();
        final target = freshDevice(root: root);
        File('${root.path}/drawings/p2.incoming/stale.json')
          ..createSync(recursive: true)
          ..writeAsStringSync('{}');

        await target.service.apply(
          bundle,
          fileProfileIds: {'p1'},
          includeSettings: false,
        );

        expect((await target.drawings.readAllRaw('p2')).keys.toSet(), {
          'd1',
          'd2',
        });
        expect(
          Directory('${root.path}/drawings/p2.incoming').existsSync(),
          isFalse,
        );
      },
    );

    test('a folder that cannot be created leaves the save as it was', () async {
      final bundle = await exportAll(await source());
      final root = newRoot();
      // `drawings` is a file, so no profile folder can exist under it.
      File('${root.path}/drawings').writeAsStringSync('in the way');
      final target = freshDevice(root: root);
      final before = target.progress.data;

      await expectLater(
        target.service.apply(
          bundle,
          fileProfileIds: {'p1', 'p2'},
          includeSettings: true,
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(target.progress.data, before);
      expect(target.progress.activeProfile.id, 'p1');
    });
  });

  test(
    'a file from this build is accepted by the codec the service uses',
    () async {
      final text = await (await source()).service.exportText();

      expect(decodeTransfer(text).profiles, hasLength(2));
    },
  );
}
