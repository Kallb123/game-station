// The store's tests, over a real temp directory.
//
// The interesting cases are the ones that only happen when something has
// already gone wrong — a half-written temp file, a save from a newer build, a
// file full of nonsense — because that is where "never block boot"
// (`PLAN.md` §5.3) is either true or not.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/save_codec.dart';
import 'package:game_station/core/storage/save_data.dart';
import 'package:game_station/core/storage/save_store.dart';

import 'save_fixtures.dart';

void main() {
  late Directory directory;

  /// A fixed clock, so a defaulted save compares equal to an expected one.
  DateTime clock() => DateTime.utc(2026, 8, 12, 9);

  FileSaveStore storeOver(Directory directory) =>
      FileSaveStore(directory, now: clock);

  File fileNamed(String name) => File('${directory.path}/$name');

  setUp(() {
    directory = Directory.systemTemp.createTempSync('game_station_store');
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  group('FileSaveStore load', () {
    test('a first launch gets defaults and says so', () async {
      final load = await storeOver(directory).load();

      expect(load.recovery, SaveRecovery.missing);
      expect(load.data, SaveData.initial(createdAt: clock()));
      // Nothing to apologise for on a first launch.
      expect(load.lostProgress, isFalse);
    });

    test('a stored save is read back as it was written', () async {
      final store = storeOver(directory);
      await store.write(fullSave());

      final load = await store.load();

      expect(load.recovery, isNull);
      expect(load.data, fullSave());
    });

    test('a second store over the same directory reads the same state', () async {
      // The PR's done-criterion: kill the app, relaunch it, get the save back.
      // A second instance is as close as a unit test gets to a second process.
      await storeOver(directory).write(fullSave());

      final load = await storeOver(directory).load();

      expect(load.recovery, isNull);
      expect(load.data, fullSave());
    });

    test('a leftover temp file is deleted unread', () async {
      await storeOver(directory).write(fullSave());
      // What an interrupted write leaves behind. It is newer than save.json and
      // decodes cleanly, so anything that preferred it would pass a weaker test
      // than this one.
      fileNamed(tempFileName).writeAsStringSync(
        encodeSave(SaveData.initial(createdAt: DateTime.utc(2000))),
      );

      final load = await storeOver(directory).load();

      expect(load.data, fullSave());
      expect(fileNamed(tempFileName).existsSync(), isFalse);
    });

    test('a corrupt save is moved aside and replaced with defaults', () async {
      const nonsense = '{"schemaVersion": 1, "profiles": ';
      fileNamed(saveFileName).writeAsStringSync(nonsense);

      final load = await storeOver(directory).load();

      expect(load.recovery, SaveRecovery.corrupt);
      expect(load.data, SaveData.initial(createdAt: clock()));
      expect(load.lostProgress, isTrue);
      expect(fileNamed(saveFileName).existsSync(), isFalse);
      // Kept verbatim: it is the only evidence of whatever wrote it.
      expect(fileNamed(corruptFileName).readAsStringSync(), nonsense);
    });

    test('a save with a wrong-typed field is corrupt too', () async {
      // Not just unparseable JSON: a file that parses but says `"sound": "yes"`
      // was written by something other than this app, and the codec refuses it
      // rather than coercing it.
      fileNamed(saveFileName).writeAsStringSync(
        '{"schemaVersion": 1, "activeProfileId": "p1", '
        '"settings": {"sound": "yes"}, '
        '"profiles": [{"id": "p1", "name": "Ana", "avatar": "fox", '
        '"createdAt": "2026-08-11T10:00:00Z"}]}',
      );

      final load = await storeOver(directory).load();

      expect(load.recovery, SaveRecovery.corrupt);
      expect(fileNamed(corruptFileName).existsSync(), isTrue);
    });

    test('a second corruption replaces the first corrupt file', () async {
      fileNamed(corruptFileName).writeAsStringSync('an older corrupt save');
      fileNamed(saveFileName).writeAsStringSync('not json');

      await storeOver(directory).load();

      expect(fileNamed(corruptFileName).readAsStringSync(), 'not json');
    });

    test('a save from a newer build is kept separately', () async {
      // Separate from the corrupt file because it is intact: a later build may
      // be able to read it, and lumping the two together would lose that.
      const newer = '{"schemaVersion": 99, "profiles": []}';
      fileNamed(saveFileName).writeAsStringSync(newer);

      final load = await storeOver(directory).load();

      expect(load.recovery, SaveRecovery.unsupportedVersion);
      expect(load.data, SaveData.initial(createdAt: clock()));
      expect(fileNamed(unsupportedFileName).readAsStringSync(), newer);
      expect(fileNamed(corruptFileName).existsSync(), isFalse);
    });

    test(
      'recovering from a corrupt save leaves a working save behind',
      () async {
        // The boot loop this design exists to prevent: recover, play, close,
        // reopen — and the second launch must be a clean one.
        fileNamed(saveFileName).writeAsStringSync('not json');
        final store = storeOver(directory);
        final recovered = await store.load();
        await store.write(recovered.data);

        final second = await storeOver(directory).load();

        expect(second.recovery, isNull);
        expect(second.data, recovered.data);
      },
    );
  });

  group('FileSaveStore write', () {
    test('leaves no temp file behind', () async {
      await storeOver(directory).write(fullSave());

      expect(fileNamed(saveFileName).existsSync(), isTrue);
      expect(fileNamed(tempFileName).existsSync(), isFalse);
    });

    test('replaces an existing save', () async {
      // The rename-over-an-existing-file case. It is the step
      // PLAN-phase-1.md §7 flags as the one that can behave differently on
      // Windows, which is why the Windows CI job runs this suite.
      final store = storeOver(directory);
      await store.write(fullSave());
      final replacement = SaveData.initial(createdAt: clock());

      await store.write(replacement);

      expect((await store.load()).data, replacement);
    });

    test('creates the directory when it is missing', () async {
      final missing = Directory('${directory.path}/nested/support');

      await storeOver(missing).write(fullSave());

      expect((await storeOver(missing).load()).data, fullSave());
    });

    test('writes the same bytes for the same save', () async {
      // The codec sorts data-named keys so this holds; asserting it here as
      // well is what stops a future store change — a timestamp in the file, say
      // — from making every save a fresh write.
      final store = storeOver(directory);
      await store.write(fullSave());
      final first = fileNamed(saveFileName).readAsStringSync();

      await store.write(fullSave());

      expect(fileNamed(saveFileName).readAsStringSync(), first);
    });
  });

  group('the layer boundary', () {
    // PLAN-phase-1.md §5: one file in `core/storage` touches a filesystem, so
    // everything above it can be tested without one. Nothing else would notice
    // that breaking — `flutter analyze` is perfectly happy with `dart:io`
    // anywhere in `lib/` — and it stops being true one convenient import at a
    // time.
    test('only save_store.dart imports dart:io', () {
      final storage = Directory('lib/core/storage');
      expect(
        storage.existsSync(),
        isTrue,
        reason: 'not found from ${Directory.current.path}',
      );

      final offenders =
          storage
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'))
              .where(
                (file) => file.readAsStringSync().contains("import 'dart:io'"),
              )
              .map((file) => file.uri.pathSegments.last)
              .toList()
            ..sort();

      expect(offenders, ['save_store.dart']);
    });
  });

  group('MemorySaveStore', () {
    test('starts empty, like a first launch', () async {
      final load = await MemorySaveStore(now: clock).load();

      expect(load.recovery, SaveRecovery.missing);
      expect(load.data, SaveData.initial(createdAt: clock()));
    });

    test('round trips through the codec, as the file store does', () async {
      final store = MemorySaveStore();

      await store.write(fullSave());

      expect((await store.load()).data, fullSave());
      expect(store.writes, 1);
    });

    test('reports a seeded recovery', () async {
      // How a widget test drives the "we couldn't find your old games" banner
      // without corrupting a real file.
      final store = MemorySaveStore(recovery: SaveRecovery.corrupt, now: clock);

      expect((await store.load()).recovery, SaveRecovery.corrupt);
    });
  });
}
