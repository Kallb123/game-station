// Builds a players file from the repositories, and applies one
// (`PLAN-transfer.md` §3.1, §3.2).
//
// The codec next door knows the format; the repositories know where things
// live. This is the only place that holds both, and it is Flutter-free apart
// from the repository it is handed, so a screen calls three methods —
// [TransferService.exportText], [TransferService.read] and
// [TransferService.apply] — without knowing how any of it is stored.

import 'dart:convert';

import '../../../core/storage/progress_repository.dart';
import '../../../core/storage/save_data.dart';
import '../../draw/data/drawing_codec.dart';
import '../../draw/data/drawing_repository.dart';
import 'transfer_codec.dart';

/// One player in a file, and the local player loading it would overwrite.
class ImportCandidate {
  const ImportCandidate({required this.incoming, required this.replaces});

  /// The player as the file holds it. Its [Profile.id] is the file's id, the
  /// one [TransferService.apply] takes in `fileProfileIds`.
  final Profile incoming;

  /// The profile on this device that loading [incoming] replaces, or null when
  /// it would be added as a new player.
  final Profile? replaces;
}

/// Moves players between devices as text.
class TransferService {
  TransferService({
    required this.progress,
    required this.drawings,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final ProgressRepository progress;
  final DrawingRepository drawings;
  final DateTime Function() _now;

  /// Names a drawing file. Anything else in a players file — a separator, a
  /// `..` — would let a hand-edited file write outside the profile's folder.
  static final RegExp _safeDrawingId = RegExp(r'^[A-Za-z0-9_-]+$');

  /// The text of a players file for [profileId], or for every player when it
  /// is null.
  ///
  /// A drawing that is not a JSON object is left out rather than failing the
  /// export: it would be skipped on import anyway, and a parent should not
  /// lose a backup of nine pictures to a tenth that was already corrupt.
  Future<String> exportText({String? profileId}) async {
    final profiles = profileId == null
        ? progress.profiles
        : [_profile(profileId)];

    final byProfile = <String, Map<String, Map<String, Object?>>>{};
    for (final profile in profiles) {
      final parsed = <String, Map<String, Object?>>{};
      final raw = await drawings.readAllRaw(profile.id);
      for (final entry in raw.entries) {
        final Object? json;
        try {
          json = jsonDecode(entry.value);
        } on FormatException {
          continue;
        }
        if (json is Map<String, Object?>) parsed[entry.key] = json;
      }
      byProfile[profile.id] = parsed;
    }

    return encodeTransfer(
      TransferBundle(
        exportedAt: _now().toUtc(),
        everyone: profileId == null,
        settings: progress.settings,
        profiles: profiles,
        generatorVersion: progress.data.generatorVersion,
        drawings: byProfile,
      ),
    );
  }

  /// `zibo-players-2026-10-08.zibo.json`, or `zibo-<name>-…` for one player.
  ///
  /// The name is reduced to lower-case letters, digits and hyphens: it ends up
  /// in a file manager and in a save dialog on a platform whose rules about
  /// other characters this code does not know.
  String suggestedFileName({String? profileId}) {
    final who = profileId == null ? 'players' : _slug(_profile(profileId).name);
    final at = _now();
    final date =
        '${at.year.toString().padLeft(4, '0')}-'
        '${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')}';
    return 'zibo-$who-$date$transferFileExtension';
  }

  /// Parses a file's [text]. Throws [TransferException] for one this build
  /// will not load.
  TransferBundle read(String text) => decodeTransfer(text);

  /// Each player in [bundle], with the local player it would replace. Writes
  /// nothing.
  List<ImportCandidate> preview(TransferBundle bundle) {
    final plan = progress.planProfileImport(bundle.profiles);
    final local = {
      for (final profile in progress.profiles) profile.id: profile,
    };
    return [
      for (final entry in plan.entries)
        ImportCandidate(
          incoming: entry.incoming,
          replaces: entry.replaces ? local[entry.localId] : null,
        ),
    ];
  }

