// The save file's shape, as plain Dart data.
//
// Nothing here imports `dart:io` or Flutter (PLAN-phase-1.md §1), so the schema
// is testable without a filesystem and a widget test can build a save by hand.
// JSON lives next door in `save_codec.dart`: these classes say what is stored,
// the codec says how it is written.
//
// Schema v1 is declared in full, including the fields phases 3 and 4 will write
// and nothing writes yet (PLAN-phase-1.md §4.2). Declaring them now is what
// keeps v1 final — adding them in phase 3 would mean migrating a file that had
// already shipped.
//
// Every class here is immutable and compares by value. The value equality is
// what lets a test say "this file decodes to this object" in one line, and what
// lets the repository decide whether a mutation actually changed anything
// before it schedules a write.

import 'package:puzzle_engine/puzzle_engine.dart' as engine;

/// The version of the save format this build writes.
///
/// Bumped when the shape of the file changes, together with a migration step
/// that reads the previous version (`save_codec.dart`).
const int currentSchemaVersion = 1;

/// The id of the profile a first launch starts with.
const String firstProfileId = 'p1';

/// Which theme the player chose.
///
/// `system` is not in `PLAN.md` §5.2's example, which predates the decision in
/// PLAN-phase-1.md §4.1; §5.2 is updated in phase 1's last PR. It is the
/// default because a device that is already in night mode should not have to be
/// told twice.
enum ThemeChoice { day, night, system }

/// The avatar shown for a profile.
///
/// A fixed enum rather than free text or a file name: the icon and colour a
/// value maps to are chosen in the UI layer, so art can change later without
/// touching a saved file. Animals only — a child picks their profile by the
/// picture, not by reading the name.
enum AvatarId { fox, bear, cat, dog, frog, owl, panda, rabbit }

/// When a wrong Sudoku digit is flagged.
///
/// Per profile rather than device-wide, unlike every other setting
/// (`AppSettings`'s own rationale): a younger sibling wants to know at once,
/// an older one may not want to be told before they have finished the grid.
enum MistakeFeedback {
  /// Flagged the moment it is entered. The default (`PLAN.md` §3.7).
  immediate,

  /// Flagged only once the grid is full.
  atCompletion,
}

/// Which side of the on-screen pad holds LEFT and RIGHT.
///
/// Per profile rather than device-wide, the same reasoning as
/// [MistakeFeedback]: handedness belongs to the child holding the tablet, not
/// to the tablet itself (`PLAN-phase-4.md` §4.9).
enum PadSide {
  /// LEFT and RIGHT bottom-left, FIRE bottom-right. The default
  /// (`PLAN.md` §4.2).
  right,

  /// The mirror image, for a left-handed player.
  left,
}

/// How hard [AppSettings] buzzes. Replaces the plain on/off `haptics` bool
/// PR 5 first shipped, once a device pass found every call too faint to feel
/// reliably (`PLAN-phase-5.md` §4.5) — `core/haptics.dart` climbs a four-rung
/// ladder, and this is how far up it starts.
enum HapticsLevel {
  /// No buzz anywhere, on any event.
  off,

  /// The default. Already a step up from the single tier PR 5 first shipped.
  low,
  medium,

  /// The strongest single rung `HapticFeedback` offers, repeated when an
  /// event's own rung is already at the ladder's ceiling — the only way left
  /// for that event to feel [high] rise further (`core/haptics.dart`).
  high,
}

/// The settings shared by every profile.
///
/// Settings are device-wide rather than per-profile on purpose: sound and
/// reduced motion describe the room the tablet is in, not the child holding it.
class AppSettings {
  const AppSettings({
    this.sound = true,
    this.music = false,
    this.hapticsLevel = HapticsLevel.low,
    this.showTimer = false,
    this.theme = ThemeChoice.system,
    this.reduceMotion = false,
    this.allowPhotoImport = false,
  });

  /// Sound effects, consumed by `core/audio/app_audio.dart`
  /// (`PLAN-phase-5.md` §1).
  final bool sound;

