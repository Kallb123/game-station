// The players file, as data (`PLAN-transfer.md` §3.1).
//
// Pure Dart, like `core/storage/save_codec.dart` — no Flutter, no `dart:io`,
// no `dart:ui` — so the format is testable without a filesystem and the
// platform edge that carries the text around never has to know what is in it.
//
// The file nests a save, produced and read by the save codec itself, rather
// than describing profiles a second time. That is what makes "everything a
// profile owns travels" true by construction: a field added to `Profile` and
// to the save codec is in the transfer file with no further change, and a
// migration step added to the save codec migrates an old players file too.
//
// Drawings are the one part this codec does not understand. Each is carried as
// an opaque JSON object; `TransferService` decodes them with `decodeDrawing`
// at import time, so this file does not depend on the draw feature, and a
// drawing a newer build wrote reaches the importer with every field intact.

import 'dart:convert';

import 'package:puzzle_engine/puzzle_engine.dart' as engine;

import '../../../core/storage/save_codec.dart';
import '../../../core/storage/save_data.dart';

/// The `format` value that marks a file as a players file at all.
const String transferFormat = 'zibo-games-players';

/// The version of this file layout, as distinct from the save schema nested in
/// it. Bumped when the keys around `save` change.
const int transferFormatVersion = 1;

/// What a players file's name ends with. Two dots because the second is what
/// a file manager shows as the type, and the first says which app's JSON it
/// is.
const String transferFileExtension = '.zibo.json';

/// Why a file was refused. Each value is answered with one sentence on screen;
/// the details below are for a log, not a child.
enum TransferProblem {
  /// Not JSON, not ours, or damaged: anything that does not read as a players
  /// file written by some version of this app.
  notAPlayersFile,

  /// Written by a newer build of the app than this one. Intact, and readable
  /// again after an update.
  fromNewerApp,

  /// Written by a build whose puzzle generator differs from this one's, so the
  /// in-progress puzzle ids in it would resolve to different boards.
  differentPuzzleVersion,
}

/// A players file this build will not load.
class TransferException implements Exception {
  const TransferException(this.problem, this.detail);

  final TransferProblem problem;

  /// What was wrong, for a log. Never shown to the player.
  final String detail;

  @override
  String toString() => 'TransferException(${problem.name}): $detail';
}

/// The contents of a players file.
///
/// Immutable and compared by value, like the save classes, so a test can say
/// "this file decodes to this bundle" in one line. The contained maps and lists
/// are not copied, so a caller does not mutate them.
class TransferBundle {
  TransferBundle({
    required this.exportedAt,
    required this.everyone,
    required this.settings,
    required this.profiles,
    this.generatorVersion = engine.generatorVersion,
    this.drawings = const {},
  }) : assert(profiles.isNotEmpty, 'a players file holds at least one profile'),
       assert(exportedAt.isUtc, 'exportedAt must be UTC');

  /// When the file was written, in UTC.
  final DateTime exportedAt;

  /// Whether this was a whole device rather than a chosen player. It decides
  /// whether importing applies [settings] by default (`PLAN-transfer.md` §1).
  final bool everyone;

  /// The device settings at export time.
  final AppSettings settings;

  /// The exported players, with the ids they had on the source device.
  final List<Profile> profiles;

  /// The puzzle generator that the in-progress puzzle ids in [profiles] belong
  /// to.
  final int generatorVersion;

  /// Profile id (as in [profiles]), then drawing id, then the drawing's parsed
  /// JSON. A profile with no drawings may be absent.
  final Map<String, Map<String, Map<String, Object?>>> drawings;

  @override
  bool operator ==(Object other) =>
      other is TransferBundle &&
      other.exportedAt == exportedAt &&
      other.everyone == everyone &&
      other.settings == settings &&
      other.generatorVersion == generatorVersion &&
      _listEquals(other.profiles, profiles) &&
      _jsonEquals(other.drawings, drawings);

  @override
  int get hashCode => Object.hash(
    exportedAt,
    everyone,
    settings,
    generatorVersion,
    Object.hashAll(profiles),
    // Counts only: equal bundles have equal counts, and hashing the pictures
    // themselves would walk megabytes for no benefit.
    Object.hashAllUnordered([
      for (final entry in drawings.entries)
        Object.hash(entry.key, entry.value.length),
    ]),
  );
}

