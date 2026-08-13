// Reading and writing `save.json`.
//
// Like `save_data.dart`, this file imports neither `dart:io` nor Flutter
// (PLAN-phase-1.md §1): it turns a string into a [SaveData] and back. The store
// that reads and writes the actual file arrives in the next PR, and is the only
// part of this layer that touches a filesystem.
//
// Three decisions shape everything below (PLAN-phase-1.md §4.2):
//
// 1. **Strict about types, lenient about missing optional fields.** A missing
//    `settings` block yields defaults; a `settings` block whose `sound` is the
//    string `"true"` is a format error. Coercing it would hide the bug that
//    wrote it, and the recovery path already turns a format error into a fresh
//    start rather than a crash.
// 2. **A version above [currentSchemaVersion] is refused, not guessed at.**
//    Guessing at a newer file's meaning is how data is destroyed silently.
// 3. **Migration is a chain of single-step functions**, so each step is
//    testable against a fixture on its own.

import 'dart:convert';

import 'save_data.dart';

/// The save file is not what this build can read: a missing field, a field of
/// the wrong type, or JSON that does not parse.
///
/// The store's answer is to move the file aside and start fresh
/// (PLAN-phase-1.md §4.3), so throwing here costs a child their progress but
/// never a working app.
class SaveFormatException implements Exception {
  const SaveFormatException(this.message, [this.path = '']);

  /// What was wrong, in a sentence.
  final String message;

  /// Where, as a dotted path from the document root — `profiles[0].name`.
  /// Empty for the root itself. Worth carrying: "expected a string" is a
  /// support question, "profiles[0].name: expected a string" is a bug report.
  final String path;

  @override
  String toString() => path.isEmpty
      ? 'SaveFormatException: $message'
      : 'SaveFormatException: $path: $message';
}

/// The save file's `schemaVersion` is one this build cannot reach.
///
/// Either it is newer than [currentSchemaVersion] — a downgrade after a test
/// build — or it is older than the oldest version [migrationSteps] can read.
///
/// Deliberately not a subtype of [SaveFormatException]: the store keeps the two
/// files apart (`save.unsupported.json` and `save.corrupt.json`), because a
/// newer save is intact and may be readable again after an update, while a
/// corrupt one never will be.
class UnsupportedSaveVersion implements Exception {
  const UnsupportedSaveVersion({
    required this.found,
    this.supported = currentSchemaVersion,
  });

  /// The version in the file.
  final int found;

  /// The version this build writes.
  final int supported;

  @override
  String toString() =>
      'UnsupportedSaveVersion: the save is schema v$found, this build reads '
      'up to v$supported';
}

/// One step of the migration chain: reads a save of version *n*, returns the
/// same data as version *n + 1*, including the bumped `schemaVersion`.
typedef MigrationStep = Map<String, Object?> Function(Map<String, Object?> raw);

/// The migration chain, keyed by the version each step reads.
///
/// Empty: v1 is the first schema that ever shipped, so there is nothing older
/// to read. It exists anyway because [migrate]'s loop is the part with a silent
/// failure mode — a bug in it stays invisible until the day a real step is
/// added, which is the day it would eat somebody's save. `save_codec_test.dart`
/// drives the loop with a synthetic step for that reason.
const Map<int, MigrationStep> migrationSteps = <int, MigrationStep>{};

/// What a save with no `generatorVersion` is assumed to have been written by.
///
/// Only a hand-edited file can be missing it — [encodeSave] always writes one —
/// and generator 1 is the only one that has ever existed, so this fills in the
/// sole possibility rather than the likeliest of several.
const int _firstGeneratorVersion = 1;

/// Parses [json] into a [SaveData], migrating older versions on the way.
///
/// Throws [SaveFormatException] if the text is not a save this build can read,
/// or [UnsupportedSaveVersion] if its schema version is out of range.
SaveData decodeSave(String json) {
  final Object? parsed;
  try {
    parsed = jsonDecode(json);
  } on FormatException catch (error) {
    throw SaveFormatException('not valid JSON (${error.message})');
  }
  return _readSave(migrate(_map(parsed, '')));
}

