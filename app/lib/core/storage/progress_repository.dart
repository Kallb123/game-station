// The one way anything above `core/storage` reads or changes saved state.
//
// It owns the write rules from `PLAN.md` §5.3 and PLAN-phase-1.md §4.3:
//
// - The save is read once, before `runApp`. Every later read is from memory, so
//   nothing in a game loop ever touches a disk.
// - A mutation updates memory immediately and schedules a write, debounced by
//   [debounce]. Ten taps in a second cost one write, not ten.
// - **One write at a time, latest wins.** While a write is in flight a new one
//   waits rather than starting beside it. Two `rename` calls racing over the
//   same path is the one way the atomic-write design still corrupts a save, and
//   a queue of one removes it.
// - [flush] awaits everything outstanding. It is what an `AppLifecycleListener`
//   calls on `paused`/`detached`, and what a test awaits instead of pumping
//   timers.
//
// It is a [ChangeNotifier] rather than a Riverpod type: the wiring arrives in
// the next pull request, and a repository that already depends on the state
// library cannot be tested without it.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:puzzle_engine/puzzle_engine.dart' as engine;

import 'save_data.dart';
import 'save_store.dart';

/// How long a name may be, in characters.
///
/// Short on purpose: the name is drawn on a profile button next to an avatar,
/// and a child picks the profile by the picture anyway.
const int maxProfileNameLength = 12;

/// How many puzzles [ProgressRepository.cachePuzzle] keeps at once
/// (`PLAN.md` §5.2, `PLAN-phase-3.md` §4.1).
const int puzzleCacheCap = 30;