  /// Background music. No control is drawn for it and nothing reads it: the
  /// app has no music at all (`PLAN-phase-5.md` §3.4, §4.6). Kept, unread, at
  /// its default so that a field ever wanting one needs no migration.
  final bool music;

  /// How hard vibration buzzes on mobile, consumed by `core/haptics.dart`
  /// (`PLAN-phase-5.md` §4.5). Hidden on desktop, where it does nothing.
  final HapticsLevel hapticsLevel;

  /// Whether the Sudoku timer is visible. Off by default: no time pressure.
  final bool showTimer;

  /// Day, night, or follow the device.
  final ThemeChoice theme;

  /// The stored half of the reduced-motion decision. The app or-s it with
  /// `MediaQuery.disableAnimations`, so a device-level setting is honoured
  /// without the child finding this one.
  final bool reduceMotion;

  /// Whether the draw screen's import control reads the photo library
  /// (`PLAN.md` §5.2, `PLAN-phase-8.md` §1). Off by default and device-wide
  /// rather than per profile: it is a parental control, not a child's
  /// preference — the child who would turn it on is the one it exists to
  /// gate. Gates only the *import* direction; exporting a drawing to the
  /// photo library is always available.
  final bool allowPhotoImport;

  AppSettings copyWith({
    bool? sound,
    bool? music,
    HapticsLevel? hapticsLevel,
    bool? showTimer,
    ThemeChoice? theme,
    bool? reduceMotion,
    bool? allowPhotoImport,
  }) => AppSettings(
    sound: sound ?? this.sound,
    music: music ?? this.music,
    hapticsLevel: hapticsLevel ?? this.hapticsLevel,
    showTimer: showTimer ?? this.showTimer,
    theme: theme ?? this.theme,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    allowPhotoImport: allowPhotoImport ?? this.allowPhotoImport,
  );

  @override
  bool operator ==(Object other) =>
      other is AppSettings &&
      other.sound == sound &&
      other.music == music &&
      other.hapticsLevel == hapticsLevel &&
      other.showTimer == showTimer &&
      other.theme == theme &&
      other.reduceMotion == reduceMotion &&
      other.allowPhotoImport == allowPhotoImport;

  @override
  int get hashCode => Object.hash(
    sound,
    music,
    hapticsLevel,
    showTimer,
    theme,
    reduceMotion,
    allowPhotoImport,
  );
}

/// A puzzle this profile has finished.
///
/// Keyed by puzzle id in [SudokuProgress.solved], so the grid itself is not
/// stored — the id plus the generator reproduces it (`PLAN.md` §5.2).
class SolvedPuzzle {
  const SolvedPuzzle({
    required this.timeMs,
    this.hints = 0,
    this.mistakes = 0,
    this.solvedAt,
    this.clean = false,
  });

  /// How long the puzzle took, in milliseconds.
  final int timeMs;

  /// How many cells the technique solver gave away.
  final int hints;

  /// How many wrong digits were entered.
  final int mistakes;

  /// When it was finished, in UTC. Optional because `PLAN.md` §5.2's own
  /// example omits it on one entry: a solved puzzle is still solved without a
  /// timestamp, and nothing gates on it.
  final DateTime? solvedAt;

  /// Solved with no hints and no mistakes — what earns the star.
  final bool clean;

  @override
  bool operator ==(Object other) =>
      other is SolvedPuzzle &&
      other.timeMs == timeMs &&
      other.hints == hints &&
      other.mistakes == mistakes &&
      other.solvedAt == solvedAt &&
      other.clean == clean;

  @override
  int get hashCode => Object.hash(timeMs, hints, mistakes, solvedAt, clean);
}

/// A puzzle left half-finished, restored exactly on the next launch.
///
/// Phase 3 owns the encoding of [grid], [notes] and [undoStack]; to the codec
/// they are opaque strings. Keeping them opaque is deliberate — the board
/// representation changes with the Sudoku UI, and a save format that knew about
/// it would change with it.
class PuzzleInProgress {
  const PuzzleInProgress({
    required this.grid,
    this.notes = '',
    this.elapsedMs = 0,
    this.undoStack = const [],
    this.hints = 0,
  });

