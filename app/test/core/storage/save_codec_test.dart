// The codec's tests. Schema v1 has to be right before anything writes a file
// with it (PLAN-phase-1.md §3): once a save has shipped, a mistake here costs a
// migration rather than an edit.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/save_codec.dart';
import 'package:game_station/core/storage/save_data.dart';

import 'save_fixtures.dart';

void main() {
  group('round trip', () {
    test('a save with every field survives encode and decode', () {
      final original = fullSave();

      expect(decodeSave(encodeSave(original)), original);
    });

    test('encode is stable across a decode', () {
      // The PR's done-criterion: encode → decode → encode is byte-identical, so
      // rewriting an unchanged save cannot rewrite the file differently.
      final once = encodeSave(fullSave());

      expect(encodeSave(decodeSave(once)), once);
    });

    test('data-named keys are written in sorted order', () {
      // Two saves built by inserting the same puzzles in opposite orders are
      // the same save, so they must produce the same bytes — otherwise the
      // store would rewrite the file after a no-op mutation.
      SaveData withSolvedOrder(List<String> ids) => SaveData(
        activeProfileId: 'p1',
        profiles: [
          Profile(
            id: 'p1',
            name: 'Ana',
            avatar: AvatarId.fox,
            createdAt: DateTime.utc(2026),
            sudoku: SudokuProgress(
              solved: {for (final id in ids) id: const SolvedPuzzle(timeMs: 1)},
            ),
          ),
        ],
      );

      expect(
        encodeSave(withSolvedOrder(['b', 'a', 'c'])),
        encodeSave(withSolvedOrder(['c', 'b', 'a'])),
      );
      expect(encodeSave(withSolvedOrder(['b', 'a'])), contains('"a":'));
    });

    test('an empty save round trips', () {
      final empty = SaveData.initial(createdAt: DateTime.utc(2026, 8, 11));

      expect(decodeSave(encodeSave(empty)), empty);
    });
  });

  group('decoding a v1 file', () {
    test('the PLAN.md §5.2 example decodes with nothing lost', () {
      final save = decodeSave(planExampleJson);

      expect(save.schemaVersion, currentSchemaVersion);
      expect(save.generatorVersion, 1);
      expect(save.activeProfileId, 'p1');
      expect(save.settings, const AppSettings(theme: ThemeChoice.day));
      expect(save.puzzleCache, {'sudoku:9x9:hard:12': '53..7....|534678912'});

      final profile = save.activeProfile;
      expect(profile.name, 'Ana');
      expect(profile.avatar, AvatarId.fox);
      expect(profile.createdAt, DateTime.utc(2026, 8, 11, 10));
      // Not the default, so this asserts the field is read rather than filled
      // in — the same reason the plan's example carries `"theme": "day"`.
      expect(profile.mistakeFeedback, MistakeFeedback.atCompletion);

      expect(
        profile.sudoku.solved['sudoku:9x9:easy:0'],
        SolvedPuzzle(
          timeMs: 244000,
          mistakes: 2,
          solvedAt: DateTime.utc(2026, 8, 11, 10, 30),
          clean: true,
        ),
      );
      // The plan's second solved entry has no `solvedAt`, which is why the
      // field is optional rather than required.
      expect(
        profile.sudoku.solved['sudoku:6x6:easy:3'],
        const SolvedPuzzle(timeMs: 61000, hints: 1),
      );
      expect(
        profile.sudoku.inProgress['sudoku:9x9:hard:12'],
        const PuzzleInProgress(
          grid: '53..7....',
          notes: '1,2|3|',
          elapsedMs: 90000,
          hints: 1,
        ),
      );
      expect(
        profile.sudoku.dailyStreak,
        const DailyStreak(current: 4, best: 11, lastDayIndex: 223),
      );
      expect(profile.sudoku.bestTimeMs, {
        '9x9:easy': 180000,
        '9x9:medium': 402000,
      });
      expect(
        profile.arcade.games['invaders'],
        ArcadeGameProgress(
          highScores: [
            HighScore(score: 15400, wave: 7, at: DateTime.utc(2026, 8, 10)),
          ],
          gamesPlayed: 22,
          totalKills: 3110,
        ),
      );
    });

    test('the example survives a re-encode', () {
      final save = decodeSave(planExampleJson);

      expect(decodeSave(encodeSave(save)), save);
    });

    test('missing optional blocks fall back to defaults', () {
      final save = decodeSave(minimalSaveJson);

      expect(save.settings, const AppSettings());
      expect(save.settings.theme, ThemeChoice.system);
      expect(save.generatorVersion, 1);
      expect(save.puzzleCache, isEmpty);
      expect(save.activeProfile.sudoku, const SudokuProgress());
      expect(save.activeProfile.arcade, const ArcadeProgress());
      expect(save.activeProfile.mistakeFeedback, MistakeFeedback.immediate);
    });

    test('timestamps are read back as UTC whatever zone they carry', () {
      final save = decodeSave(
        _patch(
          minimalSaveJson,
          '"2026-08-11T10:00:00Z"',
          '"2026-08-11T12:00:00+02:00"',
        ),
      );

      expect(save.activeProfile.createdAt.isUtc, isTrue);
      expect(save.activeProfile.createdAt, DateTime.utc(2026, 8, 11, 10));
    });
  });

  group('malformed input', () {
    test('text that is not JSON is a format error', () {
      expect(() => decodeSave('{oh no'), throwsA(isA<SaveFormatException>()));
    });

    test('a JSON document that is not an object is a format error', () {
      expect(() => decodeSave('[1, 2]'), throwsA(isA<SaveFormatException>()));
    });

    test('a wrong type is refused rather than coerced, and names its path', () {
      expect(
        () => decodeSave(
          _patch(planExampleJson, '"sound": true', '"sound": "true"'),
        ),
        throwsA(
          isA<SaveFormatException>()
              .having((e) => e.path, 'path', 'settings.sound')
              .having((e) => e.toString(), 'toString', contains('a string')),
        ),
      );
    });

    test('a nested wrong type names its full path', () {
      expect(
        () => decodeSave(
          _patch(planExampleJson, '"timeMs": 61000', '"timeMs": 61000.5'),
        ),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.path,
            'path',
            'profiles[0].sudoku.solved.sudoku:6x6:easy:3.timeMs',
          ),
        ),
      );
    });

    test('a required field that is missing is a format error', () {
      expect(
        () => decodeSave(_patch(minimalSaveJson, '"name": "Player 1",', '')),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.path,
            'path',
            'profiles[0].name',
          ),
        ),
      );
    });

    test('an unknown enum value is refused, not defaulted', () {
      expect(
        () => decodeSave(
          _patch(minimalSaveJson, '"avatar": "fox"', '"avatar": "dragon"'),
        ),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.toString(),
            'toString',
            contains('dragon'),
          ),
        ),
      );
      expect(
        () => decodeSave(
          _patch(planExampleJson, '"theme": "day"', '"theme": "sepia"'),
        ),
        throwsA(isA<SaveFormatException>()),
      );
    });

    test('a timestamp that is not ISO-8601 is a format error', () {
      expect(
        () => decodeSave(
          _patch(minimalSaveJson, '"2026-08-11T10:00:00Z"', '"last tuesday"'),
        ),
        throwsA(isA<SaveFormatException>()),
      );
    });

    test('a save with no profiles is refused', () {
      expect(
        () => decodeSave(
          '{"schemaVersion": 1, "activeProfileId": "p1", '
          '"profiles": []}',
        ),
        throwsA(isA<SaveFormatException>()),
      );
      expect(
        () => decodeSave('{"schemaVersion": 1, "activeProfileId": "p1"}'),
        throwsA(isA<SaveFormatException>()),
      );
    });

    test('duplicate profile ids are refused', () {
      final twoProfiles = _patch(
        minimalSaveJson,
        '"createdAt": "2026-08-11T10:00:00Z" }',
        '"createdAt": "2026-08-11T10:00:00Z" },'
            '{ "id": "p1", "name": "Bo", "avatar": "owl", '
            '"createdAt": "2026-08-11T10:00:00Z" }',
      );

      expect(
        () => decodeSave(twoProfiles),
        throwsA(isA<SaveFormatException>()),
      );
    });

    test('an activeProfileId naming nobody is repaired, not refused', () {
      // The one repair the codec makes. Refusing would move every profile aside
      // over one stale string, and picking the first profile loses nothing.
      final save = decodeSave(
        _patch(
          minimalSaveJson,
          '"activeProfileId": "p1"',
          '"activeProfileId": "p9"',
        ),
      );

      expect(save.activeProfileId, 'p1');
    });

    test('an activeProfileId that is absent is repaired too', () {
      final save = decodeSave(
        _patch(minimalSaveJson, '"activeProfileId": "p1",', ''),
      );

      expect(save.activeProfileId, 'p1');
    });

    test('an activeProfileId of the wrong type is still refused', () {
      expect(
        () => decodeSave(
          _patch(
            minimalSaveJson,
            '"activeProfileId": "p1"',
            '"activeProfileId": 1',
          ),
        ),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.path,
            'path',
            'activeProfileId',
          ),
        ),
      );
    });
  });

  group('schema version', () {
    test('a newer save is refused rather than guessed at', () {
      expect(
        () => decodeSave(
          _patch(minimalSaveJson, '"schemaVersion": 1', '"schemaVersion": 99'),
        ),
        throwsA(
          isA<UnsupportedSaveVersion>()
              .having((e) => e.found, 'found', 99)
              .having((e) => e.supported, 'supported', currentSchemaVersion),
        ),
      );
    });

    test('an older save with no migration step is refused', () {
      expect(
        () => decodeSave(
          _patch(minimalSaveJson, '"schemaVersion": 1', '"schemaVersion": 0'),
        ),
        throwsA(
          isA<UnsupportedSaveVersion>().having((e) => e.found, 'found', 0),
        ),
      );
    });

    test('a missing schemaVersion is a format error', () {
      expect(
        () => decodeSave(_patch(minimalSaveJson, '"schemaVersion": 1,', '')),
        throwsA(
          isA<SaveFormatException>().having(
            (e) => e.path,
            'path',
            'schemaVersion',
          ),
        ),
      );
    });

    test('UnsupportedSaveVersion is not caught as a format error', () {
      // The store files the two cases separately, so a `catch` on one must not
      // swallow the other.
      expect(
        const UnsupportedSaveVersion(found: 99),
        isNot(isA<SaveFormatException>()),
      );
    });
  });

  // There is no real migration step yet — v1 is the first schema. The loop that
  // will run them is still worth testing, because its failure mode is silence
  // until the day a step is added, which is the day it would lose a save.
  group('the migration chain', () {
    test('ships empty, because v1 is the first schema', () {
      expect(migrationSteps, isEmpty);
    });

    // Negative synthetic versions, so these fixtures can never collide with a
    // real schema version added later.
    test('applies steps in order until the version is current', () {
      final applied = <int>[];

      final raw = migrate(
        <String, Object?>{'schemaVersion': -2, 'marker': 'kept'},
        steps: {
          -2: (raw) {
            applied.add(-2);
            return {...raw, 'schemaVersion': -1};
          },
          -1: (raw) {
            applied.add(-1);
            return {...raw, 'schemaVersion': currentSchemaVersion};
          },
        },
      );

      expect(applied, [-2, -1]);
      expect(raw['schemaVersion'], currentSchemaVersion);
      expect(raw['marker'], 'kept', reason: 'a step must not drop other keys');
    });

    test('a step that does not advance the version is a programming error', () {
      expect(
        () => migrate(
          <String, Object?>{'schemaVersion': 0},
          steps: {0: (raw) => raw},
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a gap in the chain is refused', () {
      expect(
        () => migrate(
          <String, Object?>{'schemaVersion': -2},
          steps: {
            -1: (raw) => {...raw, 'schemaVersion': currentSchemaVersion},
          },
        ),
        throwsA(isA<UnsupportedSaveVersion>()),
      );
    });
  });

  group('encoded shape', () {
    test('enums are stored by name', () {
      final json = jsonDecode(encodeSave(fullSave())) as Map<String, Object?>;
      final settings = json['settings']! as Map<String, Object?>;
      final profiles = json['profiles']! as List<Object?>;

      expect(settings['theme'], 'night');
      expect((profiles.first! as Map<String, Object?>)['avatar'], 'fox');
    });

    test('timestamps are stored as ISO-8601 UTC', () {
      final save = SaveData.initial(
        // A local-zone instant, so a codec that skipped `toUtc()` would write a
        // different string here.
        createdAt: DateTime.utc(2026, 8, 11, 10).toLocal(),
      );

      expect(
        encodeSave(save),
        contains('"createdAt":"2026-08-11T10:00:00.000Z"'),
      );
    });

    test('absent optional values are omitted rather than written as null', () {
      final json = encodeSave(
        SaveData(
          activeProfileId: 'p1',
          profiles: [
            Profile(
              id: 'p1',
              name: 'Ana',
              avatar: AvatarId.fox,
              createdAt: DateTime.utc(2026),
              sudoku: const SudokuProgress(
                solved: {'x': SolvedPuzzle(timeMs: 1)},
              ),
            ),
          ],
        ),
      );

      expect(json, isNot(contains('null')));
      expect(json, isNot(contains('solvedAt')));
      expect(json, isNot(contains('lastDayIndex')));
    });
  });
}

/// Replaces the single occurrence of [from] in [source] with [to].
///
/// The tests build broken documents by editing a good one, so each case shows
/// only what makes it broken. Asserting the match is unique keeps a fixture
/// edit from silently turning a test into a different one.
String _patch(String source, String from, String to) {
  expect(
    from.allMatches(source).length,
    1,
    reason: 'the fixture must contain "$from" exactly once',
  );
  return source.replaceFirst(from, to);
}
