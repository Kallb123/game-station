// [ChannelTransferFiles] over a fake `zibo/transfer` channel,
// [FolderTransferFiles] over a temp directory, and the platform switch in
// `transferFilesProvider` (`PLAN-transfer.md` §3.3, §5 part 2). The Kotlin side
// is not exercised here: like `zibo/photos`, CI has no device to run it on, and
// the checklist in `PLAN-transfer.md` §7 is what covers it.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/features/transfer/data/providers.dart';
import 'package:zibo_games/features/transfer/data/transfer_files.dart';

void _mockChannel(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(transferChannel, handler);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChannelTransferFiles', () {
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(transferChannel, null);
    });

    test('uses the system picker', () {
      expect(const ChannelTransferFiles().usesSystemPicker, isTrue);
    });

    test(
      'write sends the name and UTF-8 bytes, returns the chosen name',
      () async {
        MethodCall? seen;
        _mockChannel((call) async {
          seen = call;
          return 'chosen.zibo.json';
        });

        final where = await const ChannelTransferFiles().write(
          'players.zibo.json',
          '{"name":"Zoë"}',
        );

        expect(where, 'chosen.zibo.json');
        expect(seen!.method, 'create');
        final arguments = seen!.arguments as Map<Object?, Object?>;
        expect(arguments['name'], 'players.zibo.json');
        expect(arguments['bytes'], isA<Uint8List>());
        expect(utf8.decode(arguments['bytes']! as Uint8List), '{"name":"Zoë"}');
      },
    );

    test('write returns null when the dialog is dismissed', () async {
      _mockChannel((call) async => null);

      expect(
        await const ChannelTransferFiles().write('a.zibo.json', '{}'),
        isNull,
      );
    });

    test('pickAndRead decodes UTF-8, non-ASCII included', () async {
      _mockChannel((call) async {
        expect(call.method, 'open');
        return Uint8List.fromList(utf8.encode('{"name":"Zoë"}'));
      });

      expect(
        await const ChannelTransferFiles().pickAndRead(),
        '{"name":"Zoë"}',
      );
    });

    test('pickAndRead returns null when the dialog is dismissed', () async {
      _mockChannel((call) async => null);

      expect(await const ChannelTransferFiles().pickAndRead(), isNull);
    });

    test(
      'pickAndRead lets a non-UTF-8 file surface as FormatException',
      () async {
        _mockChannel((call) async => Uint8List.fromList([0xff, 0xfe, 0x00]));

        await expectLater(
          const ChannelTransferFiles().pickAndRead(),
          throwsFormatException,
        );
      },
    );

    test('the folder operations are unsupported', () {
      const files = ChannelTransferFiles();
      final entry = TransferFileEntry(
        name: 'a.zibo.json',
        path: '/a.zibo.json',
        modified: DateTime(2026),
      );
      expect(files.listFiles, throwsUnsupportedError);
      expect(() => files.readFile(entry), throwsUnsupportedError);
    });
  });

  group('FolderTransferFiles', () {
    late Directory root;
    late Directory folder;
    late FolderTransferFiles files;

    setUp(() {
      root = Directory.systemTemp.createTempSync('zibo_games_transfer');
      // Not created: write must create the folder, as it will not exist on a
      // first export to <Downloads>/Zibo Games.
      folder = Directory('${root.path}/Zibo Games');
      files = FolderTransferFiles(() async => folder);
    });

    tearDown(() {
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    test('does not use the system picker', () {
      expect(files.usesSystemPicker, isFalse);
    });

    test(
      'write creates the folder, returns its path, and listFiles finds the file',
      () async {
        final where = await files.write('players.zibo.json', '{"a":1}');

        expect(where, folder.path);
        final listed = await files.listFiles();
        expect(listed.map((e) => e.name), ['players.zibo.json']);
        expect(listed.single.path, '${folder.path}/players.zibo.json');
      },
    );

    test('writing the same name again replaces the file', () async {
      await files.write('players.zibo.json', 'old, and longer than the new');
      await files.write('players.zibo.json', 'new');

      final listed = await files.listFiles();
      expect(listed, hasLength(1));
      expect(await files.readFile(listed.single), 'new');
    });

    test('lists only .zibo.json files', () async {
      await files.write('keep.zibo.json', '{}');
      File('${folder.path}/picture.png').writeAsBytesSync([1]);
      File('${folder.path}/other.json').writeAsStringSync('{}');
      File('${folder.path}/half.zibo.json.tmp').writeAsStringSync('{');
      Directory('${folder.path}/dir.zibo.json').createSync();

      expect((await files.listFiles()).map((e) => e.name), ['keep.zibo.json']);
    });

    test('lists newest first', () async {
      await files.write('middle.zibo.json', '{}');
      await files.write('oldest.zibo.json', '{}');
      await files.write('newest.zibo.json', '{}');
      final base = DateTime.utc(2026, 10, 8, 9);
      File('${folder.path}/oldest.zibo.json').setLastModifiedSync(base);
      File(
        '${folder.path}/middle.zibo.json',
      ).setLastModifiedSync(base.add(const Duration(hours: 1)));
      File(
        '${folder.path}/newest.zibo.json',
      ).setLastModifiedSync(base.add(const Duration(hours: 2)));

      expect((await files.listFiles()).map((e) => e.name), [
        'newest.zibo.json',
        'middle.zibo.json',
        'oldest.zibo.json',
      ]);
    });

    test('readFile round-trips non-ASCII text', () async {
      await files.write('players.zibo.json', '{"name":"Zoë"}');

      final entry = (await files.listFiles()).single;
      expect(await files.readFile(entry), '{"name":"Zoë"}');
    });

    test('listFiles is empty when the folder does not exist yet', () async {
      expect(await files.listFiles(), isEmpty);
    });

    test(
      'with no folder, listFiles is empty and write throws StateError',
      () async {
        final none = FolderTransferFiles(() async => null);

        expect(await none.listFiles(), isEmpty);
        await expectLater(none.write('a.zibo.json', '{}'), throwsStateError);
      },
    );

    test('pickAndRead is unsupported', () {
      expect(files.pickAndRead, throwsUnsupportedError);
    });
  });

  group('transferFilesProvider', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    TransferFiles read(TargetPlatform platform) {
      debugDefaultTargetPlatformOverride = platform;
      final container = ProviderContainer();
      addTearDown(container.dispose);
      return container.read(transferFilesProvider);
    }

    test('Android uses the system picker', () {
      expect(read(TargetPlatform.android), isA<ChannelTransferFiles>());
    });

    test('iOS and every desktop platform use a folder', () {
      for (final platform in [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        final files = read(platform);
        expect(files, isA<FolderTransferFiles>(), reason: '$platform');
        expect(files.usesSystemPicker, isFalse, reason: '$platform');
      }
    });
  });
}