  /// The digits entered so far.
  final String grid;

  /// The pencil marks entered so far.
  final String notes;

  /// Time on the clock when the app was last closed.
  final int elapsedMs;

  /// Moves in order, oldest first, so undo survives a restart.
  final List<String> undoStack;

  /// Hints used so far, carried into the [SolvedPuzzle] on completion.
  final int hints;

  @override
  bool operator ==(Object other) =>
      other is PuzzleInProgress &&
      other.grid == grid &&
      other.notes == notes &&
      other.elapsedMs == elapsedMs &&
      _listEquals(other.undoStack, undoStack) &&
      other.hints == hints;

  @override
  int get hashCode =>
      Object.hash(grid, notes, elapsedMs, Object.hashAll(undoStack), hints);
}

/// The daily-puzzle streak.
///
/// [lastDayIndex] is a day index rather than a date so the streak arithmetic is
/// subtraction, and so it agrees with the UTC day index the daily puzzle is
/// generated from (`PLAN.md` §3.2). Crossing a timezone therefore cannot break
/// a streak.
class DailyStreak {
  const DailyStreak({this.current = 0, this.best = 0, this.lastDayIndex});

  /// Days in a row up to and including [lastDayIndex].
  final int current;

  /// The longest run ever reached.
  final int best;

  /// The last day a daily puzzle was solved. Null until the first one is.
  final int? lastDayIndex;

  @override
  bool operator ==(Object other) =>
      other is DailyStreak &&
      other.current == current &&
      other.best == best &&
      other.lastDayIndex == lastDayIndex;

  @override
  int get hashCode => Object.hash(current, best, lastDayIndex);
}

/// One profile's Sudoku history. Empty for a new profile; written from phase 3.
class SudokuProgress {
  const SudokuProgress({
    this.solved = const {},
    this.inProgress = const {},
    this.dailyStreak = const DailyStreak(),
    this.bestTimeMs = const {},
  });

  /// Puzzle id to how it was finished.
  final Map<String, SolvedPuzzle> solved;

  /// Puzzle id to the board as it was left.
  final Map<String, PuzzleInProgress> inProgress;

  /// The daily-puzzle streak.
  final DailyStreak dailyStreak;

  /// `"9x9:easy"` to the best time in milliseconds. Derived from [solved], but
  /// stored, so the menu can show a best time without walking every entry.
  final Map<String, int> bestTimeMs;

  /// The key [bestTimeMs] holds one size and difficulty under
  /// (`PLAN.md` §5.2).
  ///
  /// Beside the field rather than in the repository that writes it, because the
  /// menu reads it too (`PLAN-phase-3.md` §4.7): two spellings of `"9x9:easy"`
  /// would agree right up until one of them was edited, and the failure then is
  /// a best time that silently stops being found.
  static String bestTimeKey(
    engine.SudokuSpec spec,
    engine.Difficulty difficulty,
  ) => '${spec.label}:${difficulty.name}';

  SudokuProgress copyWith({
    Map<String, SolvedPuzzle>? solved,
    Map<String, PuzzleInProgress>? inProgress,
    DailyStreak? dailyStreak,
    Map<String, int>? bestTimeMs,
  }) => SudokuProgress(
    solved: solved ?? this.solved,
    inProgress: inProgress ?? this.inProgress,
    dailyStreak: dailyStreak ?? this.dailyStreak,
    bestTimeMs: bestTimeMs ?? this.bestTimeMs,
  );

  @override
  bool operator ==(Object other) =>
      other is SudokuProgress &&
      _mapEquals(other.solved, solved) &&
      _mapEquals(other.inProgress, inProgress) &&
      other.dailyStreak == dailyStreak &&
      _mapEquals(other.bestTimeMs, bestTimeMs);

  @override
  int get hashCode => Object.hash(
    _mapHash(solved),
    _mapHash(inProgress),
    dailyStreak,
    _mapHash(bestTimeMs),
  );
}