/// Renders [bundle] as the text of a players file.
///
/// Keys named by the data — profile ids, drawing ids — are written sorted, as
/// `encodeSave` does, so the bytes are a function of the content and two
/// exports of one state are identical.
String encodeTransfer(TransferBundle bundle) {
  final profileIds = bundle.drawings.keys.toList()..sort();
  final drawings = <String, Object?>{};
  for (final profileId in profileIds) {
    final byId = bundle.drawings[profileId]!;
    final drawingIds = byId.keys.toList()..sort();
    drawings[profileId] = {for (final id in drawingIds) id: byId[id]};
  }

  return jsonEncode({
    'format': transferFormat,
    'formatVersion': transferFormatVersion,
    'exportedAt': bundle.exportedAt.toUtc().toIso8601String(),
    'everyone': bundle.everyone,
    // The active profile is not part of what moves; the first is the one the
    // save's invariant needs a name for.
    'save': saveToJson(
      SaveData(
        activeProfileId: bundle.profiles.first.id,
        profiles: bundle.profiles,
        settings: bundle.settings,
        generatorVersion: bundle.generatorVersion,
      ),
    ),
    'drawings': drawings,
  });
}

/// Parses [text] into a [TransferBundle].
///
/// Throws [TransferException] for anything this build will not load, and
/// nothing else: a bad file is an answer, not an error to propagate
/// (`PLAN-transfer.md` §1).
TransferBundle decodeTransfer(String text) {
  final Object? parsed;
  try {
    parsed = jsonDecode(text);
  } on FormatException catch (error) {
    throw TransferException(
      TransferProblem.notAPlayersFile,
      'not valid JSON (${error.message})',
    );
  }
  if (parsed is! Map<String, Object?>) {
    throw _notAFile('expected an object at the top level');
  }
  if (parsed['format'] != transferFormat) {
    throw _notAFile('"format" is not "$transferFormat"');
  }

  final version = parsed['formatVersion'];
  if (version is! int || version < 1) {
    throw _notAFile('"formatVersion" is not a positive integer');
  }
  if (version > transferFormatVersion) {
    throw TransferException(
      TransferProblem.fromNewerApp,
      'file format v$version, this build reads up to v$transferFormatVersion',
    );
  }

  final exportedAtText = parsed['exportedAt'];
  final everyone = parsed['everyone'];
  if (exportedAtText is! String) throw _notAFile('"exportedAt" is missing');
  if (everyone is! bool) throw _notAFile('"everyone" is missing');
  final exportedAt = DateTime.tryParse(exportedAtText);
  if (exportedAt == null) throw _notAFile('"exportedAt" is not a timestamp');

  final SaveData save;
  try {
    save = saveFromJson(parsed['save']);
  } on SaveFormatException catch (error) {
    throw _notAFile('save: $error');
  } on UnsupportedSaveVersion catch (error) {
    // Older than the oldest migration is not "from a newer app": nothing in
    // the file will ever become readable by updating.
    throw error.found > currentSchemaVersion
        ? TransferException(TransferProblem.fromNewerApp, '$error')
        : _notAFile('save: $error');
  }
  if (save.generatorVersion != engine.generatorVersion) {
    throw TransferException(
      TransferProblem.differentPuzzleVersion,
      'puzzle generator v${save.generatorVersion}, this build is '
      'v${engine.generatorVersion}',
    );
  }

  return TransferBundle(
    exportedAt: exportedAt.toUtc(),
    everyone: everyone,
    settings: save.settings,
    profiles: save.profiles,
    generatorVersion: save.generatorVersion,
    drawings: _readDrawings(parsed['drawings'], {
      for (final profile in save.profiles) profile.id,
    }),
  );
}

Map<String, Map<String, Map<String, Object?>>> _readDrawings(
  Object? raw,
  Set<String> profileIds,
) {
  if (raw is! Map<String, Object?>) {
    throw _notAFile('"drawings" is missing or not an object');
  }
  final drawings = <String, Map<String, Map<String, Object?>>>{};
  for (final MapEntry(key: profileId, value: byId) in raw.entries) {
    if (!profileIds.contains(profileId)) {
      throw _notAFile('"drawings" holds "$profileId", who is not in the file');
    }
    if (byId is! Map<String, Object?>) {
      throw _notAFile('drawings.$profileId is not an object');
    }
    final profileDrawings = <String, Map<String, Object?>>{};
    for (final MapEntry(key: drawingId, value: drawing) in byId.entries) {
      if (drawing is! Map<String, Object?>) {
        throw _notAFile('drawings.$profileId.$drawingId is not an object');
      }
      profileDrawings[drawingId] = drawing;
    }
    drawings[profileId] = profileDrawings;
  }
  return drawings;
}

TransferException _notAFile(String detail) =>
    TransferException(TransferProblem.notAPlayersFile, detail);

// --- value equality ---------------------------------------------------------

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Deep equality over parsed JSON: maps by key regardless of order, lists by
/// position, everything else by `==`.
bool _jsonEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_jsonEquals(a[key], b[key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_jsonEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}
