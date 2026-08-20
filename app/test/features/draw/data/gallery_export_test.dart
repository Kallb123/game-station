// [FolderGalleryExport]'s own test, over a real temp directory standing in
// for Downloads. [GalGalleryExport] is not tested here: it is a thin call
// into `package:gal`, which talks to a platform plugin no test environment
// has — the same gap `AGENTS.md` records for `app/integration_test/`, closed
// instead by `gallery_export_import_test.dart` proving nothing else can call
// it by mistake.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:zibo_games/features/draw/data/gallery_export.dart';

/// Stands in for the platform plugin `path_provider` would otherwise reach
/// for `getDownloadsDirectory()`, returning [path] — or nothing, when a test
/// wants to see the "no downloads directory" case.
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);

  final String? path;

  @override
  Future<String?> getDownloadsPath() async => path;
}

void main() {
  late Directory downloads;
  late PathProviderPlatform original;

  setUp(() {
    downloads = Directory.systemTemp.createTempSync('zibo_games_downloads');
    original = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(downloads.path);
  });

  tearDown(() {
    PathProviderPlatform.instance = original;
    if (downloads.existsSync()) downloads.deleteSync(recursive: true);
  });

  test('available when a downloads directory exists', () async {
    const export = FolderGalleryExport();
    expect(await export.available, isTrue);
  });

  test('unavailable when the platform has no downloads directory', () async {
    PathProviderPlatform.instance = _FakePathProvider(null);
    const export = FolderGalleryExport();
    expect(await export.available, isFalse);
  });

  test('writes the PNG under a Zibo Games folder, creating it', () async {
    const export = FolderGalleryExport();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await export.savePng(bytes, 'drawing-d1');

    final file = File('${downloads.path}/Zibo Games/drawing-d1.png');
    expect(file.existsSync(), isTrue);
    expect(file.readAsBytesSync(), bytes);
  });

  test('a second export does not disturb the first', () async {
    const export = FolderGalleryExport();
    await export.savePng(Uint8List.fromList([1]), 'drawing-d1');
    await export.savePng(Uint8List.fromList([2]), 'drawing-d2');

    final folder = Directory('${downloads.path}/Zibo Games');
    expect(folder.listSync().map((e) => e.path.split('/').last).toSet(), {
      'drawing-d1.png',
      'drawing-d2.png',
    });
  });
}