/// Renders [data] as the text to write to `save.json`.
///
/// Keys of the maps whose names come from the data — puzzle ids, game ids —
/// are sorted, so the bytes are a function of the content alone and not of the
/// order the app happened to insert things in. That makes two saves with the
/// same content compare equal as bytes, and makes a hand-diff of the file
/// during development readable.
String encodeSave(SaveData data) => jsonEncode(_writeSave(data));

/// Brings [raw] up to [currentSchemaVersion] by applying [steps] in order.
///
/// [steps] is injectable only so the loop can be tested before a real step
/// exists; production callers take the default.
Map<String, Object?> migrate(
  Map<String, Object?> raw, {
  Map<int, MigrationStep> steps = migrationSteps,
}) {
  var current = raw;
  var version = _int(_required(current, 'schemaVersion', ''), 'schemaVersion');

  if (version > currentSchemaVersion) {
    throw UnsupportedSaveVersion(found: version);
  }

  while (version < currentSchemaVersion) {
    final step = steps[version];
    if (step == null) throw UnsupportedSaveVersion(found: version);

    current = step(current);
    final next = _int(_required(current, 'schemaVersion', ''), 'schemaVersion');
    // A step that forgets to bump the version would spin here forever. That is
    // a mistake in this repository rather than bad data, so it is a StateError
    // and not a SaveFormatException — the store must not treat it as a corrupt
    // save and quietly delete the file.
    if (next <= version) {
      throw StateError(
        'the migration step for schema v$version left the version at v$next',
      );
    }
    version = next;
  }

  return current;
}

// --- reading ----------------------------------------------------------------

SaveData _readSave(Map<String, Object?> raw) {
  final profilesRaw = _list(_required(raw, 'profiles', ''), 'profiles');
  if (profilesRaw.isEmpty) {
    throw const SaveFormatException(
      'a save must contain at least one profile',
      'profiles',
    );
  }
  final profiles = [
    for (var i = 0; i < profilesRaw.length; i++)
      _readProfile(_map(profilesRaw[i], 'profiles[$i]'), 'profiles[$i]'),
  ];

  final ids = profiles.map((profile) => profile.id).toList();
  if (ids.toSet().length != ids.length) {
    throw const SaveFormatException('profile ids must be unique', 'profiles');
  }

  // The one place decoding repairs rather than refuses. An activeProfileId that
  // names nobody — or is missing entirely — is not a malformed file, it is a
  // stale pointer with an obvious and lossless fix; refusing it would move every
  // profile aside over one wrong string. A pointer of the wrong *type* is still
  // an error, because that says something other than this app wrote the file.
  final storedActiveId = raw['activeProfileId'] == null
      ? null
      : _string(raw['activeProfileId'], 'activeProfileId');
  final activeProfileId = ids.contains(storedActiveId)
      ? storedActiveId!
      : ids.first;

  return SaveData(
    generatorVersion: _optInt(
      raw,
      'generatorVersion',
      '',
      _firstGeneratorVersion,
    ),
    activeProfileId: activeProfileId,
    settings: _readSettings(_optMap(raw, 'settings', ''), 'settings'),
    profiles: profiles,
    puzzleCache: _readStringMap(_optMap(raw, 'puzzleCache', ''), 'puzzleCache'),
  );
}

AppSettings _readSettings(Map<String, Object?> raw, String path) => AppSettings(
  sound: _optBool(raw, 'sound', path, true),
  music: _optBool(raw, 'music', path, false),
  haptics: _optBool(raw, 'haptics', path, true),
  showTimer: _optBool(raw, 'showTimer', path, false),
  theme: raw['theme'] == null
      ? ThemeChoice.system
      : _enum(
          ThemeChoice.values,
          _string(raw['theme'], _at(path, 'theme')),
          _at(path, 'theme'),
        ),
  reduceMotion: _optBool(raw, 'reduceMotion', path, false),
);

