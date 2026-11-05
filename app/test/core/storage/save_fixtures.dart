// Fixtures shared by the storage tests.
//
// [fullSave] populates every field of schema v1, including the ones no code
// writes until phases 3 and 4. That is the point: the round-trip test is only
// evidence that v1 is final if it covers the parts of v1 that are not yet
// exercised by anything else.

import 'package:zibo_games/core/storage/save_data.dart';

/// A save with every field of schema v1 set to a distinguishable value.
SaveData fullSave() => SaveData(
  generatorVersion: 1,
  activeProfileId: 'p2',
  settings: const AppSettings(
    sound: false,
    music: true,
    hapticsLevel: HapticsLevel.high,
    showTimer: true,
    theme: ThemeChoice.night,
    reduceMotion: true,
    allowPhotoImport: true,
  ),
  profiles: [
    Profile(
      id: 'p1',
      name: 'Ana',
      avatar: AvatarId.fox,
      createdAt: DateTime.utc(2026, 8, 11, 10),
      mistakeFeedback: MistakeFeedback.atCompletion,
      arcadeEasyMode: true,
      arcadeAutoFire: true,
      padSide: PadSide.left,
      snakeCounting: SnakeCounting.twos,
      tracksTheme: TracksTheme.santa,
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
        bestSolve: {
          '9x9:easy': SolvedPuzzle(
            timeMs: 180000,
            hints: 2,
            mistakes: 1,
            solvedAt: DateTime.utc(2026, 8, 10, 8, 15),
          ),
        },
      ),
      arcade: ArcadeProgress(
        games: {
          'invaders': ArcadeGameProgress(
            highScores: [
              HighScore(score: 15400, wave: 7, at: DateTime.utc(2026, 8, 10)),
              const HighScore(score: 9000, wave: 4),
              const HighScore(score: 6200, wave: 5, easy: true),
            ],
            gamesPlayed: 22,
            totalKills: 3110,
          ),
          'snake': ArcadeGameProgress(
            highScores: [
              HighScore(
                score: 320,
                at: DateTime.utc(2026, 8, 9),
                counting: true,
              ),
              const HighScore(score: 180, easy: true, counting: true),
            ],
            gamesPlayed: 14,
            totalKills: 96,
            bestLength: 24,
          ),
        },
      ),
      draw: const DrawProgress(
        drawingCount: 7,
        lastDrawingId: 'd7',
        bytesUsed: 4820112,
      ),
      tracks: TracksProgress(
        solved: {
          'tracks:5x5:easy:2': SolvedPuzzle(
            timeMs: 52000,
            mistakes: 1,
            solvedAt: DateTime.utc(2026, 8, 13, 16, 5),
            clean: true,
          ),
          'tracks:7x7:medium:9': const SolvedPuzzle(timeMs: 188000, hints: 2),
        },
        inProgress: const {
          // Row 2's west port only, so the board is partial but valid: it
          // passes every structural check the codec makes.
          'tracks:5x5:easy:4': TracksInProgress(
            cells: '0000000000800000000000000',
            marks: '0000000000000001000000000',
            elapsedMs: 31000,
            undoStack: ['+r2c0:8'],
            hints: 1,
          ),
        },
        bestTimeMs: {'5x5:easy': 52000},
        bestSolve: {
          '5x5:easy': SolvedPuzzle(
            timeMs: 52000,
            mistakes: 1,
            solvedAt: DateTime.utc(2026, 8, 13, 16, 5),
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
/// nothing else changed but the line the longest of them no longer fits on.
/// The plan elides four values — two timestamps, the in-progress board, and the
/// two halves of the cached record — and each is filled with something of the
/// right shape.
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
    "sound": true, "music": false, "hapticsLevel": "low",
    "showTimer": false, "theme": "day", "reduceMotion": false
  },
  "profiles": [{
    "id": "p1", "name": "Ana", "avatar": "fox", "createdAt": "2026-08-11T10:00:00Z",
    "mistakeFeedback": "atCompletion",
    "arcadeEasyMode": true, "arcadeAutoFire": true, "padSide": "left",
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
      "invaders": { "highScores": [{ "score": 15400, "wave": 7,
                                     "at": "2026-08-10T00:00:00Z", "easy": false },
                                   { "score": 6200, "wave": 5, "easy": true }],
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

/// The exact output of `encodeSave(fullSave())`, pretty-printed, as `fullSave()`
/// stood on main before Tracks' save fields (`PLAN-phase-9-tracks.md` §6, PR 4),
/// frozen as text so that a later change to [fullSave] cannot quietly move it.
///
/// It stands for a real file written by a build that predates Tracks: no
/// `tracks` block and no `tracksTheme` on either profile.
const String preTracksSaveJson = '''
{
  "schemaVersion": 1,
  "generatorVersion": 1,
  "activeProfileId": "p2",
  "settings": {
    "sound": false,
    "music": true,
    "hapticsLevel": "high",
    "showTimer": true,
    "theme": "night",
    "reduceMotion": true,
    "allowPhotoImport": true
  },
  "profiles": [
    {
      "id": "p1",
      "name": "Ana",
      "avatar": "fox",
      "createdAt": "2026-08-11T10:00:00.000Z",
      "sudoku": {
        "solved": {
          "sudoku:6x6:easy:3": {
            "timeMs": 61000,
            "hints": 1,
            "mistakes": 0,
            "clean": false
          },
          "sudoku:9x9:easy:0": {
            "timeMs": 244000,
            "hints": 0,
            "mistakes": 2,
            "solvedAt": "2026-08-11T10:30:00.000Z",
            "clean": true
          }
        },
        "inProgress": {
          "sudoku:9x9:hard:12": {
            "grid": "53..7....6..195...",
            "notes": "1,2|3|",
            "elapsedMs": 90000,
            "undoStack": [
              "r0c0=5",
              "r0c1=3"
            ],
            "hints": 1
          }
        },
        "dailyStreak": {
          "current": 4,
          "best": 11,
          "lastDayIndex": 223
        },
        "bestTimeMs": {
          "9x9:easy": 180000,
          "9x9:medium": 402000
        }
      },
      "arcade": {
        "invaders": {
          "highScores": [
            {
              "score": 15400,
              "wave": 7,
              "at": "2026-08-10T00:00:00.000Z",
              "easy": false,
              "counting": false
            },
            {
              "score": 9000,
              "wave": 4,
              "easy": false,
              "counting": false
            },
            {
              "score": 6200,
              "wave": 5,
              "easy": true,
              "counting": false
            }
          ],
          "gamesPlayed": 22,
          "totalKills": 3110,
          "bestLength": 0
        },
        "snake": {
          "highScores": [
            {
              "score": 320,
              "wave": 0,
              "at": "2026-08-09T00:00:00.000Z",
              "easy": false,
              "counting": true
            },
            {
              "score": 180,
              "wave": 0,
              "easy": true,
              "counting": true
            }
          ],
          "gamesPlayed": 14,
          "totalKills": 96,
          "bestLength": 24
        }
      },
      "draw": {
        "drawingCount": 7,
        "lastDrawingId": "d7",
        "bytesUsed": 4820112
      },
      "mistakeFeedback": "atCompletion",
      "arcadeEasyMode": true,
      "arcadeAutoFire": true,
      "padSide": "left",
      "snakeCounting": "twos"
    },
    {
      "id": "p2",
      "name": "Bo",
      "avatar": "owl",
      "createdAt": "2026-08-12T09:15:00.000Z",
      "sudoku": {
        "solved": {},
        "inProgress": {},
        "dailyStreak": {
          "current": 0,
          "best": 0
        },
        "bestTimeMs": {}
      },
      "arcade": {},
      "draw": {
        "drawingCount": 0,
        "bytesUsed": 0
      },
      "mistakeFeedback": "immediate",
      "arcadeEasyMode": false,
      "arcadeAutoFire": false,
      "padSide": "right",
      "snakeCounting": "ones"
    }
  ],
  "puzzleCache": {
    "sudoku:9x9:hard:12": "53..7....6..195..."
  }
}''';