/// One entry in a game's high-score table.
///
/// `PLAN.md` §4.3 lists the profile as part of an entry; it is the profile that
/// contains it, so storing it again would be a second copy that can disagree
/// with the first.
class HighScore {
  const HighScore({
    required this.score,
    this.wave = 0,
    this.at,
    this.easy = false,
  });

  /// Points.
  final int score;

  /// The wave, level or round reached. Zero where a game has no such thing —
  /// Memory Match and Whack-a-Mole in `PLAN.md` §4.4 do not.
  final int wave;

  /// When it was set, in UTC. Optional for the same reason as
  /// [SolvedPuzzle.solvedAt]: a score with no date is still a score.
  final DateTime? at;

  /// Whether the run that set it was played in easy mode.
  ///
  /// A flag rather than a second game id (`"invaders:easy"`), so the two
  /// lifetime counters on [ArcadeGameProgress] stay single numbers instead of
  /// two that would need adding at every read (`PLAN-phase-4.md` §3). The
  /// top-five cap in `ProgressRepository` applies within one value of this
  /// flag, so a normal-mode score can never evict an easy-mode one.
  final bool easy;

  @override
  bool operator ==(Object other) =>
      other is HighScore &&
      other.score == score &&
      other.wave == wave &&
      other.at == at &&
      other.easy == easy;

  @override
  int get hashCode => Object.hash(score, wave, at, easy);
}

/// One profile's history for one arcade game.
class ArcadeGameProgress {
  const ArcadeGameProgress({
    this.highScores = const [],
    this.gamesPlayed = 0,
    this.totalKills = 0,
  });

  /// Best first, capped at five by the repository (`PLAN.md` §4.3). The cap is
  /// a write-time rule rather than a decode-time one: truncating on load would
  /// throw away scores that a later, larger cap could have shown.
  final List<HighScore> highScores;

  /// Lifetime games started.
  final int gamesPlayed;

  /// Lifetime aliens destroyed.
  final int totalKills;

  @override
  bool operator ==(Object other) =>
      other is ArcadeGameProgress &&
      _listEquals(other.highScores, highScores) &&
      other.gamesPlayed == gamesPlayed &&
      other.totalKills == totalKills;

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(highScores), gamesPlayed, totalKills);
}

/// One profile's arcade history, keyed by game id — `"invaders"` in phase 4.
///
/// A class wrapping a single map rather than a bare map, so that the two halves
/// of [Profile] read the same way and equality lives beside the data. The
/// encoded form is the bare map (`PLAN.md` §5.2), so a field added here later
/// would collide with a game called after it — a cross-game counter belongs
/// outside this object, not in it.
class ArcadeProgress {
  const ArcadeProgress({this.games = const {}});

  /// Game id to that game's scores and counters.
  final Map<String, ArcadeGameProgress> games;

  @override
  bool operator ==(Object other) =>
      other is ArcadeProgress && _mapEquals(other.games, games);

  @override
  int get hashCode => _mapHash(games);
}

/// One profile's drawing history (`PLAN.md` §5.2, `PLAN-phase-8.md` §4.5).
///
/// Holds three numbers, not the drawings: a picture is tens of kilobytes,
/// which is the whole of what `save.json`'s few-kilobyte target would cost if
/// drawings lived in it. A drawing itself is a file under
/// `drawings/<profileId>/`, read and written by
/// `features/draw/data/drawing_repository.dart`.
class DrawProgress {
  const DrawProgress({
    this.drawingCount = 0,
    this.lastDrawingId,
    this.bytesUsed = 0,
  });

  /// How many drawings this profile has made, ever — including ones since
  /// deleted, so it never repeats an id `"d1"`, `"d2"`, … the way a profile
  /// id counter never repeats (`PLAN-phase-1.md` §1).
  final int drawingCount;

  /// The id the Draw card reopens, or null before the first drawing.
  final String? lastDrawingId;