Profile _readProfile(Map<String, Object?> raw, String path) => Profile(
  id: _string(_required(raw, 'id', path), _at(path, 'id')),
  name: _string(_required(raw, 'name', path), _at(path, 'name')),
  avatar: _enum(
    AvatarId.values,
    _string(_required(raw, 'avatar', path), _at(path, 'avatar')),
    _at(path, 'avatar'),
  ),
  createdAt: _dateTime(
    _required(raw, 'createdAt', path),
    _at(path, 'createdAt'),
  ),
  sudoku: _readSudoku(_optMap(raw, 'sudoku', path), _at(path, 'sudoku')),
  arcade: _readArcade(_optMap(raw, 'arcade', path), _at(path, 'arcade')),
  mistakeFeedback: raw['mistakeFeedback'] == null
      ? MistakeFeedback.immediate
      : _enum(
          MistakeFeedback.values,
          _string(raw['mistakeFeedback'], _at(path, 'mistakeFeedback')),
          _at(path, 'mistakeFeedback'),
        ),
);

SudokuProgress _readSudoku(Map<String, Object?> raw, String path) =>
    SudokuProgress(
      solved: _readMapOf(
        _optMap(raw, 'solved', path),
        _at(path, 'solved'),
        _readSolvedPuzzle,
      ),
      inProgress: _readMapOf(
        _optMap(raw, 'inProgress', path),
        _at(path, 'inProgress'),
        _readPuzzleInProgress,
      ),
      dailyStreak: _readStreak(
        _optMap(raw, 'dailyStreak', path),
        _at(path, 'dailyStreak'),
      ),
      bestTimeMs: _readIntMap(
        _optMap(raw, 'bestTimeMs', path),
        _at(path, 'bestTimeMs'),
      ),
    );

SolvedPuzzle _readSolvedPuzzle(Map<String, Object?> raw, String path) =>
    SolvedPuzzle(
      timeMs: _int(_required(raw, 'timeMs', path), _at(path, 'timeMs')),
      hints: _optInt(raw, 'hints', path, 0),
      mistakes: _optInt(raw, 'mistakes', path, 0),
      solvedAt: raw['solvedAt'] == null
          ? null
          : _dateTime(raw['solvedAt'], _at(path, 'solvedAt')),
      clean: _optBool(raw, 'clean', path, false),
    );

PuzzleInProgress _readPuzzleInProgress(Map<String, Object?> raw, String path) =>
    PuzzleInProgress(
      grid: _string(_required(raw, 'grid', path), _at(path, 'grid')),
      notes: raw['notes'] == null
          ? ''
          : _string(raw['notes'], _at(path, 'notes')),
      elapsedMs: _optInt(raw, 'elapsedMs', path, 0),
      undoStack: _readStringList(raw['undoStack'], _at(path, 'undoStack')),
      hints: _optInt(raw, 'hints', path, 0),
    );

DailyStreak _readStreak(Map<String, Object?> raw, String path) => DailyStreak(
  current: _optInt(raw, 'current', path, 0),
  best: _optInt(raw, 'best', path, 0),
  lastDayIndex: raw['lastDayIndex'] == null
      ? null
      : _int(raw['lastDayIndex'], _at(path, 'lastDayIndex')),
);

ArcadeProgress _readArcade(Map<String, Object?> raw, String path) =>
    ArcadeProgress(games: _readMapOf(raw, path, _readArcadeGame));

ArcadeGameProgress _readArcadeGame(Map<String, Object?> raw, String path) {
  final scoresPath = _at(path, 'highScores');
  final scoresRaw = raw['highScores'] == null
      ? const <Object?>[]
      : _list(raw['highScores'], scoresPath);
  return ArcadeGameProgress(
    highScores: [
      for (var i = 0; i < scoresRaw.length; i++)
        _readHighScore(
          _map(scoresRaw[i], '$scoresPath[$i]'),
          '$scoresPath[$i]',
        ),
    ],
    gamesPlayed: _optInt(raw, 'gamesPlayed', path, 0),
    totalKills: _optInt(raw, 'totalKills', path, 0),
  );
}

