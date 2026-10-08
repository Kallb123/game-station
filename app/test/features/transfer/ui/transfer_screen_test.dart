// The Move players screen, driven the way a parent drives it: Settings, then
// the buttons on the screen, over a fake `TransferFiles` that holds the file in
// memory (`PLAN-transfer.md` §3.4, §5 part 3).
//
// Everything behind the fake is real: the codec, the repositories, the service
// and a `DrawingRepository` on a temp directory. What the tests assert is
// therefore what a second device would read, not what a mock was told.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/progress_repository.dart';
import 'package:zibo_games/core/storage/providers.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';
import 'package:zibo_games/features/draw/data/drawing_repository.dart';
import 'package:zibo_games/features/draw/data/providers.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';
import 'package:zibo_games/features/settings/settings_screen.dart';
import 'package:zibo_games/features/transfer/data/providers.dart';
import 'package:zibo_games/features/transfer/data/transfer_codec.dart';
import 'package:zibo_games/features/transfer/data/transfer_files.dart';
import 'package:zibo_games/features/transfer/data/transfer_service.dart';
import 'package:zibo_games/features/transfer/ui/transfer_screen.dart';

import '../../../app_harness.dart';
import '../../../core/storage/save_fixtures.dart';

/// A [TransferFiles] that keeps files in memory.
///
/// Both shapes in one class, chosen by [usesSystemPicker]: the screen never
/// branches on the platform itself, so neither does the fake.
class _FakeFiles implements TransferFiles {
  _FakeFiles({
    this.usesSystemPicker = true,
    this.picked,
    this.pickThrows,
    this.entries = const [],
    this.contents = const {},
    this.writeThrows = false,
    this.dismissWrite = false,
  });

  @override
  final bool usesSystemPicker;

  /// What the system picker returns; null is a dismissed dialog.
  String? picked;

  /// Thrown by [pickAndRead] instead, when set.
  final Object? pickThrows;

  /// What [listFiles] returns, in the order given.
  final List<TransferFileEntry> entries;

  /// Entry name to text, for [readFile].
  final Map<String, String> contents;

  /// Where `write` says the file went.
  final String where = 'the Downloads folder';
  final bool writeThrows;
  final bool dismissWrite;

  /// Every `write`, in order.
  final List<({String name, String text})> writes = [];

  @override
  Future<String?> write(String fileName, String contents) async {
    if (writeThrows) {
      throw const FileSystemException('errno = 13, permission denied');
    }
    writes.add((name: fileName, text: contents));
    return dismissWrite ? null : where;
  }

  @override
  Future<String?> pickAndRead() async {
    final error = pickThrows;
    if (error != null) throw error;
    return picked;
  }

  @override
  Future<List<TransferFileEntry>> listFiles() async => entries;

  @override
  Future<String> readFile(TransferFileEntry entry) async =>
      contents[entry.name]!;
}

/// A service whose load always fails, for the sentence a parent sees then.
class _FailingService extends TransferService {
  _FailingService({required super.progress, required super.drawings});

  @override
  Future<void> apply(
    TransferBundle bundle, {
    required Set<String> fileProfileIds,
    required bool includeSettings,
  }) async => throw StateError('disk on fire');
}

Drawing _drawing(String id) => Drawing(
  id: id,
  createdAt: DateTime.utc(2026, 8, 11, 12),
  strokes: [
    const Stroke(
      colorIndex: 1,
      sizeIndex: 1,
      points: [Offset(1, 1), Offset(2, 2)],
    ),
  ],
);

