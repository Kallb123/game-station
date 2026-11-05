// The model's own rules: value equality, the two invariants a save always
// holds, and the promise that this layer needs no filesystem to exist.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/save_data.dart';

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

    test('quiz progress compares by value, with known as a set', () {
      const title = QuizTitleProgress(seed: 1, next: 2, pool: 3);
      final a = QuizProgress(known: {'x', 'y'}, titles: {'t': title});
      final b = QuizProgress(known: {'y', 'x'}, titles: {'t': title});

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(known: {'x'})));
      expect(a, isNot(a.copyWith(mixed: const QuizMixedProgress(rounds: 1))));
      expect(a, isNot(a.copyWith(titles: const {})));
      expect(a.copyWith(), a);
    });

    test('quiz titles and mixed counters compare field by field', () {
      const title = QuizTitleProgress(
        seed: 1,
        next: 2,
        pool: 3,
        rounds: 4,
        best: 5,
      );

      expect(
        title,
        const QuizTitleProgress(seed: 1, next: 2, pool: 3, rounds: 4, best: 5),
      );
      expect(
        title.hashCode,
        const QuizTitleProgress(
          seed: 1,
          next: 2,
          pool: 3,
          rounds: 4,
          best: 5,
        ).hashCode,
      );
      expect(title, isNot(const QuizTitleProgress(seed: 1, next: 2, pool: 3)));
      expect(
        const QuizMixedProgress(rounds: 1, best: 2),
        const QuizMixedProgress(rounds: 1, best: 2),
      );
      expect(
        const QuizMixedProgress(rounds: 1, best: 2),
        isNot(const QuizMixedProgress(rounds: 1, best: 3)),
      );
      expect(const QuizMixedProgress(), const QuizMixedProgress(rounds: 0));
    });

    test('a difference in the quiz field is a difference at the root', () {
      final profile = fullSave().profiles.first;
      final changed = fullSave().copyWith(
        profiles: [
          profile.copyWith(quiz: const QuizProgress(known: {'other'})),
          fullSave().profiles.last,
        ],
      );

      expect(changed, isNot(fullSave()));
      expect(profile.copyWith(quiz: const QuizProgress()), isNot(profile));
    });

    test('a difference in the Tracks fields is a difference at the root', () {
      final profile = fullSave().profiles.first;
      SaveData with_(Profile changed) =>
          fullSave().copyWith(profiles: [changed, fullSave().profiles.last]);

      expect(
        with_(profile.copyWith(tracksTheme: TracksTheme.snail)),
        isNot(fullSave()),
      );
      expect(
        with_(
          profile.copyWith(
            tracks: profile.tracks.copyWith(bestTimeMs: const {'5x5:easy': 1}),
          ),
        ),
        isNot(fullSave()),
      );
      expect(
        with_(
          profile.copyWith(
            tracks: profile.tracks.copyWith(
              bestSolve: const {'5x5:easy': SolvedPuzzle(timeMs: 52000)},
            ),
          ),
        ),
        isNot(fullSave()),
      );
      expect(
        with_(
          profile.copyWith(
            sudoku: profile.sudoku.copyWith(
              bestSolve: const {'9x9:easy': SolvedPuzzle(timeMs: 180000)},
            ),
          ),
        ),
        isNot(fullSave()),
      );
      expect(
        with_(
          profile.copyWith(
            tracks: profile.tracks.copyWith(
              inProgress: const {
                'tracks:5x5:easy:4': TracksInProgress(cells: 'x'),
              },
            ),
          ),
        ),
        isNot(fullSave()),
      );
    });

    test('maps compare by content, not by insertion order', () {
      SudokuProgress best(List<String> keys) =>
          SudokuProgress(bestTimeMs: {for (final key in keys) key: 1});

      expect(best(['a', 'b']), best(['b', 'a']));
      expect(best(['a', 'b']).hashCode, best(['b', 'a']).hashCode);

      TracksProgress tracks(List<String> keys) =>
          TracksProgress(bestTimeMs: {for (final key in keys) key: 1});

      expect(tracks(['a', 'b']), tracks(['b', 'a']));
      expect(tracks(['a', 'b']).hashCode, tracks(['b', 'a']).hashCode);
    });

    test('bestSolve takes part in equality, hashing and copyWith', () {
      const solve = SolvedPuzzle(timeMs: 1000, hints: 1);
      const sudoku = SudokuProgress(bestSolve: {'9x9:easy': solve});
      const tracks = TracksProgress(bestSolve: {'7x7:easy': solve});

      expect(sudoku, isNot(const SudokuProgress()));
      expect(sudoku.hashCode, isNot(const SudokuProgress().hashCode));
      expect(sudoku.copyWith(), sudoku);
      expect(sudoku.copyWith(bestSolve: const {}), const SudokuProgress());
      expect(tracks, isNot(const TracksProgress()));
      expect(tracks.hashCode, isNot(const TracksProgress().hashCode));
      expect(tracks.copyWith(), tracks);
      expect(tracks.copyWith(bestSolve: const {}), const TracksProgress());
    });
  });

  // The consistency rule of `PLAN-best-time-assists.md` §4.2.
  group('bestSolveFor', () {
    const solve = SolvedPuzzle(timeMs: 1000, hints: 2, mistakes: 1);

    test('returns the entry when bestTimeMs agrees with its time', () {
      const sudoku = SudokuProgress(
        bestTimeMs: {'9x9:easy': 1000},
        bestSolve: {'9x9:easy': solve},
      );
      const tracks = TracksProgress(
        bestTimeMs: {'7x7:easy': 1000},
        bestSolve: {'7x7:easy': solve},
      );

      expect(sudoku.bestSolveFor('9x9:easy'), solve);
      expect(tracks.bestSolveFor('7x7:easy'), solve);
    });

    test('is null when the times disagree', () {
      const sudoku = SudokuProgress(
        bestTimeMs: {'9x9:easy': 900},
        bestSolve: {'9x9:easy': solve},
      );
      const tracks = TracksProgress(
        bestTimeMs: {'7x7:easy': 900},
        bestSolve: {'7x7:easy': solve},
      );

      expect(sudoku.bestSolveFor('9x9:easy'), isNull);
      expect(tracks.bestSolveFor('7x7:easy'), isNull);
    });

    test('is null when bestTimeMs has no such key, or bestSolve has none', () {
      const sudoku = SudokuProgress(
        bestTimeMs: {'9x9:medium': 1000},
        bestSolve: {'9x9:easy': solve},
      );
      const tracks = TracksProgress(
        bestTimeMs: {'7x7:medium': 1000},
        bestSolve: {'7x7:easy': solve},
      );

      expect(sudoku.bestSolveFor('9x9:easy'), isNull);
      expect(sudoku.bestSolveFor('9x9:medium'), isNull);
      expect(tracks.bestSolveFor('7x7:easy'), isNull);
      expect(tracks.bestSolveFor('7x7:medium'), isNull);
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
