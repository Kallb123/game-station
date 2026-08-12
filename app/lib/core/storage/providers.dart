// The Riverpod wiring over `core/storage`.
//
// The save is read once, before `runApp`, and handed to the scope as an
// override (PLAN-phase-1.md §4.4). Everything above therefore reads a
// synchronous [SaveData]: no screen carries a loading branch for a state that
// exists for the first few milliseconds of a launch and never again.
//
// The selectors below exist so that a settings toggle does not rebuild the
// profile list. Each derives one value from the repository, and Riverpod only
// notifies a derived provider's listeners when that value actually changes —
// which works because everything in `save_data.dart` compares by value.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'progress_repository.dart';
import 'save_data.dart';
import 'save_store.dart';

/// Where the save is read from and written to.
///
/// Has no default: `main` overrides it with a [FileSaveStore] over the
/// directory `path_provider` resolved, and a widget test overrides it with a
/// [MemorySaveStore]. A default would be a filesystem dependency that a test
/// silently picks up when its override is missing.
final Provider<SaveStore> saveStoreProvider = Provider<SaveStore>(
  (ref) => throw UnimplementedError(_missingOverride('saveStoreProvider')),
);

/// What [SaveStore.load] returned at launch.
///
/// Overridden alongside [saveStoreProvider], from the same load: the two
/// describe one launch, so a scope that overrode only one of them would run the
/// app against a save it never read.
final Provider<SaveLoad> initialSaveProvider = Provider<SaveLoad>(
  (ref) => throw UnimplementedError(_missingOverride('initialSaveProvider')),
);

/// The repository every screen reads and writes through.
///
/// [ChangeNotifierProvider] disposes the repository with the scope, which is
/// what starts any write still sitting in the debounce window
/// (`progress_repository.dart`).
final ChangeNotifierProvider<ProgressRepository> progressRepositoryProvider =
    ChangeNotifierProvider<ProgressRepository>(
      (ref) => ProgressRepository.fromLoad(
        ref.watch(saveStoreProvider),
        ref.watch(initialSaveProvider),
      ),
    );

/// The device-wide settings.
final Provider<AppSettings> settingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(progressRepositoryProvider).settings,
);

/// The profile the app is showing.
final Provider<Profile> activeProfileProvider = Provider<Profile>(
  (ref) => ref.watch(progressRepositoryProvider).activeProfile,
);

/// Whether the "we started fresh" notice is still to be shown.
///
/// It is state rather than a plain read of [SaveLoad.recovery] because it is
/// dismissible, and it lives here rather than in the home screen's state so
/// that rebuilding or re-entering that screen cannot show it a second time.
/// Nothing persists it: the next launch reads a valid save, so the notice
/// cannot come back on its own.
final NotifierProvider<SaveNotice, bool> saveNoticeProvider =
    NotifierProvider<SaveNotice, bool>(SaveNotice.new);

/// Holds [saveNoticeProvider].
class SaveNotice extends Notifier<bool> {
  @override
  bool build() => ref.watch(initialSaveProvider).lostProgress;

  /// Hides the notice for the rest of this launch.
  void dismiss() => state = false;
}

String _missingOverride(String name) =>
    '$name has no value: override it in the ProviderScope, as main() and the '
    'test harness do.';
