// The players file's codec. The decision these tests protect is that the file
// *is* the save codec's output (`PLAN-transfer.md` §3.1): a profile with every
// field off its default must come back whole, so a field the save codec drops
// is a failure here too.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzle_engine/puzzle_engine.dart' as engine;
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/features/draw/data/drawing_codec.dart';
import 'package:zibo_games/features/draw/model/stroke.dart';
import 'package:zibo_games/features/transfer/data/transfer_codec.dart';

import '../../../core/storage/save_fixtures.dart';

/// A drawing as the parsed JSON a file holds.
Map<String, Object?> drawingJson(String id) =>
    jsonDecode(
          encodeDrawing(
            Drawing(
              id: id,
              createdAt: DateTime.utc(2026, 8, 11, 12),
              strokes: const [
                Stroke(
                  colorIndex: 2,
                  sizeIndex: 1,
                  points: [Offset(1.5, 2.5), Offset(30, 40)],
                ),
              ],
            ),
          ),
        )
        as Map<String, Object?>;

/// A second profile with every field off its default, so that between the two
/// of them nothing is covered only by the default.
Profile fullSecondProfile() => Profile(
  id: 'p2',
  name: 'Bo',
  avatar: AvatarId.owl,
  createdAt: DateTime.utc(2026, 8, 12, 9, 15, 30, 250, 125),
  mistakeFeedback: MistakeFeedback.atCompletion,
  arcadeEasyMode: true,
  arcadeAutoFire: true,
  padSide: PadSide.left,
  snakeCounting: SnakeCounting.twos,
  sudoku: SudokuProgress(
    solved: {
      'sudoku:4x4:easy:1': SolvedPuzzle(
        timeMs: 9000,
        hints: 2,
        mistakes: 1,
        solvedAt: DateTime.utc(2026, 8, 12, 10),
        clean: true,
      ),
    },
    inProgress: const {
      'sudoku:6x6:medium:5': PuzzleInProgress(
        grid: '1..2',
        notes: '1|2',
        elapsedMs: 4000,
        undoStack: ['r0c0=1'],
        hints: 1,
      ),
    },
    dailyStreak: const DailyStreak(current: 2, best: 3, lastDayIndex: 224),
    bestTimeMs: const {'4x4:easy': 9000},
  ),
  arcade: ArcadeProgress(
    games: {
      'invaders': ArcadeGameProgress(
        highScores: [
          HighScore(
            score: 1200,
            wave: 3,
            at: DateTime.utc(2026, 8, 12),
            easy: true,
            counting: true,
          ),
        ],
        gamesPlayed: 3,
        totalKills: 40,
        bestLength: 9,
      ),
    },
  ),
  draw: const DrawProgress(
    drawingCount: 3,
    lastDrawingId: 'd2',
    bytesUsed: 777,
  ),
);

TransferBundle fullBundle() => TransferBundle(
  exportedAt: DateTime.utc(2026, 10, 8, 9),
  everyone: true,
  settings: const AppSettings(
    sound: false,
    music: true,
    hapticsLevel: HapticsLevel.high,
    showTimer: true,
    theme: ThemeChoice.night,
    reduceMotion: true,
    allowPhotoImport: true,
  ),
  profiles: [fullSave().profiles.first, fullSecondProfile()],
  drawings: {
    'p1': {'d1': drawingJson('d1'), 'd2': drawingJson('d2')},
    'p2': {'d1': drawingJson('d1')},
  },
);

/// [text] decoded, edited by [edit], and encoded again.
String patched(String text, void Function(Map<String, Object?> json) edit) {
  final json = jsonDecode(text) as Map<String, Object?>;
  edit(json);
  return jsonEncode(json);
}

Matcher refusedAs(TransferProblem problem) => throwsA(
  isA<TransferException>().having((e) => e.problem, 'problem', problem),
);

