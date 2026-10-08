// The repository half of loading a players file (`PLAN-transfer.md` §3.2):
// planning where each incoming profile goes, and applying that in one
// mutation. The file and the drawings are `transfer_service_test.dart`'s.

import 'package:flutter_test/flutter_test.dart';
import 'package:zibo_games/core/storage/progress_repository.dart';
import 'package:zibo_games/core/storage/save_data.dart';
import 'package:zibo_games/core/storage/save_store.dart';

void main() {
  final starterCreatedAt = DateTime.utc(2026, 8, 12, 9);

  Profile incoming(String id, int day, {String name = 'Ana'}) => Profile(
    id: id,
    name: name,
    avatar: AvatarId.bear,
    createdAt: DateTime.utc(2026, 7, day),
  );

  ProgressRepository repositoryOver(SaveData save) {
    // A clock that moves, because `createdAt` is how an import recognises a
    // child: two profiles made "at the same instant" would be one.
    var tick = 0;
    final repository = ProgressRepository(
      MemorySaveStore(initial: save),
      initial: save,
      now: () => starterCreatedAt.add(Duration(minutes: ++tick)),
    );
    addTearDown(repository.dispose);
    return repository;
  }

  ProgressRepository fresh() =>
      repositoryOver(SaveData.initial(createdAt: starterCreatedAt));

  group('planning', () {
    test('is a pure read', () {
      final repository = fresh();
      final before = repository.data;

      repository.planProfileImport([incoming('p1', 1)]);

      expect(repository.data, before);
      expect(repository.isSaving, isFalse);
    });

    test('a matching createdAt replaces the local profile under its id', () {
      final repository = fresh();
      // The file's own id is unrelated to the local one; only the instant
      // says whose this is.
      final plan = repository.planProfileImport([
        incoming('p7', 1).copyWith(name: 'Zed'),
        Profile(
          id: 'p9',
          name: 'Back',
          avatar: AvatarId.cat,
          createdAt: starterCreatedAt,
        ),
      ]);

      expect(plan.entries.map((e) => e.localId), ['p2', 'p1']);
      expect(plan.entries.map((e) => e.replaces), [false, true]);
    });

    test('new profiles are numbered after the highest id in use, and after '
        'the ids already handed out in the same plan', () {
      final repository = fresh()
        ..createProfile(avatar: AvatarId.dog)
        ..createProfile(avatar: AvatarId.dog)
        ..deleteProfile('p2');

      final plan = repository.planProfileImport([
        incoming('a', 1),
        incoming('b', 2),
      ]);

      // p1 and p3 remain, so the next free number is 4 and then 5.
      expect(plan.entries.map((e) => e.localId), ['p4', 'p5']);
    });

    test('two incoming profiles with one createdAt replace once, then add', () {
      final repository = fresh();

      final plan = repository.planProfileImport([
        incoming('a', 1).copyWith(),
        Profile(
          id: 'b',
          name: 'Twin',
          avatar: AvatarId.cat,
          createdAt: starterCreatedAt,
        ),
        Profile(
          id: 'c',
          name: 'Twin 2',
          avatar: AvatarId.cat,
          createdAt: starterCreatedAt,
        ),
      ]);

      expect(plan.entries.map((e) => (e.localId, e.replaces)), [
        ('p2', false),
        ('p1', true),
        ('p3', false),
      ]);
    });

    test('the untouched starter is dropped when something is added', () {
      final plan = fresh().planProfileImport([incoming('a', 1)]);

      expect(plan.droppedStarter?.id, 'p1');
    });

    test('a starter that was played, renamed or given another avatar is not '
        'dropped', () {
      for (final change in <void Function(ProgressRepository)>[
        (r) => r.renameProfile('p1', 'Kai'),
        (r) => r.setProfileAvatar('p1', AvatarId.owl),
        (r) => r.setMistakeFeedback('p1', MistakeFeedback.atCompletion),
        (r) => r.setArcadeOptions(padSide: PadSide.left),
        (r) => r.startArcadeGame('invaders'),
        (r) =>
            r.recordDrawingSaved(drawingId: 'd1', isNew: true, totalBytes: 10),
      ]) {
        final repository = fresh();
        change(repository);

        final plan = repository.planProfileImport([incoming('a', 1)]);

        expect(plan.droppedStarter, isNull);
      }
    });

    test('the starter stays when the import only replaces', () {
      final repository = fresh()..createProfile(avatar: AvatarId.dog);
      final plan = repository.planProfileImport([
        Profile(
          id: 'x',
          name: 'Other',
          avatar: AvatarId.cat,
          createdAt: repository.profiles[1].createdAt,
        ),
      ]);

      expect(plan.entries.single.replaces, isTrue);
      expect(plan.droppedStarter, isNull);
    });

    test('the starter stays when it is itself being replaced', () {
      final plan = fresh().planProfileImport([
        Profile(
          id: 'x',
          name: 'Same child',
          avatar: AvatarId.cat,
          createdAt: starterCreatedAt,
        ),
        incoming('y', 1),
      ]);

      expect(plan.droppedStarter, isNull);
    });
  });

  group('applying', () {
    test('replaces in place, appends in file order, drops the starter, and '
        'hands the active profile to the first imported', () {
      final repository = fresh();
      final plan = repository.planProfileImport([
        incoming('a', 1, name: 'Ana'),
        incoming('b', 2, name: 'Bo'),
      ]);

      repository.applyProfileImport(plan);

      expect(repository.profiles.map((p) => (p.id, p.name)), [
        ('p2', 'Ana'),
        ('p3', 'Bo'),
      ]);
      expect(repository.activeProfile.id, 'p2');
    });

    test('a replacement takes the file contents but keeps the local id and '
        'position', () {
      final repository = fresh()..createProfile(avatar: AvatarId.dog);
      final local = repository.profiles[1];
      final file = Profile(
        id: 'p5',
        name: 'Restored',
        avatar: AvatarId.panda,
        createdAt: local.createdAt,
        padSide: PadSide.left,
        snakeCounting: SnakeCounting.off,
        draw: const DrawProgress(drawingCount: 4, bytesUsed: 9),
      );

      repository.applyProfileImport(repository.planProfileImport([file]));

      expect(repository.profiles, hasLength(2));
      expect(
        repository.profiles[1],
        Profile(
          id: local.id,
          name: 'Restored',
          avatar: AvatarId.panda,
          createdAt: local.createdAt,
          padSide: PadSide.left,
          snakeCounting: SnakeCounting.off,
          draw: const DrawProgress(drawingCount: 4, bytesUsed: 9),
        ),
      );
      // Nothing was added, so the starter is still there and still active.
      expect(repository.profiles.first.id, 'p1');
    });

    test('the active profile is untouched when the dropped starter was not '
        'it', () {
      final repository = fresh()
        ..createProfile(name: 'Kai', avatar: AvatarId.dog);
      expect(repository.activeProfile.id, 'p2');

      repository.applyProfileImport(
        repository.planProfileImport([incoming('a', 1)]),
      );

      expect(repository.profiles.map((p) => p.id), ['p2', 'p3']);
      expect(repository.activeProfile.id, 'p2');
    });

    test('settings are replaced only when given', () {
      final repository = fresh();
      const imported = AppSettings(sound: false, theme: ThemeChoice.night);

      repository.applyProfileImport(
        repository.planProfileImport([incoming('a', 1)]),
      );
      expect(repository.settings, const AppSettings());

      repository.applyProfileImport(
        repository.planProfileImport([incoming('a', 1)]),
        settings: imported,
      );
      expect(repository.settings, imported);
    });

    test('is one mutation: one notification, one write', () async {
      final store = MemorySaveStore(
        initial: SaveData.initial(createdAt: starterCreatedAt),
      );
      final repository = ProgressRepository(
        store,
        initial: SaveData.initial(createdAt: starterCreatedAt),
      );
      addTearDown(repository.dispose);
      var notifications = 0;
      repository.addListener(() => notifications++);

      repository.applyProfileImport(
        repository.planProfileImport([incoming('a', 1), incoming('b', 2)]),
        settings: const AppSettings(sound: false),
      );
      await repository.flush();

      expect(notifications, 1);
      expect(store.writes, 1);
    });

    test('withDraw changes only that profile\'s counters in the plan', () {
      final repository = fresh();
      final plan = repository
          .planProfileImport([incoming('a', 1), incoming('b', 2)])
          .withDraw('p3', const DrawProgress(drawingCount: 2, bytesUsed: 50));

      repository.applyProfileImport(plan);

      expect(repository.profiles[0].draw, const DrawProgress());
      expect(
        repository.profiles[1].draw,
        const DrawProgress(drawingCount: 2, bytesUsed: 50),
      );
    });

    test('a plan made before a profile was added is stale: StateError, and '
        'nothing changes', () {
      final repository = fresh();
      final plan = repository.planProfileImport([incoming('a', 1)]);
      repository.createProfile(avatar: AvatarId.dog);
      final before = repository.data;

      expect(
        () => repository.applyProfileImport(plan),
        throwsA(isA<StateError>()),
      );
      expect(repository.data, before);
    });

    test('a plan made before the starter was touched is stale', () {
      final repository = fresh();
      final plan = repository.planProfileImport([incoming('a', 1)]);
      repository.setProfileAvatar('p1', AvatarId.owl);
      final before = repository.data;

      expect(
        () => repository.applyProfileImport(plan),
        throwsA(isA<StateError>()),
      );
      expect(repository.data, before);
    });

    test('a plan made before a profile was deleted is stale', () {
      final repository = fresh()..createProfile(avatar: AvatarId.dog);
      final plan = repository.planProfileImport([incoming('a', 1)]);
      repository.deleteProfile('p2');

      expect(
        () => repository.applyProfileImport(plan),
        throwsA(isA<StateError>()),
      );
    });
  });
}