HighScore _readHighScore(Map<String, Object?> raw, String path) => HighScore(
  score: _int(_required(raw, 'score', path), _at(path, 'score')),
  wave: _optInt(raw, 'wave', path, 0),
  at: raw['at'] == null ? null : _dateTime(raw['at'], _at(path, 'at')),
);

// --- writing ----------------------------------------------------------------

Map<String, Object?> _writeSave(SaveData data) => {
  'schemaVersion': data.schemaVersion,
  'generatorVersion': data.generatorVersion,
  'activeProfileId': data.activeProfileId,
  'settings': _writeSettings(data.settings),
  'profiles': [for (final profile in data.profiles) _writeProfile(profile)],
  'puzzleCache': _sorted(data.puzzleCache, (String value) => value),
};

Map<String, Object?> _writeSettings(AppSettings settings) => {
  'sound': settings.sound,
  'music': settings.music,
  'haptics': settings.haptics,
  'showTimer': settings.showTimer,
  'theme': settings.theme.name,
  'reduceMotion': settings.reduceMotion,
};

Map<String, Object?> _writeProfile(Profile profile) => {
  'id': profile.id,
  'name': profile.name,
  'avatar': profile.avatar.name,
  'createdAt': _writeDateTime(profile.createdAt),
  'sudoku': _writeSudoku(profile.sudoku),
  'arcade': _sorted(profile.arcade.games, _writeArcadeGame),
  'mistakeFeedback': profile.mistakeFeedback.name,
};

Map<String, Object?> _writeSudoku(SudokuProgress sudoku) => {
  'solved': _sorted(sudoku.solved, _writeSolvedPuzzle),
  'inProgress': _sorted(sudoku.inProgress, _writePuzzleInProgress),
  'dailyStreak': {
    'current': sudoku.dailyStreak.current,
    'best': sudoku.dailyStreak.best,
    if (sudoku.dailyStreak.lastDayIndex != null)
      'lastDayIndex': sudoku.dailyStreak.lastDayIndex,
  },
  'bestTimeMs': _sorted(sudoku.bestTimeMs, (int value) => value),
};

Map<String, Object?> _writeSolvedPuzzle(SolvedPuzzle solved) => {
  'timeMs': solved.timeMs,
  'hints': solved.hints,
  'mistakes': solved.mistakes,
  if (solved.solvedAt != null) 'solvedAt': _writeDateTime(solved.solvedAt!),
  'clean': solved.clean,
};

Map<String, Object?> _writePuzzleInProgress(PuzzleInProgress puzzle) => {
  'grid': puzzle.grid,
  'notes': puzzle.notes,
  'elapsedMs': puzzle.elapsedMs,
  'undoStack': puzzle.undoStack,
  'hints': puzzle.hints,
};

Map<String, Object?> _writeArcadeGame(ArcadeGameProgress game) => {
  'highScores': [
    for (final score in game.highScores)
      {
        'score': score.score,
        'wave': score.wave,
        if (score.at != null) 'at': _writeDateTime(score.at!),
      },
  ],
  'gamesPlayed': game.gamesPlayed,
  'totalKills': game.totalKills,
};

/// UTC and ISO-8601, matching the reason `PLAN.md` §3.2 gives for indexing days
/// in UTC: a save moved between timezones must not shift a date.
String _writeDateTime(DateTime value) => value.toUtc().toIso8601String();

Map<String, Object?> _sorted<V extends Object>(
  Map<String, V> source,
  Object? Function(V value) write,
) {
  final keys = source.keys.toList()..sort();
  return {for (final key in keys) key: write(source[key] as V)};
}

// --- typed readers ----------------------------------------------------------

String _at(String path, String key) => path.isEmpty ? key : '$path.$key';

Never _fail(String path, String message) =>
    throw SaveFormatException(message, path);

Object? _required(Map<String, Object?> raw, String key, String path) {
  final value = raw[key];
  if (value == null) _fail(_at(path, key), 'is required');
  return value;
}

