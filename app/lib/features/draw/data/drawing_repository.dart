// Where a drawing lives on disk, and the rules for reading, writing and
// listing them (`PLAN-phase-8.md` §4.5).
//
// One file per drawing, `drawings/<profileId>/<id>.json`, under the same
// application-support directory `save.json` lives in — `FileSaveStore`'s own
// directory, handed to this repository rather than resolved a second time.
// Written through `writeFileAtomically`, the same tmp-then-rename helper
// `FileSaveStore` uses, for the same reason: a tablet that dies mid-write
// costs the last stroke, not the picture.
//
// Why a drawing is not a row in `save.json`: `PLAN.md` §5.2's few-kilobyte
// target, and blast radius — a corrupt drawing file is moved aside and costs
// one picture, the way a corrupt `save.json` costs a fresh start, but never
// the other way around (`PLAN-phase-8.md` §4.5).

import 'dart:convert';
import 'dart:io';

import '../../../core/storage/atomic_write.dart';
import '../model/stroke.dart';
import 'drawing_codec.dart';

/// Reads and writes one profile's drawings under [root].
///
/// [root] is the application-support directory `save.json` lives in, not the
/// `drawings/` folder itself — this class owns that layout the way
/// `FileSaveStore` owns `save.json`'s name, so a caller never spells
/// `drawings/<id>` by hand.
class DrawingRepository {
  const DrawingRepository(this.root);

  /// The application-support directory, shared with `FileSaveStore`.
  final Directory root;

  Directory _profileDir(String profileId) =>
      Directory('${root.path}/drawings/$profileId');

  File _drawingFile(String profileId, String drawingId) =>
      File('${_profileDir(profileId).path}/$drawingId.json');

  /// Bytes [drawing] would take on disk once encoded — what a caller checks
  /// against the profile's 64 MB budget before calling [save]
  /// (`PLAN.md` §8, `PLAN-phase-8.md` §4.5). Not itself enforced here: the
  /// budget is compared against `Profile.draw.bytesUsed`, which this
  /// repository has no access to.
  int encodedSize(Drawing drawing) =>
      utf8.encode(encodeDrawing(drawing)).length;

  /// Writes [drawing] under [profileId], replacing whatever was there.
  Future<void> save(String profileId, Drawing drawing) async {
    final dir = _profileDir(profileId);
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    await writeFileAtomically(
      _drawingFile(profileId, drawing.id),
      encodeDrawing(drawing),
    );
  }

  /// Reads the drawing [drawingId] of [profileId], or null when there is no
  /// such file or it does not decode.
  ///
  /// A decode failure is swallowed rather than thrown, matching
  /// `SaveStore.load`'s recovery: the caller cannot tell "missing" from
  /// "corrupt" from this alone, but both mean the same thing to a screen that
  /// only has one picture to show or not show.
  Future<Drawing?> load(String profileId, String drawingId) async {
    final file = _drawingFile(profileId, drawingId);
    if (!file.existsSync()) return null;
    try {
      return decodeDrawing(await file.readAsString());
    } on DrawingFormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  /// Deletes the drawing [drawingId] of [profileId]. Does nothing if it does
  /// not exist.
  Future<void> delete(String profileId, String drawingId) async {
    final file = _drawingFile(profileId, drawingId);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// The bytes every one of [profileId]'s drawings takes on disk right now —
  /// what a caller writes into `DrawProgress.bytesUsed` after a save or a
  /// delete (`ProgressRepository.recordDrawingSaved`,
  /// `.recordDrawingDeleted`).
  ///
  /// Summed from [File.lengthSync] over the profile's folder rather than
  /// tracked as a running total: `PLAN-phase-8.md` §4.5 keeps a running total
  /// and heals it with an occasional directory walk, but a stat call per file
  /// is cheap enough that this repository walks on every mutation instead —
  /// simpler, and a number that can never drift from what is actually stored
  /// needs no healing step to begin with. A profile with the phase's own 64
  /// MB budget's worth of drawings is at most a few hundred files, so the
  /// walk costs a few hundred stat syscalls, not a content read.
  int profileBytes(String profileId) {
    final dir = _profileDir(profileId);
    if (!dir.existsSync()) return 0;

    var total = 0;
    for (final entity in dir.listSync()) {
      if (entity is File) total += entity.lengthSync();
    }
    return total;
  }

  /// Every drawing of [profileId] that decodes cleanly, in no particular
  /// order — a caller sorts by [Drawing.createdAt] or by id, rather than
  /// trusting the order a filesystem happens to list entries in.
  ///
  /// A drawing that fails to decode is left off the list rather than
  /// surfacing an error: `AGENTS.md`'s rule is that a child never sees an
  /// internal error, and a missing picture in a grid is self-explanatory in
  /// a way an error card is not (`PLAN-phase-8.md` §4.5).
  Future<List<Drawing>> listDecodable(String profileId) async {
    final dir = _profileDir(profileId);
    if (!dir.existsSync()) return const [];

    final drawings = <Drawing>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        drawings.add(decodeDrawing(await entity.readAsString()));
      } on DrawingFormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }
    return drawings;
  }
}