void main() {
  late List<Directory> roots;

  setUp(() => roots = []);

  tearDown(() {
    for (final dir in roots) {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  });

  DrawingRepository newDrawings() {
    final dir = Directory.systemTemp.createTempSync('zibo_games_transfer_ui');
    roots.add(dir);
    return DrawingRepository(dir);
  }

  /// Ana, who has played everything, and Bo; plus a drawing of Ana's on disk
  /// once [seedDrawings] has run.
  SaveData twoPlayers() => fullSave().copyWith(
    profiles: [
      fullSave().profiles[0].copyWith(
        draw: const DrawProgress(drawingCount: 1, lastDrawingId: 'd1'),
      ),
      fullSave().profiles[1],
    ],
  );

  /// Writes `d1` for Ana into [drawings].
  Future<void> seedDrawings(WidgetTester tester, DrawingRepository drawings) =>
      tester.runAsync(() => drawings.save('p1', _drawing('d1')));

  /// The text of a file holding [twoPlayers], made the way the app makes it.
  Future<String> twoPlayersText(WidgetTester tester) async {
    final drawings = newDrawings();
    await seedDrawings(tester, drawings);
    final save = twoPlayers();
    final service = TransferService(
      progress: ProgressRepository(
        MemorySaveStore(initial: save),
        initial: save,
      ),
      drawings: drawings,
    );
    return (await tester.runAsync(service.exportText))!;
  }

  /// Starts the app over [save] with [files] behind the screen.
  Future<ProviderContainer> launch(
    WidgetTester tester, {
    required _FakeFiles files,
    SaveData? save,
    DrawingRepository? drawings,
    MemorySaveStore? store,
    List<Override> overrides = const [],
  }) => pumpApp(
    tester,
    store: store ?? MemorySaveStore(initial: save ?? freshSave()),
    overrides: [
      drawingRepositoryProvider.overrideWithValue(drawings ?? newDrawings()),
      transferFilesProvider.overrideWithValue(files),
      ...overrides,
    ],
  );

  /// Settings, then the row that opens the screen, the way a parent gets there.
  Future<void> openTransfer(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(movePlayersLabel),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    // `scrollUntilVisible` stops as soon as the first pixel is built, which on
    // a short window is still under the bottom edge.
    await tester.ensureVisible(find.text(movePlayersLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text(movePlayersLabel));
    await tester.pumpAndSettle();
    expect(find.text(saveSectionLabel), findsOneWidget);
  }

  /// Taps [label], scrolling to it first: the confirmation page is taller than
  /// the test window.
  Future<void> tapText(WidgetTester tester, String label) async {
    // A list builds lazily, so on a short window a button below the fold does
    // not exist until the list has been scrolled towards it.
    if (find.text(label).evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        find.text(label),
        100,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
  }

  /// A tap whose handler does real file work, settled.
  Future<void> tapAndSettle(WidgetTester tester, String label) async {
    await tapText(tester, label);
    await settleDrawIO(tester);
  }

  ProgressRepository repository(ProviderContainer container) =>
      container.read(progressRepositoryProvider);

  group('getting there', () {
    testWidgets('the Settings row opens the screen', (tester) async {
      await launch(tester, files: _FakeFiles());

      await openTransfer(tester);

      expect(find.text(transferTitle), findsOneWidget);
      expect(find.text(loadSectionLabel), findsOneWidget);
    });

    testWidgets(
      'it lists every player and Everyone, and does no I/O to do it',
      (tester) async {
        // `transferFilesProvider` is not overridden: reading it here would hit
        // the real channel, so a build that touched it would throw.
        await pumpApp(
          tester,
          store: MemorySaveStore(initial: twoPlayers()),
          overrides: [
            drawingRepositoryProvider.overrideWithValue(newDrawings()),
          ],
        );

        await openTransfer(tester);

        expect(find.text('Ana'), findsOneWidget);
        expect(find.text('Bo'), findsOneWidget);
        expect(find.text(everyoneLabel), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('saving', () {
    testWidgets('Everyone writes one file and says where it went', (
      tester,
    ) async {
      final files = _FakeFiles();
      await launch(tester, files: files, save: twoPlayers());
      await openTransfer(tester);

      await tapAndSettle(tester, everyoneLabel);

      expect(files.writes, hasLength(1));
      expect(files.writes.single.name, startsWith('zibo-players-'));
      expect(files.writes.single.name, endsWith(transferFileExtension));
      expect(find.text(savedMessage('the Downloads folder')), findsOneWidget);
      final bundle = decodeTransfer(files.writes.single.text);
      expect(bundle.everyone, isTrue);
      expect(bundle.profiles.map((p) => p.name), ['Ana', 'Bo']);
    });

    testWidgets('one player writes a file of just that player', (tester) async {
      final files = _FakeFiles();
      await launch(tester, files: files, save: twoPlayers());
      await openTransfer(tester);

      await tapAndSettle(tester, 'Bo');

      expect(files.writes.single.name, startsWith('zibo-bo-'));
      final bundle = decodeTransfer(files.writes.single.text);
      expect(bundle.everyone, isFalse);
      expect(bundle.profiles.map((p) => p.name), ['Bo']);
    });

    testWidgets('a dismissed dialog says nothing', (tester) async {
      final files = _FakeFiles(dismissWrite: true);
      await launch(tester, files: files, save: twoPlayers());
      await openTransfer(tester);

      await tapAndSettle(tester, everyoneLabel);

      expect(files.writes, hasLength(1));
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('a failed write is one friendly line, not the error', (
      tester,
    ) async {
      await launch(
        tester,
        files: _FakeFiles(writeThrows: true),
        save: twoPlayers(),
      );
      await openTransfer(tester);

      await tapAndSettle(tester, everyoneLabel);

      expect(find.text(saveFailedMessage), findsOneWidget);
      expect(find.textContaining('errno'), findsNothing);
      expect(find.textContaining('FileSystemException'), findsNothing);
      // And the buttons work again.
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(everyoneLabel),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  group('the round trip', () {
    testWidgets(
      'everyone saved on one device is everyone loaded on a fresh one',
      (tester) async {
        // Device one: Ana and Bo, scores, solved puzzles, night theme, a drawing.
        final sourceDrawings = newDrawings();
        await seedDrawings(tester, sourceDrawings);
        final written = _FakeFiles();
        await launch(
          tester,
          files: written,
          save: twoPlayers(),
          drawings: sourceDrawings,
        );
        await openTransfer(tester);
        await tapAndSettle(tester, everyoneLabel);
        final text = written.writes.single.text;

        // Device two: a first launch, over a new store and a new drawings
        // folder. `pumpApp` a second time is a relaunch.
        final targetDrawings = newDrawings();
        final container = await launch(
          tester,
          files: _FakeFiles(picked: text),
          drawings: targetDrawings,
        );
        expect(repository(container).profiles.single.name, 'Player 1');
        await openTransfer(tester);

        await tapText(tester, chooseFileLabel);
        await tester.pumpAndSettle();

        // The confirmation: both players, both ticked, settings offered and on
        // because the file is everyone.
        expect(find.text(confirmTitle), findsOneWidget);
        expect(find.text('Ana'), findsOneWidget);
        expect(find.text('Bo'), findsOneWidget);
        expect(find.textContaining('Replaces'), findsNothing);
        expect(
          tester
              .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
              .map((tile) => tile.value),
          [true, true],
        );
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue,
        );

        await tapAndSettle(tester, loadLabel);

        // Back on the transfer screen with the one line.
        expect(find.text(saveSectionLabel), findsOneWidget);
        expect(find.text(loadedMessage(2)), findsOneWidget);

        final source = twoPlayers();
        final loaded = repository(container);
        expect(loaded.profiles.map((p) => p.name), ['Ana', 'Bo']);
        expect(loaded.profiles.any((p) => p.name == 'Player 1'), isFalse);
        for (var i = 0; i < 2; i++) {
          final profile = loaded.profiles[i];
          final original = source.profiles[i];
          expect(profile.avatar, original.avatar);
          expect(profile.createdAt, original.createdAt);
          expect(profile.arcade, original.arcade);
          expect(profile.sudoku, original.sudoku);
          expect(profile.mistakeFeedback, original.mistakeFeedback);
          expect(profile.snakeCounting, original.snakeCounting);
        }
        expect(loaded.settings, source.settings);
        // The untouched starter was the active profile, so the first imported
        // player takes over.
        expect(loaded.activeProfile.name, 'Ana');

        final drawings = await tester.runAsync(
          () => targetDrawings.listDecodable(loaded.profiles[0].id),
        );
        expect(drawings!.map((d) => d.id), ['d1']);

        // And what the second device wrote is what a third would read back.
        await loaded.flush();
      },
    );

    testWidgets('loading a file onto the device it came from restores, not '
        'duplicates', (tester) async {
      final text = await twoPlayersText(tester);
      final container = await launch(
        tester,
        files: _FakeFiles(picked: text),
        save: twoPlayers().copyWith(
          profiles: [
            twoPlayers().profiles[0].copyWith(name: 'Ana renamed'),
            twoPlayers().profiles[1],
          ],
        ),
      );
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      expect(find.text(replacesMessage('Ana renamed')), findsOneWidget);
      expect(find.text(replacesMessage('Bo')), findsOneWidget);

      await tapAndSettle(tester, loadLabel);

      expect(repository(container).profiles.map((p) => p.name), ['Ana', 'Bo']);
    });
  });

  group('settings on load', () {
    /// Ana's file, the way "one player" writes it.
    Future<String> anaOnlyText(WidgetTester tester) async {
      final files = _FakeFiles();
      await launch(tester, files: files, save: twoPlayers());
      await openTransfer(tester);
      await tapAndSettle(tester, 'Ana');
      expect(decodeTransfer(files.writes.single.text).everyone, isFalse);
      return files.writes.single.text;
    }

    const quiet = AppSettings(sound: false, allowPhotoImport: false);

    testWidgets('a one-player file leaves this device settings alone', (
      tester,
    ) async {
      final text = await anaOnlyText(tester);
      final container = await launch(
        tester,
        files: _FakeFiles(picked: text),
        save: freshSave(settings: quiet),
      );
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tapAndSettle(tester, loadLabel);

      expect(find.text(loadedMessage(1)), findsOneWidget);
      expect(loadedMessage(1), 'Loaded 1 player');
      expect(repository(container).settings, quiet);
      expect(repository(container).profiles.map((p) => p.name), ['Ana']);
    });

    testWidgets('the switch copies them when turned on', (tester) async {
      final text = await anaOnlyText(tester);
      final container = await launch(
        tester,
        files: _FakeFiles(picked: text),
        save: freshSave(settings: quiet),
      );
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();
      await tapText(tester, copySettingsLabel);
      await tester.pumpAndSettle();
      await tapAndSettle(tester, loadLabel);

      expect(repository(container).settings, twoPlayers().settings);
    });
  });

  group('the confirmation', () {
    testWidgets('Load is off while nothing is ticked, and a player can be left '
        'out', (tester) async {
      final text = await twoPlayersText(tester);
      final container = await launch(tester, files: _FakeFiles(picked: text));
      await openTransfer(tester);
      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      FilledButton loadButton() => tester.widget<FilledButton>(
        find.ancestor(
          of: find.text(loadLabel),
          matching: find.byType(FilledButton),
        ),
      );

      await tapText(tester, 'Ana');
      await tester.pumpAndSettle();
      expect(loadButton().onPressed, isNotNull);
      await tapText(tester, 'Bo');
      await tester.pumpAndSettle();
      expect(loadButton().onPressed, isNull);

      // Ana back on, Bo left out.
      await tapText(tester, 'Ana');
      await tester.pumpAndSettle();
      await tapAndSettle(tester, loadLabel);

      expect(find.text(loadedMessage(1)), findsOneWidget);
      expect(repository(container).profiles.map((p) => p.name), ['Ana']);
    });

    testWidgets('backing out changes nothing', (tester) async {
      final text = await twoPlayersText(tester);
      final container = await launch(tester, files: _FakeFiles(picked: text));
      final before = repository(container).data;
      await openTransfer(tester);
      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text(saveSectionLabel), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(repository(container).data, before);
    });

    testWidgets('a load that throws says so once and changes nothing', (
      tester,
    ) async {
      final text = await twoPlayersText(tester);
      final drawings = newDrawings();
      final container = await launch(
        tester,
        files: _FakeFiles(picked: text),
        drawings: drawings,
        overrides: [
          transferServiceProvider.overrideWith(
            (ref) => _FailingService(
              progress: ref.watch(progressRepositoryProvider.notifier),
              drawings: drawings,
            ),
          ),
        ],
      );
      final before = repository(container).data;
      await openTransfer(tester);
      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      await tapAndSettle(tester, loadLabel);

      expect(find.text(loadFailedMessage), findsOneWidget);
      expect(find.textContaining('disk on fire'), findsNothing);
      expect(repository(container).data, before);
    });

    testWidgets('survives 200% text on a 360x640 phone', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final text = await twoPlayersText(tester);
      await launch(
        tester,
        files: _FakeFiles(picked: text),
        save: twoPlayers().copyWith(
          profiles: [
            twoPlayers().profiles[0].copyWith(name: 'Ana with a long name'),
            twoPlayers().profiles[1],
          ],
        ),
      );
      await openTransfer(tester);
      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text(loadLabel),
        100,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('a file that cannot be loaded', () {
    Future<void> expectRefused(
      WidgetTester tester, {
      required _FakeFiles files,
      required String sentence,
    }) async {
      final container = await launch(tester, files: files);
      final before = repository(container).data;
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      expect(find.text(sentence), findsOneWidget);
      expect(find.text(confirmTitle), findsNothing);
      expect(repository(container).data, before);
    }

    testWidgets('junk is not a players file', (tester) async {
      await expectRefused(
        tester,
        files: _FakeFiles(picked: 'hello, this is a shopping list'),
        sentence: "That file isn't a players file.",
      );
    });

    testWidgets('JSON that is not ours is not a players file', (tester) async {
      await expectRefused(
        tester,
        files: _FakeFiles(picked: '{"some": "other app"}'),
        sentence: notAPlayersFileMessage,
      );
    });

    testWidgets('a picker error is the same sentence', (tester) async {
      await expectRefused(
        tester,
        files: _FakeFiles(pickThrows: const FormatException('not UTF-8')),
        sentence: notAPlayersFileMessage,
      );
    });

    testWidgets('a newer file says to update', (tester) async {
      final text = await twoPlayersText(tester);
      final newer = jsonDecode(text) as Map<String, Object?>
        ..['formatVersion'] = transferFormatVersion + 1;
      await expectRefused(
        tester,
        files: _FakeFiles(picked: jsonEncode(newer)),
        sentence:
            'That file is from a newer version of Zibo Games. Update this one '
            'first.',
      );
    });

    testWidgets('another puzzle generator is a different version', (
      tester,
    ) async {
      final text = await twoPlayersText(tester);
      final other = jsonDecode(text) as Map<String, Object?>;
      (other['save']! as Map<String, Object?>)['generatorVersion'] = 999;
      await expectRefused(
        tester,
        files: _FakeFiles(picked: jsonEncode(other)),
        sentence: 'That file is from a different version of Zibo Games.',
      );
    });

    testWidgets('a dismissed picker does nothing at all', (tester) async {
      final container = await launch(tester, files: _FakeFiles());
      final before = repository(container).data;
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(confirmTitle), findsNothing);
      expect(repository(container).data, before);
    });
  });

  group('where the platform lists a folder', () {
    TransferFileEntry entry(String name, DateTime modified) =>
        TransferFileEntry(name: name, path: '/x/$name', modified: modified);

    testWidgets('newest first, and the chosen one is loaded', (tester) async {
      final text = await twoPlayersText(tester);
      final files = _FakeFiles(
        usesSystemPicker: false,
        entries: [
          entry('zibo-players-2026-10-08.zibo.json', DateTime(2026, 10, 8, 9)),
          entry('zibo-ana-2026-09-01.zibo.json', DateTime(2026, 9, 1, 18, 5)),
        ],
        contents: {'zibo-players-2026-10-08.zibo.json': text},
      );
      final container = await launch(tester, files: files);
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      expect(find.text(pickFileTitle), findsOneWidget);
      expect(find.text('2026-10-08 09:00'), findsOneWidget);
      expect(find.text('2026-09-01 18:05'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('zibo-players-2026-10-08.zibo.json')).dy,
        lessThan(
          tester.getTopLeft(find.text('zibo-ana-2026-09-01.zibo.json')).dy,
        ),
      );

      await tester.tap(find.text('zibo-players-2026-10-08.zibo.json'));
      await tester.pumpAndSettle();
      expect(find.text(confirmTitle), findsOneWidget);
      await tapAndSettle(tester, loadLabel);

      expect(repository(container).profiles.map((p) => p.name), ['Ana', 'Bo']);
    });

    testWidgets('cancelling the list does nothing', (tester) async {
      final files = _FakeFiles(
        usesSystemPicker: false,
        entries: [entry('a.zibo.json', DateTime(2026, 10, 8))],
      );
      final container = await launch(tester, files: files);
      final before = repository(container).data;
      await openTransfer(tester);
      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text(confirmTitle), findsNothing);
      expect(repository(container).data, before);
    });

    testWidgets('an empty folder says where to put a file', (tester) async {
      await launch(tester, files: _FakeFiles(usesSystemPicker: false));
      await openTransfer(tester);

      await tapText(tester, chooseFileLabel);
      await tester.pumpAndSettle();

      expect(find.text(noFilesMessage(TargetPlatform.windows)), findsOneWidget);
      expect(noFilesMessage(TargetPlatform.windows), contains('Downloads'));
    });

    testWidgets('on iOS it points at the Files app', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await launch(tester, files: _FakeFiles(usesSystemPicker: false));
        await openTransfer(tester);

        await tapText(tester, chooseFileLabel);
        await tester.pumpAndSettle();

        expect(find.textContaining('Files app'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });
}