void main() {
  group('round trip', () {
    test('every profile and settings field, and the drawings, survive', () {
      final original = fullBundle();

      final decoded = decodeTransfer(encodeTransfer(original));

      expect(decoded, original);
      expect(decoded.profiles, original.profiles);
      expect(decoded.settings, original.settings);
      expect(decoded.drawings, original.drawings);
    });

    test('the fixture really has no field at its default', () {
      // A guard on the test above: a profile that quietly fell back to
      // defaults would round trip just as well.
      const defaults = AppSettings();
      final settings = fullBundle().settings;
      expect(settings.sound, isNot(defaults.sound));
      expect(settings.music, isNot(defaults.music));
      expect(settings.hapticsLevel, isNot(defaults.hapticsLevel));
      expect(settings.showTimer, isNot(defaults.showTimer));
      expect(settings.theme, isNot(defaults.theme));
      expect(settings.reduceMotion, isNot(defaults.reduceMotion));
      expect(settings.allowPhotoImport, isNot(defaults.allowPhotoImport));

      final profile = fullSecondProfile();
      expect(profile.mistakeFeedback, MistakeFeedback.atCompletion);
      expect(profile.padSide, PadSide.left);
      expect(profile.snakeCounting, SnakeCounting.twos);
      expect(profile.arcadeEasyMode, isTrue);
      expect(profile.arcadeAutoFire, isTrue);
      expect(profile.draw, isNot(const DrawProgress()));
    });

    test('a single-player file keeps everyone false', () {
      final one = TransferBundle(
        exportedAt: DateTime.utc(2026, 10, 8),
        everyone: false,
        settings: const AppSettings(),
        profiles: [fullSecondProfile()],
      );

      final decoded = decodeTransfer(encodeTransfer(one));

      expect(decoded.everyone, isFalse);
      expect(decoded, one);
    });

    test('a profile with no drawings entry decodes with none', () {
      final bundle = TransferBundle(
        exportedAt: DateTime.utc(2026, 10, 8),
        everyone: true,
        settings: const AppSettings(),
        profiles: fullBundle().profiles,
        drawings: {
          'p1': {'d1': drawingJson('d1')},
        },
      );

      expect(decodeTransfer(encodeTransfer(bundle)).drawings.keys, ['p1']);
    });

    test('the file is shaped as PLAN-transfer.md §3.1 shows', () {
      final json = jsonDecode(encodeTransfer(fullBundle())) as Map;

      expect(json['format'], 'zibo-games-players');
      expect(json['formatVersion'], 1);
      expect(json['exportedAt'], '2026-10-08T09:00:00.000Z');
      expect(json['everyone'], isTrue);
      expect((json['save'] as Map)['activeProfileId'], 'p1');
      expect((json['save'] as Map)['puzzleCache'], isEmpty);
      expect(json['drawings'], contains('p1'));
      expect(transferFileExtension, '.zibo.json');
    });
  });

  group('deterministic bytes', () {
    test('insertion order of profiles and drawings does not matter', () {
      final base = fullBundle();
      final reversed = TransferBundle(
        exportedAt: base.exportedAt,
        everyone: base.everyone,
        settings: base.settings,
        profiles: base.profiles,
        drawings: {
          'p2': {'d1': base.drawings['p2']!['d1']!},
          'p1': {
            'd2': base.drawings['p1']!['d2']!,
            'd1': base.drawings['p1']!['d1']!,
          },
        },
      );

      expect(encodeTransfer(reversed), encodeTransfer(base));
    });

    test('encode, decode, encode is byte-identical', () {
      final once = encodeTransfer(fullBundle());

      expect(encodeTransfer(decodeTransfer(once)), once);
    });
  });

  group('a file that is not a players file', () {
    final good = encodeTransfer(fullBundle());

    test('is refused as notAPlayersFile', () {
      final cases = <String, String>{
        'empty': '',
        'not JSON': 'zibo',
        'truncated': good.substring(0, good.length ~/ 2),
        'a list': '[]',
        'a save file': encodeTransferSaveOnly(),
        'wrong format': patched(good, (j) => j['format'] = 'something-else'),
        'no format': patched(good, (j) => j.remove('format')),
        'no formatVersion': patched(good, (j) => j.remove('formatVersion')),
        'formatVersion as text': patched(good, (j) => j['formatVersion'] = '1'),
        'formatVersion zero': patched(good, (j) => j['formatVersion'] = 0),
        'no exportedAt': patched(good, (j) => j.remove('exportedAt')),
        'exportedAt not a date': patched(
          good,
          (j) => j['exportedAt'] = 'yesterday',
        ),
        'no everyone': patched(good, (j) => j.remove('everyone')),
        'no save': patched(good, (j) => j.remove('save')),
        'a save that does not read': patched(
          good,
          (j) => (j['save'] as Map<String, Object?>)['profiles'] = <Object?>[],
        ),
        'a save older than any migration': patched(
          good,
          (j) => (j['save'] as Map<String, Object?>)['schemaVersion'] = 0,
        ),
        'no drawings': patched(good, (j) => j.remove('drawings')),
        'drawings as a list': patched(good, (j) => j['drawings'] = <Object?>[]),
        'drawings for a stranger': patched(
          good,
          (j) => (j['drawings'] as Map<String, Object?>)['p9'] = {
            'd1': <String, Object?>{},
          },
        ),
        'a profile\'s drawings as a list': patched(
          good,
          (j) => (j['drawings'] as Map<String, Object?>)['p1'] = <Object?>[],
        ),
        'a drawing as text': patched(
          good,
          (j) =>
              ((j['drawings'] as Map<String, Object?>)['p1']
                      as Map<String, Object?>)['d1'] =
                  'not a drawing',
        ),
      };

      for (final entry in cases.entries) {
        expect(
          () => decodeTransfer(entry.value),
          refusedAs(TransferProblem.notAPlayersFile),
          reason: entry.key,
        );
      }
    });
  });

  group('a file from a newer app', () {
    final good = encodeTransfer(fullBundle());

    test('with a newer formatVersion is refused as fromNewerApp', () {
      expect(
        () => decodeTransfer(
          patched(good, (j) => j['formatVersion'] = transferFormatVersion + 1),
        ),
        refusedAs(TransferProblem.fromNewerApp),
      );
    });

    test('with a newer save schemaVersion is refused as fromNewerApp', () {
      expect(
        () => decodeTransfer(
          patched(
            good,
            (j) => (j['save'] as Map<String, Object?>)['schemaVersion'] =
                currentSchemaVersion + 1,
          ),
        ),
        refusedAs(TransferProblem.fromNewerApp),
      );
    });

    test('is judged by formatVersion before the rest is read', () {
      // A newer layout may have moved every key; the one sentence that helps a
      // parent is "update the app", not "this is not a players file".
      final text = jsonEncode({
        'format': transferFormat,
        'formatVersion': transferFormatVersion + 1,
      });

      expect(
        () => decodeTransfer(text),
        refusedAs(TransferProblem.fromNewerApp),
      );
    });
  });

  group('a file from a different puzzle generator', () {
    test('is refused as differentPuzzleVersion', () {
      final other = TransferBundle(
        exportedAt: DateTime.utc(2026, 10, 8),
        everyone: true,
        settings: const AppSettings(),
        profiles: fullBundle().profiles,
        generatorVersion: engine.generatorVersion + 1,
      );

      expect(
        () => decodeTransfer(encodeTransfer(other)),
        refusedAs(TransferProblem.differentPuzzleVersion),
      );
    });

    test('and the exception carries a detail for the log', () {
      expect(
        () => decodeTransfer('nope'),
        throwsA(
          isA<TransferException>().having(
            (e) => e.detail,
            'detail',
            isNotEmpty,
          ),
        ),
      );
    });
  });
}

/// A bare save document, which a parent could pick by mistake.
String encodeTransferSaveOnly() {
  final json = jsonDecode(encodeTransfer(fullBundle())) as Map<String, Object?>;
  return jsonEncode(json['save']);
}
