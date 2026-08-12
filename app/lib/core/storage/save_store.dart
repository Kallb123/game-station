// Where `save.json` lives, and the rules for reading and writing it.
//
// This is the only file in `core/storage` that touches a filesystem
// (PLAN-phase-1.md §5): the models and the codec above it stay pure, so their
// tests need no temp directory and a widget test can run against
// [MemorySaveStore] instead of a disk.
//
// Two failure modes drive the design (PLAN.md §5.3):
//
// 1. **An interrupted write must not corrupt the save.** Every write goes to
//    `save.json.tmp`, is flushed to disk, and is then renamed over `save.json`.
//    Rename is atomic, so a crash or a flat battery mid-write leaves either the
//    old file or the new one, never half of either.
// 2. **A save this build cannot read must not block boot.** A child cannot fix
//    a boot loop. Anything unreadable is moved aside and a fresh save takes its
//    place; the caller is told which happened so it can say so once, in words a
//    child can read.

import 'dart:io';

import 'save_codec.dart';
import 'save_data.dart';

/// The file the save is read from and written to.
const String saveFileName = 'save.json';

/// The half-written file a write goes to before it is renamed into place.
const String tempFileName = '$saveFileName.tmp';

/// Where a save that failed to decode is kept.
///
/// Kept rather than deleted: it costs a few kilobytes, and it is the only
/// evidence left of a bug that produced it.
const String corruptFileName = 'save.corrupt.json';

/// Where a save from a newer build is kept.
///
/// Separate from [corruptFileName] because the two differ in what a later
/// build can do with them: a newer save is intact and may be readable again
/// after an update, while a corrupt one never will be.
const String unsupportedFileName = 'save.unsupported.json';

/// Why [SaveStore.load] returned a fresh save instead of a stored one.
///
/// `null` — the normal case — means the stored save was read as written.
enum SaveRecovery {
  /// No save file. First launch, or the app's data was cleared. Not an error.
  missing,

  /// The file did not decode: malformed JSON, a missing field, a field of the
  /// wrong type, or a file that could not be read at all.
  corrupt,

  /// The file's `schemaVersion` is newer than this build reads.
  unsupportedVersion,
}

/// The result of a load: the save to use, and why it is not the stored one.
class SaveLoad {
  const SaveLoad(this.data, {this.recovery});

  /// The save to run with. Never null — a recovery yields defaults, not an
  /// error, so no caller has a "there is no save" branch to write.
  final SaveData data;

  /// Null when [data] came from a stored save that decoded cleanly.
  final SaveRecovery? recovery;

  /// Whether the player lost progress they might remember having.
  ///
  /// [SaveRecovery.missing] is excluded: a first launch has nothing to lose,
  /// and telling a child their games are gone the first time they open the app
  /// would be both frightening and false.
  bool get lostProgress =>
      recovery == SaveRecovery.corrupt ||
      recovery == SaveRecovery.unsupportedVersion;
}

/// Reads and writes the save.
///
/// An interface with two implementations so that everything above it — the
/// repository, the providers, every widget test — can run without a
/// filesystem. It is also the seam `PLAN.md` §2 names for swapping the JSON
/// file for a database if the data ever outgrows it.
abstract interface class SaveStore {
  /// Reads the stored save, recovering to defaults rather than throwing.
  Future<SaveLoad> load();

  /// Writes [data], replacing whatever is stored.
  Future<void> write(SaveData data);
}