/// Holds the save in memory and writes it back on a debounce.
class ProgressRepository extends ChangeNotifier {
  ProgressRepository(
    this._store, {
    required SaveData initial,
    this.debounce = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) : _data = initial,
       _now = now ?? DateTime.now,
       _cacheRecency = LinkedHashSet.of(initial.puzzleCache.keys);

  /// Builds a repository from what [SaveStore.load] returned.
  ///
  /// The recovery itself is not held here: it describes one launch, not the
  /// saved state, and the screen that shows it takes it from the [SaveLoad].
  factory ProgressRepository.fromLoad(
    SaveStore store,
    SaveLoad load, {
    Duration debounce = const Duration(milliseconds: 500),
    DateTime Function()? now,
  }) => ProgressRepository(
    store,
    initial: _withCurrentGenerator(load.data),
    debounce: debounce,
    now: now,
  );

  /// Drops [data]'s puzzle cache wholesale when it was written by a different
  /// generator (`PLAN-phase-3.md` §4.1).
  ///
  /// A per-entry key would let a stale entry outlive the generator that made
  /// it, and there is nothing in a cache worth a migration — the puzzle
  /// source regenerates on the next miss.
  static SaveData _withCurrentGenerator(SaveData data) =>
      data.generatorVersion == engine.generatorVersion
      ? data
      : data.copyWith(
          generatorVersion: engine.generatorVersion,
          puzzleCache: const {},
        );

  final SaveStore _store;
  final DateTime Function() _now;

  /// [_data.puzzleCache]'s keys, oldest access first. Seeded on load in
  /// whatever order the file gives, because the codec sorts keys on write and
  /// recency is not recoverable from disk (`PLAN-phase-3.md` §4.8) — the cost
  /// of that is the occasional wrong eviction, not a wrong one every time.
  final LinkedHashSet<String> _cacheRecency;

  /// How long after a mutation the write starts. A mutation inside the window
  /// restarts it.
  final Duration debounce;

  SaveData _data;
  Timer? _timer;
  Future<void>? _inFlight;
  bool _pending = false;
  bool _disposed = false;
  Object? _lastWriteError;

  /// The save as it stands. Always current; never re-read from the store.
  SaveData get data => _data;

  /// Device-wide settings.
  AppSettings get settings => _data.settings;

  /// Every profile on this device, in creation order.
  List<Profile> get profiles => List.unmodifiable(_data.profiles);

  /// The profile the app is showing.
  Profile get activeProfile => _data.activeProfile;

  /// Whether a write is scheduled or running.
  bool get isSaving => _pending || _inFlight != null;

  /// Whether this repository has been disposed with its scope.
  ///
  /// Asked by a caller that arranged to write *after* the frame that took it
  /// down — the play screen's last save (`sudoku_play_screen.dart`) — because
  /// by then the scope may have gone too, and mutating a disposed
  /// [ChangeNotifier] throws.
  bool get isDisposed => _disposed;

  /// What the last write failed with, or null if the last one succeeded.
  ///
  /// A failed write is recorded rather than thrown: the caller is a tap
  /// handler, and an unhandled exception from one would be a crash in front of
  /// a child (PLAN-phase-1.md §7). A later phase surfaces this as "couldn't
  /// save"; nothing draws it yet.
  Object? get lastWriteError => _lastWriteError;

  // --- settings --------------------------------------------------------------

  /// Replaces the settings block.
  ///
  /// Takes the whole block rather than one setter per field: a screen already
  /// holds the current settings, `copyWith` says which field changed, and six
  /// near-identical methods would say nothing extra.
  void updateSettings(AppSettings settings) =>
      _apply(_data.copyWith(settings: settings));

  // --- profiles --------------------------------------------------------------

  /// Adds a profile and makes it active, returning it.
  ///
  /// [name] is trimmed and capped at [maxProfileNameLength]; an empty one falls
  /// back to `Player n`, so a child who taps *Create* without typing gets a
  /// profile rather than a validation error.
  Profile createProfile({String name = '', required AvatarId avatar}) {
    final number = _nextProfileNumber();
    final profile = Profile(
      id: 'p$number',
      name: _cleanName(name, number),
      avatar: avatar,
      createdAt: _now().toUtc(),
    );
    _apply(
      _data.copyWith(
        profiles: [..._data.profiles, profile],
        activeProfileId: profile.id,
      ),
    );
    return profile;
  }

  /// Renames the profile with [id]. Same trimming and fallback as
  /// [createProfile].
  void renameProfile(String id, String name) => _replaceProfile(
    id,
    (profile) => profile.copyWith(name: _cleanName(name, _displayNumber(id))),
  );

  /// Changes the avatar of the profile with [id].
  void setProfileAvatar(String id, AvatarId avatar) =>
      _replaceProfile(id, (profile) => profile.copyWith(avatar: avatar));

  /// Changes when the profile with [id] is told about a wrong digit.
  void setMistakeFeedback(String id, MistakeFeedback value) => _replaceProfile(
    id,
    (profile) => profile.copyWith(mistakeFeedback: value),
  );

  /// Makes the profile with [id] the active one.
  void selectProfile(String id) {
    _requireProfile(id);
    _apply(_data.copyWith(activeProfileId: id));
  }

  /// Removes the profile with [id], selecting another if it was active.
  ///
  /// Refused when it is the last one. The rule lives here rather than only in
  /// the screen that hides the button, because a save with no profiles has no
  /// way back to a working app and every caller would otherwise have to
  /// remember that.
  void deleteProfile(String id) {
    _requireProfile(id);
    if (_data.profiles.length == 1) {
      throw StateError('the last profile cannot be deleted');
    }

    final remaining = [
      for (final profile in _data.profiles)
        if (profile.id != id) profile,
    ];
    _apply(
      _data.copyWith(
        profiles: remaining,
        activeProfileId: _data.activeProfileId == id
            ? remaining.first.id
            : _data.activeProfileId,
      ),
    );
  }

  // --- sudoku ------------------------------------------------------------

  /// Stores [state] as the active profile's in-progress board for [id],
  /// replacing whatever was there.
  void saveInProgress(engine.PuzzleId id, PuzzleInProgress state) =>
      _updateActiveSudoku(
        (sudoku) => sudoku.copyWith(
          inProgress: {...sudoku.inProgress, id.value: state},
        ),
      );

  /// Removes the active profile's in-progress entry for [id], if it has one.
  void clearInProgress(engine.PuzzleId id) => _updateActiveSudoku(
    (sudoku) => sudoku.copyWith(
      inProgress: {
        for (final entry in sudoku.inProgress.entries)
          if (entry.key != id.value) entry.key: entry.value,
      },
    ),
  );

  /// Records [result] as how the active profile finished [id]: adds it to
  /// `solved`, clears the matching `inProgress` entry in the same mutation so
  /// a save cannot hold a puzzle that is both finished and in progress, and
  /// updates `bestTimeMs` and the daily streak (`PLAN-phase-3.md` §4.7, §4.8).
  ///
  /// A [result] with no [SolvedPuzzle.solvedAt] is stamped from this
  /// repository's own clock — the one the streak is counted against, so a solve
  /// cannot be dated by one clock and counted by another. It is also the clock
  /// a test can move, which a `DateTime.now` in the screen that finished the
  /// puzzle would not be.
  void recordSolved(engine.PuzzleId id, SolvedPuzzle result) =>
      _updateActiveSudoku((sudoku) {
        final key = _bestTimeKey(id);
        final best = sudoku.bestTimeMs[key];

        return sudoku.copyWith(
          solved: {...sudoku.solved, id.value: _stamped(result)},
          inProgress: {
            for (final entry in sudoku.inProgress.entries)
              if (entry.key != id.value) entry.key: entry.value,
          },
          dailyStreak: _nextStreak(sudoku.dailyStreak, id),
          bestTimeMs: {
            ...sudoku.bestTimeMs,
            if (best == null || result.timeMs < best) key: result.timeMs,
          },
        );
      });

  /// Caches [record] — the puzzle source's encoded form — against [id],
  /// evicting the least-recently-used entry once the cache would hold more
  /// than [puzzleCacheCap]. An id with an `inProgress` entry, in any profile,
  /// is never evicted: dropping the puzzle a child is halfway through would
  /// make resume regenerate it behind a spinner (`PLAN-phase-3.md` §4.8).
  ///
  /// Device-wide rather than per profile, matching [SaveData.puzzleCache]: two
  /// profiles playing the same puzzle id share one generation.
  void cachePuzzle(engine.PuzzleId id, String record) {
    final key = id.value;
    _cacheRecency
      ..remove(key)
      ..add(key);

    var cache = {..._data.puzzleCache, key: record};
    while (cache.length > puzzleCacheCap) {
      final victim = _cacheRecency.firstWhere(
        (candidate) => candidate != key && !_isPinned(candidate),
        orElse: () => key,
      );
      if (victim == key) break; // Nothing left that is safe to drop.

      cache = {
        for (final entry in cache.entries)
          if (entry.key != victim) entry.key: entry.value,
      };
      _cacheRecency.remove(victim);
    }

    _apply(_data.copyWith(puzzleCache: cache));
  }

  /// [result] with a time on it, dated now when it arrived without one.
  SolvedPuzzle _stamped(SolvedPuzzle result) => result.solvedAt != null
      ? result
      : SolvedPuzzle(
          timeMs: result.timeMs,
          hints: result.hints,
          mistakes: result.mistakes,
          solvedAt: _now().toUtc(),
          clean: result.clean,
        );

  /// Whether some profile has an `inProgress` entry for [puzzleId].
  bool _isPinned(String puzzleId) => _data.profiles.any(
    (profile) => profile.sudoku.inProgress.containsKey(puzzleId),
  );

  /// `"9x9:easy"`, the key [SudokuProgress.bestTimeMs] uses (`PLAN.md` §5.2).
  String _bestTimeKey(engine.PuzzleId id) =>
      '${id.spec.label}:${id.difficulty.name}';

  /// The streak after solving [id], or [streak] unchanged when [id] is not
  /// today's daily puzzle — any size and difficulty counts, so a solve is only
  /// ever compared against today's day index (`PLAN-phase-3.md` §4.7).
  DailyStreak _nextStreak(DailyStreak streak, engine.PuzzleId id) {
    final today = engine.dayIndexFor(_now());
    if (id.index != today || streak.lastDayIndex == today) return streak;

    final current = streak.lastDayIndex == today - 1 ? streak.current + 1 : 1;
    return DailyStreak(
      current: current,
      best: current > streak.best ? current : streak.best,
      lastDayIndex: today,
    );
  }

  void _updateActiveSudoku(SudokuProgress Function(SudokuProgress) update) =>
      _replaceProfile(
        _data.activeProfileId,
        (profile) => profile.copyWith(sudoku: update(profile.sudoku)),
      );

  // --- writing ---------------------------------------------------------------

  /// Writes everything outstanding and waits for it to land.
  ///
  /// Never throws: a write that fails leaves [lastWriteError] set, because the
  /// callers are a lifecycle handler and a desktop exit request, and neither
  /// has anywhere to put an exception.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;

    while (_pending || _inFlight != null) {
      final inFlight = _inFlight;
      if (inFlight != null) {
        await inFlight;
      } else {
        _startWrite();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _disposed = true;
    // A scheduled write is started rather than dropped. Nothing awaits it — a
    // caller that needs the write to have landed awaits [flush] first — but
    // silently losing the last change a child made is worse than a write that
    // finishes after the object is gone.
    if (_pending && _inFlight == null) _startWrite();
    super.dispose();
  }

  /// Updates memory and schedules a write, if [next] is a real change.
  ///
  /// The equality check is why value equality is on the models: a settings
  /// screen that writes the value already stored, or a rename to the same name,
  /// costs nothing.
  void _apply(SaveData next) {
    if (next == _data) return;
    _data = next;
    notifyListeners();

    _pending = true;
    _timer?.cancel();
    _timer = Timer(debounce, _onTimer);
  }

  void _onTimer() {
    _timer = null;
    // A write already running keeps the slot; its own completion starts this
    // one, so the newest state is what reaches disk.
    if (_pending && _inFlight == null) _startWrite();
  }

  void _startWrite() {
    _pending = false;
    _inFlight = _writeThenSettle(_data);
  }

  Future<void> _writeThenSettle(SaveData snapshot) async {
    try {
      await _store.write(snapshot);
      _setWriteError(null);
    } on Object catch (error) {
      _setWriteError(error);
    }

    _inFlight = null;
    // Only when no timer is waiting: if one is, it owns the next write, and
    // starting one here would undo the debounce.
    if (_pending && _timer == null) _startWrite();
  }

  void _setWriteError(Object? error) {
    if (_lastWriteError == error) return;
    _lastWriteError = error;
    // A write can outlive the repository (see [dispose]), and notifying a
    // disposed ChangeNotifier throws.
    if (!_disposed) notifyListeners();
  }

  // --- helpers ---------------------------------------------------------------

  void _replaceProfile(String id, Profile Function(Profile) update) {
    _requireProfile(id);
    _apply(
      _data.copyWith(
        profiles: [
          for (final profile in _data.profiles)
            if (profile.id == id) update(profile) else profile,
        ],
      ),
    );
  }

  void _requireProfile(String id) {
    if (!_data.profiles.any((profile) => profile.id == id)) {
      throw ArgumentError.value(id, 'id', 'no such profile');
    }
  }

  /// One more than the highest `p<n>` in use.
  ///
  /// A counter, so that no identifier comes from `Random` or a clock
  /// (PLAN-phase-1.md §1). Highest in use rather than a count, so deleting p2
  /// of p1..p3 and creating a profile gives p4 and not a second p3.
  int _nextProfileNumber() {
    var highest = 0;
    for (final profile in _data.profiles) {
      final number = _numberOf(profile);
      if (number > highest) highest = number;
    }
    return highest + 1;
  }

  /// The `n` in a `p<n>` id, or 0 for an id of any other shape.
  int _numberOf(Profile profile) {
    final match = RegExp(r'^p(\d+)$').firstMatch(profile.id);
    return match == null ? 0 : int.parse(match.group(1)!);
  }

  /// The number to put in a `Player n` fallback name.
  ///
  /// Falls back to the profile's position for an id this app did not write —
  /// only a hand-edited file has one — because `Player 0` would look like a
  /// bug to the child who was just renamed to it.
  int _displayNumber(String id) {
    final index = _data.profiles.indexWhere((profile) => profile.id == id);
    final number = _numberOf(_data.profiles[index]);
    return number > 0 ? number : index + 1;
  }

  /// Trims, caps, and falls back to `Player n` when nothing is left.
  ///
  /// Capped by runes rather than by code units, so a cap cannot cut an emoji in
  /// half and leave an unpaired surrogate in the file.
  String _cleanName(String name, int number) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'Player $number';
    final runes = trimmed.runes.toList();
    if (runes.length <= maxProfileNameLength) return trimmed;
    return String.fromCharCodes(runes.take(maxProfileNameLength)).trimRight();
  }
}
