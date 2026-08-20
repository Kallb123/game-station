// Where an exported drawing's PNG bytes go: the device photo library on
// Android and iOS, a `Zibo Games` folder under Downloads everywhere else
// (`PLAN-phase-8.md` §3.2, §4.6).
//
// `GalGalleryExport` is the only file in `app/lib` that imports
// `package:gal` — `gallery_export_import_test.dart` asserts it, the same
// shape of guard `no_random_test.dart` keeps for `Random`, with its own
// self-tests for the same reason.

import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Saves an exported drawing's PNG bytes somewhere a parent can find them
/// afterwards.
///
/// [available] answers whether this *platform* has somewhere to save to —
/// export stays available either way, unlike import (`PLAN-phase-8.md` §1) —
/// not whether permission has been granted yet. `Future<bool>` rather than
/// the plan's own sketch of a plain `bool`: [FolderGalleryExport] can only
/// answer by asking `path_provider`, which is itself async, so both
/// implementations answer the same way.
abstract interface class GalleryExport {
  /// Whether this platform has somewhere to save to at all.
  Future<bool> get available;

  /// Saves [bytes] under [name] — no extension: callers do not know which
  /// one an implementation adds, only that it is a PNG.
  Future<void> savePng(Uint8List bytes, String name);
}

/// Android and iOS: the device photo library, through `package:gal`
/// (`PLAN-phase-8.md` §3.2). Every device on both platforms has one, so
/// [available] is unconditionally true; `Gal.putImageBytes` is what handles
/// the `MediaStore` split on Android and the add-only permission prompt on
/// iOS, at the point of the write itself rather than asked for up front —
/// asking earlier would show a permission dialog before a child has tapped
/// anything.
class GalGalleryExport implements GalleryExport {
  const GalGalleryExport();

  @override
  Future<bool> get available async => true;

  @override
  Future<void> savePng(Uint8List bytes, String name) =>
      Gal.putImageBytes(bytes, name: name);
}

/// Windows, macOS and Linux: a plain file write to `<Downloads>/Zibo Games/`
/// (`PLAN-phase-8.md` §4.6) — desktop has no photo library `gal` can reach,
/// and `path_provider` offers `getDownloadsDirectory()` where it offers
/// nothing for Pictures, so Downloads is the folder rather than a
/// hard-coded, per-platform Pictures path.
class FolderGalleryExport implements GalleryExport {
  const FolderGalleryExport();

  @override
  Future<bool> get available async => await getDownloadsDirectory() != null;

  @override
  Future<void> savePng(Uint8List bytes, String name) async {
    final downloads = await getDownloadsDirectory();
    if (downloads == null) {
      throw StateError('No downloads directory on this platform.');
    }
    final folder = Directory('${downloads.path}/Zibo Games');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    await File('${folder.path}/$name.png').writeAsBytes(bytes);
  }
}