  /// What the 64 MB per-profile budget is checked against when a drawing is
  /// written. Kept here rather than measured from the directory, so the
  /// check costs no disk read on a cheap tablet (`PLAN.md` §5.2).
  final int bytesUsed;

  DrawProgress copyWith({
    int? drawingCount,
    String? lastDrawingId,
    int? bytesUsed,
  }) => DrawProgress(
    drawingCount: drawingCount ?? this.drawingCount,
    lastDrawingId: lastDrawingId ?? this.lastDrawingId,
    bytesUsed: bytesUsed ?? this.bytesUsed,
  );

  @override
  bool operator ==(Object other) =>
      other is DrawProgress &&
      other.drawingCount == drawingCount &&
      other.lastDrawingId == lastDrawingId &&
      other.bytesUsed == bytesUsed;

  @override
  int get hashCode => Object.hash(drawingCount, lastDrawingId, bytesUsed);
}

/// One child.
///
/// No password and no account: several children share one tablet, and nothing
/// stored here is worth locking (`PLAN.md` §5.1).
class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.avatar,
    required this.createdAt,
    this.sudoku = const SudokuProgress(),
    this.arcade = const ArcadeProgress(),
    this.draw = const DrawProgress(),
    this.mistakeFeedback = MistakeFeedback.immediate,
    this.arcadeEasyMode = false,
    this.arcadeAutoFire = false,
    this.padSide = PadSide.right,
  }) : assert(createdAt.isUtc, 'createdAt must be UTC');

  /// `"p1"`, `"p2"`, … — a counter, never random and never a clock reading, so
  /// that no ambient randomness exists anywhere in `lib/` (PLAN-phase-1.md §1).
  final String id;

  /// What the child typed, or a `Player n` fallback.
  final String name;

  /// The picture they picked.
  final AvatarId avatar;

  /// When the profile was made, in UTC.
  final DateTime createdAt;

  /// Sudoku history.
  final SudokuProgress sudoku;

  /// Arcade history.
  final ArcadeProgress arcade;

  /// Drawing history (`PLAN-phase-8.md` §4.5).
  final DrawProgress draw;

  /// When a wrong Sudoku digit is flagged. Per profile — see [MistakeFeedback].
  final MistakeFeedback mistakeFeedback;

  /// Fewer rows, more lives, slower aliens (`PLAN.md` §4.1). A child's choice,
  /// not the tablet's — see [PadSide].
  final bool arcadeEasyMode;

  /// The ship fires on its own, so a small player only has to steer
  /// (`PLAN.md` §4.1).
  final bool arcadeAutoFire;

  /// Which side LEFT and RIGHT sit on.
  final PadSide padSide;

  Profile copyWith({
    String? name,
    AvatarId? avatar,
    SudokuProgress? sudoku,
    ArcadeProgress? arcade,
    DrawProgress? draw,
    MistakeFeedback? mistakeFeedback,
    bool? arcadeEasyMode,
    bool? arcadeAutoFire,
    PadSide? padSide,
  }) => Profile(
    id: id,
    name: name ?? this.name,
    avatar: avatar ?? this.avatar,
    createdAt: createdAt,
    sudoku: sudoku ?? this.sudoku,
    arcade: arcade ?? this.arcade,
    draw: draw ?? this.draw,
    mistakeFeedback: mistakeFeedback ?? this.mistakeFeedback,
    arcadeEasyMode: arcadeEasyMode ?? this.arcadeEasyMode,
    arcadeAutoFire: arcadeAutoFire ?? this.arcadeAutoFire,
    padSide: padSide ?? this.padSide,
  );

  @override
  bool operator ==(Object other) =>
      other is Profile &&
      other.id == id &&
      other.name == name &&
      other.avatar == avatar &&
      other.createdAt == createdAt &&
      other.sudoku == sudoku &&
      other.arcade == arcade &&
      other.draw == draw &&
      other.mistakeFeedback == mistakeFeedback &&
      other.arcadeEasyMode == arcadeEasyMode &&
      other.arcadeAutoFire == arcadeAutoFire &&
      other.padSide == padSide;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    avatar,
    createdAt,
    sudoku,
    arcade,
    draw,
    mistakeFeedback,
    arcadeEasyMode,
    arcadeAutoFire,
    padSide,
  );
}