/// A [SaveStore] over a directory — in the app, the one `path_provider`
/// resolves for application support.
class FileSaveStore implements SaveStore {
  FileSaveStore(this.directory, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// Where the save files live.
  final Directory directory;

  /// The clock a fresh save's `createdAt` is read from.
  ///
  /// Injected so the tests are deterministic. It is a clock, not a source of
  /// randomness: PLAN-phase-1.md §1 bans `Random` from `lib/`, and profile ids
  /// come from a counter for that reason, but a creation timestamp has to come
  /// from somewhere.
  final DateTime Function() _now;

  // Joined with a forward slash rather than with `package:path`, which is not a
  // declared dependency. Windows accepts `/` in a path as readily as `\`, and
  // these paths are only ever handed back to `dart:io`, never shown to anyone.
  File get _saveFile => File('${directory.path}/$saveFileName');
  File get _tempFile => File('${directory.path}/$tempFileName');

  @override
  Future<SaveLoad> load() async {
    // A leftover temp file is the remains of an interrupted write, and there is
    // no way to tell a complete one from a truncated one. `save.json` is intact
    // either way — that is what the rename buys — so the temp file is deleted
    // unread rather than salvaged.
    _deleteQuietly(_tempFile);

    final file = _saveFile;
    if (!file.existsSync()) {
      return SaveLoad(_fresh(), recovery: SaveRecovery.missing);
    }

    final String text;
    try {
      text = await file.readAsString();
    } on FileSystemException {
      // Unreadable rather than unparseable — a permission or hardware problem.
      // Reported as corrupt because the player-facing outcome is the same, but
      // deliberately *not* moved aside: a file we could not read is a file we
      // should not destroy, and a move would most likely fail too.
      return SaveLoad(_fresh(), recovery: SaveRecovery.corrupt);
    }

    try {
      return SaveLoad(decodeSave(text));
    } on SaveFormatException {
      await _moveAside(file, corruptFileName);
      return SaveLoad(_fresh(), recovery: SaveRecovery.corrupt);
    } on UnsupportedSaveVersion {
      await _moveAside(file, unsupportedFileName);
      return SaveLoad(_fresh(), recovery: SaveRecovery.unsupportedVersion);
    }
    // A StateError from the migration chain is deliberately not caught: it
    // means a migration step in this repository is wrong, not that the file is
    // bad, and moving a perfectly good save aside would turn our bug into the
    // player's data loss (`save_codec.dart`).
  }

  @override
  Future<void> write(SaveData data) async {
    if (!directory.existsSync()) {
      await directory.create(recursive: true);
    }

    final temp = _tempFile;
    final handle = await temp.open(mode: FileMode.writeOnly);
    try {
      await handle.writeString(encodeSave(data));
      // Flushed before the rename, not after: renaming a file whose contents
      // are still in a buffer would publish an empty save if the power went at
      // the wrong moment.
      await handle.flush();
    } finally {
      await handle.close();
    }
    await temp.rename(_saveFile.path);
  }

  SaveData _fresh() => SaveData.initial(createdAt: _now());

  /// Moves [file] to [name] in the same directory, replacing any previous one.
  ///
  /// Best effort. Failing to keep a copy of an unreadable save is not a reason
  /// to fail the launch that recovers from it, so the error is swallowed —
  /// [load] has already decided to start fresh either way.
  Future<void> _moveAside(File file, String name) async {
    try {
      await file.rename('${directory.path}/$name');
    } on FileSystemException {
      _deleteQuietly(file);
    }
  }

  void _deleteQuietly(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Nothing to do and nothing worth saying: the caller's next write will
      // replace it.
    }
  }
}

/// A [SaveStore] that keeps the save in memory.
///
/// For tests: a widget test gets the real codec and the real repository over a
/// store with no filesystem, no temp directory to clean up, and a [writes]
/// counter for asserting that the debounce actually coalesces.
///
/// The save is held as encoded text rather than as a [SaveData], so a test
/// running against this store exercises encode and decode exactly as the file
/// store does. A model that fails to round trip fails here too.
class MemorySaveStore implements SaveStore {
  MemorySaveStore({
    SaveData? initial,
    SaveRecovery? recovery,
    DateTime Function()? now,
  }) : _text = initial == null ? null : encodeSave(initial),
       _recovery = recovery ?? (initial == null ? SaveRecovery.missing : null),
       _now = now ?? DateTime.now;

  String? _text;

  /// Reported by every [load], not only the first. The app loads once, before
  /// `runApp`, so nothing depends on it clearing itself; a test that wants a
  /// clean second load builds a second store.
  final SaveRecovery? _recovery;

  final DateTime Function() _now;

  /// How many times [write] has been called.
  int writes = 0;

  /// The encoded save as it stands, or null if nothing has been stored.
  String? get contents => _text;

  @override
  Future<SaveLoad> load() async {
    final text = _text;
    if (text == null) {
      return SaveLoad(
        SaveData.initial(createdAt: _now()),
        recovery: _recovery ?? SaveRecovery.missing,
      );
    }
    return SaveLoad(decodeSave(text), recovery: _recovery);
  }

  @override
  Future<void> write(SaveData data) async {
    writes++;
    _text = encodeSave(data);
  }
}
