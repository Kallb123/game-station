// Fixtures shared by the storage tests.
//
// [fullSave] populates every field of schema v1, including the ones no code
// writes until phases 3 and 4. That is the point: the round-trip test is only
// evidence that v1 is final if it covers the parts of v1 that are not yet
// exercised by anything else.

import 'package:game_station/core/storage/save_data.dart';

/// A save with every field of schema v1 set to a distinguishable value.
SaveData fullSave() => SaveData(
  generatorVersion: 1,
  activeProfileId: 'p2',
  settings: const AppSettings(
    sound: false,
    music: true,
    haptics: false,
    showTimer: true,
    theme: ThemeChoice.night,
    reduceMotion: true,
  ),
  profiles: [
    Profile(
      id: 'p1',
      name: 'Ana',
      avatar: AvatarId.fox,
      createdAt: DateTime.utc(2026, 8, 11, 10),
      mistakeFeedback: MistakeFeedback.atCompletion,
      sudoku: SudokuProgress(
        solved: {
          'sudoku:9x9:easy:0': SolvedPuzzle(
            timeMs: 244000,
            mistakes: 2,
            solvedAt: DateTime.utc(2026, 8, 11, 10, 30),
            clean: true,
          ),
          'sudoku:6x6:easy:3': const SolvedPuzzle(timeMs: 61000, hints: 1),
        },
        inProgress: const {
          'sudoku:9x9:hard:12': PuzzleInProgress(
            grid: '53..7....6..195...',
            notes: '1,2|3|',
            elapsedMs: 90000,
            undoStack: ['r0c0=5', 'r0c1=3'],
            hints: 1,
          ),
        },
        dailyStreak: const DailyStreak(current: 4, best: 11, lastDayIndex: 223),
        bestTimeMs: const {'9x9:easy': 180000, '9x9:medium': 402000},
      ),
      arcade: ArcadeProgress(
        games: {
          'invaders': ArcadeGameProgress(
            highScores: [
              HighScore(score: 15400, wave: 7, at: DateTime.utc(2026, 8, 10)),
              const HighScore(score: 9000, wave: 4),
            ],
            gamesPlayed: 22,
            totalKills: 3110,
          ),
        },
      ),
    ),
    Profile(
      id: 'p2',
      name: 'Bo',
      avatar: AvatarId.owl,
      createdAt: DateTime.utc(2026, 8, 12, 9, 15),
    ),
  ],
  puzzleCache: const {'sudoku:9x9:hard:12': '53..7....6..195...'},
);

/// `PLAN.md` §5.2's example document, with its `"…"` placeholders filled in and
/// nothing else changed. The plan elides four values — two timestamps, the
/// in-progress board, and the two halves of the cached record — and each is
/// filled with something of the right shape.
///
/// Short of the 81 characters a real 9x9 record holds on each side of the `|`,
/// as the plan's own example is: the codec stores the value as an opaque string
/// and never parses it (`PLAN-phase-3.md` §4.1), so a full-length one would be
/// seventy more characters proving the same thing.
const String planExampleJson = '''
{
  "schemaVersion": 1,
  "generatorVersion": 1,
  "activeProfileId": "p1",
  "settings": {
    "sound": true, "music": false, "haptics": true,
    "showTimer": false, "theme": "day", "reduceMotion": false
  },
  "profiles": [{
    "id": "p1", "name": "Ana", "avatar": "fox", "createdAt": "2026-08-11T10:00:00Z",
    "mistakeFeedback": "atCompletion",
    "sudoku": {
      "solved": {
        "sudoku:9x9:easy:0": { "timeMs": 244000, "hints": 0, "mistakes": 2,
                               "solvedAt": "2026-08-11T10:30:00Z", "clean": true },
        "sudoku:6x6:easy:3": { "timeMs": 61000, "hints": 1, "mistakes": 0, "clean": false }
      },
      "inProgress": {
        "sudoku:9x9:hard:12": { "grid": "53..7....", "notes": "1,2|3|",
                                "elapsedMs": 90000, "undoStack": [], "hints": 1 }
      },
      "dailyStreak": { "current": 4, "best": 11, "lastDayIndex": 223 },
      "bestTimeMs": { "9x9:easy": 180000, "9x9:medium": 402000 }
    },
    "arcade": {
      "invaders": { "highScores": [{ "score": 15400, "wave": 7, "at": "2026-08-10T00:00:00Z" }],
                    "gamesPlayed": 22, "totalKills": 3110 }
    }
  }],
  "puzzleCache": { "sudoku:9x9:hard:12": "53..7....|534678912" }
}
''';

/// The smallest document [decodeSave] accepts: the version, one profile, and
/// the pointer to it. Everything else has to fall back to a default.
const String minimalSaveJson = '''
{
  "schemaVersion": 1,
  "activeProfileId": "p1",
  "profiles": [
    { "id": "p1", "name": "Player 1", "avatar": "fox",
      "createdAt": "2026-08-11T10:00:00Z" }
  ]
}
''';