Map<String, Object?> _map(Object? value, String path) =>
    value is Map<String, Object?>
    ? value
    : _fail(path, 'expected an object, got ${_typeName(value)}');

List<Object?> _list(Object? value, String path) => value is List<Object?>
    ? value
    : _fail(path, 'expected a list, got ${_typeName(value)}');

String _string(Object? value, String path) => value is String
    ? value
    : _fail(path, 'expected a string, got ${_typeName(value)}');

/// Strict about `bool` rather than accepting `0`, `1`, `"true"`: every one of
/// those means this file was written by something other than [encodeSave], and
/// the interesting question is what, not how to keep going.
bool _bool(Object? value, String path) => value is bool
    ? value
    : _fail(path, 'expected true or false, got ${_typeName(value)}');

/// Rejects `1.0` as well as `"1"`. JSON has one number type, but `jsonDecode`
/// hands back an `int` for anything written without a decimal point, so a
/// `double` here means the value was not an integer when it was written.
int _int(Object? value, String path) => value is int
    ? value
    : _fail(path, 'expected an integer, got ${_typeName(value)}');

DateTime _dateTime(Object? value, String path) {
  final text = _string(value, path);
  final DateTime parsed;
  try {
    parsed = DateTime.parse(text);
  } on FormatException {
    throw SaveFormatException('"$text" is not an ISO-8601 timestamp', path);
  }
  // Normalised rather than rejected when the string carries no zone: the
  // instant is what matters, and the models compare UTC to UTC.
  return parsed.toUtc();
}

T _enum<T extends Enum>(List<T> values, String name, String path) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  // Refused rather than defaulted. A value this build does not know is either a
  // newer save — which `schemaVersion` is supposed to have caught — or a
  // corrupt one, and silently substituting a fox for an unknown avatar hides
  // both.
  _fail(
    path,
    '"$name" is not one of ${values.map((value) => value.name).join(', ')}',
  );
}

/// A missing or null value falls back to [fallback]; a present one of the wrong
/// type is still an error.
Map<String, Object?> _optMap(
  Map<String, Object?> raw,
  String key,
  String path,
) => raw[key] == null ? const {} : _map(raw[key], _at(path, key));

bool _optBool(
  Map<String, Object?> raw,
  String key,
  String path,
  bool fallback,
) => raw[key] == null ? fallback : _bool(raw[key], _at(path, key));

int _optInt(Map<String, Object?> raw, String key, String path, int fallback) =>
    raw[key] == null ? fallback : _int(raw[key], _at(path, key));

Map<String, T> _readMapOf<T>(
  Map<String, Object?> raw,
  String path,
  T Function(Map<String, Object?> raw, String path) read,
) => {
  for (final entry in raw.entries)
    entry.key: read(
      _map(entry.value, _at(path, entry.key)),
      _at(path, entry.key),
    ),
};

Map<String, String> _readStringMap(Map<String, Object?> raw, String path) => {
  for (final entry in raw.entries)
    entry.key: _string(entry.value, _at(path, entry.key)),
};

Map<String, int> _readIntMap(Map<String, Object?> raw, String path) => {
  for (final entry in raw.entries)
    entry.key: _int(entry.value, _at(path, entry.key)),
};

List<String> _readStringList(Object? value, String path) {
  if (value == null) return const [];
  final items = _list(value, path);
  return [
    for (var i = 0; i < items.length; i++) _string(items[i], '$path[$i]'),
  ];
}

/// Names a JSON value's kind for an error message.
///
/// Hand-written rather than `runtimeType`: the analyzer bans `Type.toString()`
/// (`avoid_type_to_string`), and `_InternalLinkedHashMap<String, dynamic>`
/// would not have told a reader anything anyway.
String _typeName(Object? value) => switch (value) {
  null => 'null',
  bool() => 'true or false',
  int() => 'an integer',
  double() => 'a fractional number',
  String() => 'a string',
  List<Object?>() => 'a list',
  Map<String, Object?>() => 'an object',
  _ => 'an unexpected value',
};