  /// Loads the players of [bundle] whose file ids are in [fileProfileIds],
  /// and the device settings too when [includeSettings] is set.
  ///
  /// Drawings are staged first, beside the live folders, under the final
  /// local ids; only when every one is written are they swapped in, and the
  /// save is changed last, in one mutation (`PLAN-transfer.md` §3.2). A
  /// failure while writing therefore propagates with the staging discarded,
  /// the live drawings of a profile being replaced intact, and the save
  /// untouched.
  ///
  /// A drawing is written as the file's own JSON rather than re-encoded:
  /// [decodeDrawing] has already shown this build can read it, and
  /// `encodeDrawing` would drop any field a newer build had added. One that
  /// fails to decode, or whose id is not its key, is skipped, as the gallery
  /// skips an unreadable file (`PLAN-phase-8.md` §4.5).
  ///
  /// Throws [ArgumentError] when no profile is selected, and [StateError] if
  /// the device's players changed while the drawings were being written.
  Future<void> apply(
    TransferBundle bundle, {
    required Set<String> fileProfileIds,
    required bool includeSettings,
  }) async {
    final chosen = [
      for (final profile in bundle.profiles)
        if (fileProfileIds.contains(profile.id)) profile,
    ];
    if (chosen.isEmpty) {
      throw ArgumentError.value(
        fileProfileIds,
        'fileProfileIds',
        'selects no profile in the file',
      );
    }

    var plan = progress.planProfileImport(chosen);

    // Stage every profile's drawings first; nothing live is touched until all
    // of them are written, so a failure here costs nothing but the staging.
    final staged = <String>[];
    final written = <String, Set<String>>{};
    try {
      for (final entry in plan.entries) {
        final localId = entry.localId;
        await drawings.startStaging(localId);
        staged.add(localId);

        final incoming = bundle.drawings[entry.incoming.id] ?? const {};
        final ids = <String>{};
        for (final id in (incoming.keys.toList()..sort())) {
          if (!_safeDrawingId.hasMatch(id)) continue;
          final text = jsonEncode(incoming[id]);
          try {
            if (decodeDrawing(text).id != id) continue;
          } on DrawingFormatException {
            continue;
          }
          await drawings.writeRawStaged(localId, id, text);
          ids.add(id);
        }
        written[localId] = ids;
      }

      // Swapping is renames and deletes inside one folder, the cheapest part
      // to do last. A failure part-way through leaves the profiles already
      // swapped with their new drawings and the save pointing at the old
      // counters, which loading the file again repairs.
      while (staged.isNotEmpty) {
        await drawings.commitStaged(staged.first);
        staged.removeAt(0);
      }
    } on Object {
      for (final localId in staged) {
        await drawings.discardStaged(localId);
      }
      rethrow;
    }

    for (final entry in plan.entries) {
      final localId = entry.localId;
      final draw = entry.incoming.draw;
      plan = plan.withDraw(
        localId,
        DrawProgress(
          drawingCount: _atLeastHighestId(draw.drawingCount, written[localId]!),
          lastDrawingId: written[localId]!.contains(draw.lastDrawingId)
              ? draw.lastDrawingId
              : null,
          bytesUsed: drawings.profileBytes(localId),
        ),
      );
    }

    progress.applyProfileImport(
      plan,
      settings: includeSettings ? bundle.settings : null,
    );
    await progress.flush();
  }

  Profile _profile(String id) => progress.profiles.firstWhere(
    (profile) => profile.id == id,
    orElse: () => throw ArgumentError.value(id, 'profileId', 'no such profile'),
  );

  /// [count], raised to the highest `d<n>` among [ids]. New drawing ids come
  /// from `drawingCount + 1` (`ProgressRepository.nextDrawingId`), so a file
  /// whose count trails its own drawings — only a hand-edited one can — would
  /// otherwise have the next drawing overwrite an imported one.
  static int _atLeastHighestId(int count, Set<String> ids) {
    var highest = count;
    for (final id in ids) {
      final match = RegExp(r'^d(\d+)$').firstMatch(id);
      final number = match == null ? 0 : int.parse(match.group(1)!);
      if (number > highest) highest = number;
    }
    return highest;
  }

  static String _slug(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'player' : slug;
  }
}
