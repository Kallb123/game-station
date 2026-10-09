// Where a players file is written to and loaded from (`PLAN-transfer.md`
// §3.3). Two shapes, because the platforms differ in what they can offer a
// parent without a new dependency:
//
//  * [ChannelTransferFiles] — Android. The system's own save and open dialogs,
//    reached over the `zibo/transfer` channel that `TransferPlugin.kt` answers.
//    The parent chooses where the file goes and picks it again by hand.
//  * [FolderTransferFiles] — iOS and desktop. A folder the parent can already
//    see (the Files app, or `<Downloads>/Zibo Games`), listed by the app itself.
//
// Both sit behind [TransferFiles] so the service and the screen never branch on
// platform; the screen reads [TransferFiles.usesSystemPicker] to choose between
// a button that opens the system picker and a list.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:path_provider/path_provider.dart';

import '../../../core/storage/atomic_write.dart';

// The same string `transfer_codec.dart` calls `transferFileExtension`. Kept
// as a private copy so this file, which is only about files and folders, does
// not import the codec and its model for the sake of one suffix.
const String _fileExtension = '.zibo.json';

/// The folder name under Downloads that `FolderGalleryExport` already writes
/// drawings to; a parent looks in one place for everything the app exports.
const String _desktopFolderName = 'Zibo Games';

/// One file a folder-based [TransferFiles] can offer to load.
class TransferFileEntry {
  const TransferFileEntry({
    required this.name,
    required this.path,
    required this.modified,
  });

  /// The file name shown to the parent, for example
  /// `zibo-players-2026-10-08.zibo.json`.
  final String name;

  /// Absolute path.
  final String path;

  final DateTime modified;
}

/// Writes a players file somewhere a parent can find it, and reads one back.
abstract interface class TransferFiles {
  /// True where loading goes through the platform's own file picker
  /// ([pickAndRead]); false where the app lists a folder itself
  /// ([listFiles], [readFile]).
  bool get usesSystemPicker;

  /// Writes [contents] as [fileName]. Returns a short description of where it
  /// went, for one line of UI text (the folder path, or the name the parent
  /// chose in the system dialog), or null if the parent dismissed the dialog.
  Future<String?> write(String fileName, String contents);

  /// System-picker platforms only: prompts for a file and returns its text, or
  /// null if dismissed.
  ///
  /// Throws [FormatException] if the file is not valid UTF-8. The caller reads
  /// that as "not a players file", the same answer it gives any other file it
  /// cannot parse.
  Future<String?> pickAndRead();

  /// Folder platforms only: the `.zibo.json` files in the folder, newest
  /// first. Empty if there are none or no folder.
  Future<List<TransferFileEntry>> listFiles();

  /// Folder platforms only: the text of [entry].
  Future<String> readFile(TransferFileEntry entry);
}

/// The channel `TransferPlugin.kt` answers on.
const MethodChannel transferChannel = MethodChannel('zibo/transfer');

/// Android: the Storage Access Framework's create and open dialogs, over
/// [transferChannel] (`PLAN-transfer.md` §3.3). Neither dialog needs a
/// permission, which is what keeps the release APK's permission list empty.
class ChannelTransferFiles implements TransferFiles {
  const ChannelTransferFiles();

  @override
  bool get usesSystemPicker => true;

  @override
  Future<String?> write(String fileName, String contents) {
    // Bytes, not a string: the platform side writes them straight to the chosen
    // document and has no business knowing the encoding.
    return transferChannel.invokeMethod<String>('create', <String, Object?>{
      'name': fileName,
      'bytes': Uint8List.fromList(utf8.encode(contents)),
    });
  }

  @override
  Future<String?> pickAndRead() async {
    final bytes = await transferChannel.invokeMethod<Uint8List>('open');
    if (bytes == null) return null;
    // Strict decoding: a binary file a parent picked by mistake should fail
    // here as a FormatException rather than load as replacement characters
    // that the JSON parser then rejects with a less specific error.
    return utf8.decode(bytes, allowMalformed: false);
  }

  @override
  Future<List<TransferFileEntry>> listFiles() =>
      throw UnsupportedError('ChannelTransferFiles loads through pickAndRead.');

  @override
  Future<String> readFile(TransferFileEntry entry) =>
      throw UnsupportedError('ChannelTransferFiles loads through pickAndRead.');
}

/// iOS and desktop: a plain folder (`PLAN-transfer.md` §3.3).
///
/// [folder] is a function rather than a path because `path_provider` resolves
/// it asynchronously and may have no answer; tests hand in a temp directory.
class FolderTransferFiles implements TransferFiles {
  const FolderTransferFiles(this.folder);

  /// Resolves the folder, or null on a platform that has none.
  final Future<Directory?> Function() folder;

  @override
  bool get usesSystemPicker => false;

  /// Throws [StateError] when there is no folder: unlike a dismissed dialog
  /// this is a failure, and returning null would tell the screen the parent had
  /// cancelled.
  ///
  /// A file of the same name is overwritten, not kept beside a ` (2)` copy. The
  /// name carries the date, so a collision means the same export was made
  /// again, and two near-identical files would leave a parent choosing between
  /// them with nothing to tell them apart.
  @override
  Future<String?> write(String fileName, String contents) async {
    final directory = await folder();
    if (directory == null) {
      throw StateError('No folder to save players files to on this platform.');
    }
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }
    await writeFileAtomically(File('${directory.path}/$fileName'), contents);
    return directory.path;
  }

  @override
  Future<String?> pickAndRead() =>
      throw UnsupportedError('FolderTransferFiles loads through listFiles.');

  @override
  Future<List<TransferFileEntry>> listFiles() async {
    final directory = await folder();
    if (directory == null || !directory.existsSync()) return const [];

    final entries = <TransferFileEntry>[];
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      // `endsWith`, so a half-written `<name>.zibo.json.tmp` left by a crash
      // mid-write (`writeFileAtomically`) is not offered as a file to load.
      if (!name.endsWith(_fileExtension)) continue;
      entries.add(
        TransferFileEntry(
          name: name,
          path: entity.path,
          modified: entity.lastModifiedSync(),
        ),
      );
    }
    entries.sort((a, b) => b.modified.compareTo(a.modified));
    return entries;
  }

  @override
  Future<String> readFile(TransferFileEntry entry) =>
      File(entry.path).readAsString();
}

/// Windows, macOS, Linux: `<Downloads>/Zibo Games`, the folder drawings already
/// export to, or null where `path_provider` knows no Downloads directory.
Future<Directory?> desktopTransferFolder() async {
  final downloads = await getDownloadsDirectory();
  if (downloads == null) return null;
  return Directory('${downloads.path}/$_desktopFolderName');
}

/// iOS: the app's Documents directory itself. That root, not a subfolder, is
/// what the Files app shows once `UIFileSharingEnabled` is set
/// (`PLAN-transfer.md` §3.3).
Future<Directory?> documentsTransferFolder() =>
    getApplicationDocumentsDirectory();