/// The whole save file.
///
/// Two invariants hold for every instance, and the codec enforces both at the
/// boundary rather than leaving them to callers: [profiles] is never empty, and
/// [activeProfileId] names one of them. A child with no profile has no way back
/// to a working app.
class SaveData {
  SaveData({
    required this.activeProfileId,
    required this.profiles,
    this.settings = const AppSettings(),
    this.generatorVersion = engine.generatorVersion,
    this.puzzleCache = const {},
  }) : assert(profiles.isNotEmpty, 'a save always has at least one profile'),
       assert(
         profiles.any((profile) => profile.id == activeProfileId),
         'activeProfileId must name one of profiles',
       );

  /// The save a first launch starts from: one profile, default settings.
  ///
  /// [createdAt] is passed in rather than read from a clock here, so this layer
  /// stays free of ambient state and the store's tests stay deterministic.
  factory SaveData.initial({required DateTime createdAt}) => SaveData(
    activeProfileId: firstProfileId,
    profiles: [
      Profile(
        id: firstProfileId,
        name: 'Player 1',
        avatar: AvatarId.fox,
        createdAt: createdAt.toUtc(),
      ),
    ],
  );

  /// Always [currentSchemaVersion] in memory, and not settable: a file written
  /// by an older version is migrated on load, so nothing downstream branches on
  /// it and nothing can build a save that would be written as another version.
  final int schemaVersion = currentSchemaVersion;

  /// The generator that produced the puzzle ids in this file. Recorded at write
  /// time so a future generator bump can tell which ids it can still resolve
  /// (`PLAN.md` §3.1).
  final int generatorVersion;

  /// Which profile the app opens into. Always the id of a member of [profiles].
  final String activeProfileId;

  /// Device-wide settings.
  final AppSettings settings;

  /// Never empty.
  final List<Profile> profiles;

  /// Puzzle id to clue string, for instant revisits. Populated from phase 3;
  /// nothing writes it in phase 1.
  final Map<String, String> puzzleCache;

  /// The profile the app is showing.
  Profile get activeProfile =>
      profiles.firstWhere((profile) => profile.id == activeProfileId);

  SaveData copyWith({
    String? activeProfileId,
    AppSettings? settings,
    List<Profile>? profiles,
    int? generatorVersion,
    Map<String, String>? puzzleCache,
  }) => SaveData(
    activeProfileId: activeProfileId ?? this.activeProfileId,
    settings: settings ?? this.settings,
    profiles: profiles ?? this.profiles,
    generatorVersion: generatorVersion ?? this.generatorVersion,
    puzzleCache: puzzleCache ?? this.puzzleCache,
  );

  @override
  bool operator ==(Object other) =>
      // [schemaVersion] is a constant, so it is not compared.
      other is SaveData &&
      other.generatorVersion == generatorVersion &&
      other.activeProfileId == activeProfileId &&
      other.settings == settings &&
      _listEquals(other.profiles, profiles) &&
      _mapEquals(other.puzzleCache, puzzleCache);

  @override
  int get hashCode => Object.hash(
    generatorVersion,
    activeProfileId,
    settings,
    Object.hashAll(profiles),
    _mapHash(puzzleCache),
  );
}

// --- value equality helpers -------------------------------------------------
//
// Flutter's `listEquals` and `mapEquals` would do, but they live in
// `package:flutter/foundation.dart` and this file stays Flutter-free.

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

bool _mapEquals<V>(Map<String, V> a, Map<String, V> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (final entry in a.entries) {
    if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return false;
  }
  return true;
}

/// Order-independent, because [_mapEquals] is: two maps holding the same
/// entries in a different insertion order are equal, so they must hash alike.
int _mapHash<V>(Map<String, V> map) {
  var hash = 0;
  for (final entry in map.entries) {
    hash ^= Object.hash(entry.key, entry.value);
  }
  return hash;
}
