// The model's own rules: value equality, the two invariants a save always
// holds, and the promise that this layer needs no filesystem to exist.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:game_station/core/storage/save_data.dart';

import 'save_fixtures.dart';

void main() {
  group('value equality', () {
    test('two identically built saves are equal and hash alike', () {
      expect(fullSave(), fullSave());
      expect(fullSave().hashCode, fullSave().hashCode);
    });

    test('a difference anywhere in the tree is a difference at the root', () {
      final changed = fullSave().copyWith(
        profiles: [
          fullSave().profiles.first.copyWith(
            sudoku: const SudokuProgress(
              solved: {'sudoku:9x9:easy:0': SolvedPuzzle(timeMs: 1)},
            ),
          ),
          fullSave().profiles.last,
        ],
      );

      expect(changed, isNot(fullSave()));
    });

    test('maps compare by content, not by insertion order', () {
      SudokuProgress best(List<String> keys) =>
          SudokuProgress(bestTimeMs: {for (final key in keys) key: 1});

      expect(best(['a', 'b']), best(['b', 'a']));
      expect(best(['a', 'b']).hashCode, best(['b', 'a']).hashCode);
    });
  });

  group('copyWith', () {
    test('changes only what it is given', () {
      final save = fullSave();
      final themed = save.copyWith(
        settings: save.settings.copyWith(theme: ThemeChoice.day),
      );

      expect(themed.settings.theme, ThemeChoice.day);
      expect(themed.settings.sound, save.settings.sound);
      expect(themed.profiles, save.profiles);
      expect(themed.activeProfileId, save.activeProfileId);
    });

    test('a profile keeps its identity and its creation time', () {
      final profile = fullSave().profiles.first;
      final renamed = profile.copyWith(name: 'Bo');

      expect(renamed.name, 'Bo');
      expect(renamed.id, profile.id);
      expect(renamed.createdAt, profile.createdAt);
      expect(renamed.sudoku, profile.sudoku);
    });
  });

  group('invariants', () {
    test('a save with no profiles is rejected', () {
      expect(
        () => SaveData(activeProfileId: 'p1', profiles: const []),
        throwsA(isA<AssertionError>()),
      );
    });

    test('activeProfileId must name a profile that exists', () {
      expect(
        () => SaveData(
          activeProfileId: 'p9',
          profiles: [
            Profile(
              id: 'p1',
              name: 'Ana',
              avatar: AvatarId.fox,
              createdAt: DateTime.utc(2026),
            ),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('createdAt must be UTC, so two saves compare by instant', () {
      expect(
        () => Profile(
          id: 'p1',
          name: 'Ana',
          avatar: AvatarId.fox,
          createdAt: DateTime(2026),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('activeProfile resolves to the named profile', () {
      expect(fullSave().activeProfile.name, 'Bo');
    });
  });

  test('the first launch starts with one profile and default settings', () {
    final save = SaveData.initial(createdAt: DateTime.utc(2026, 8, 11));

    expect(save.profiles, hasLength(1));
    expect(save.activeProfileId, firstProfileId);
    expect(save.activeProfile.id, firstProfileId);
    expect(save.settings, const AppSettings());
    expect(save.schemaVersion, currentSchemaVersion);
    expect(save.activeProfile.createdAt.isUtc, isTrue);
  });

  // PLAN-phase-1.md §1: the model and codec import no `dart:io` and no Flutter,
  // so the schema stays testable without a filesystem and a widget test can
  // build a save by hand. That is a property of the source, not of behaviour,
  // and nothing else would notice it breaking — `flutter analyze` is perfectly
  // happy with `dart:io` in `lib/`.
  test('the storage model and codec import no filesystem and no Flutter', () {
    const files = [
      'lib/core/storage/save_data.dart',
      'lib/core/storage/save_codec.dart',
    ];
    const banned = ['dart:io', 'dart:ui', 'package:flutter/'];

    for (final path in files) {
      final file = File(path);
      // Relative to the package root, which is where `flutter test` runs. A
      // clear failure here beats an unhandled FileSystemException if that ever
      // stops being true.
      expect(
        file.existsSync(),
        isTrue,
        reason: '$path not found from ${Directory.current.path}',
      );
      final source = file.readAsStringSync();
      for (final import in banned) {
        expect(
          source.contains("import '$import"),
          isFalse,
          reason: '$path imports $import',
        );
      }
    }
  });
}
