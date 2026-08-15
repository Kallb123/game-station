// The launch path: resolve where the save lives, read it, then start the app
// with both handed to the provider scope (PLAN-phase-1.md §4.4).
//
// Reading before `runApp` is what lets every screen read a synchronous
// `SaveData`. The file is a few kilobytes, which is well inside the two-second
// cold-start budget in PLAN.md §9.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/storage/providers.dart';
import 'core/storage/save_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await _openStore();
  final loaded = await store.load();

  runApp(
    ProviderScope(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(loaded),
      ],
      child: const ZiboGamesApp(),
    ),
  );
}

/// The store over the platform's application support directory, or an in-memory
/// one if that directory cannot be resolved.
///
/// `path_provider` throwing is the one failure here that a child cannot do
/// anything about — a Linux desktop with no writable data directory is the
/// case PLAN-phase-1.md §7 names — and an app that will not start is worse than
/// one that forgets (`AGENTS.md`). The fallback runs the whole app normally and
/// loses progress on exit; the store is the only thing that differs.
Future<SaveStore> _openStore() async {
  try {
    return FileSaveStore(await getApplicationSupportDirectory());
  } on Exception catch (error) {
    debugPrint('Zibo Games: no save directory, running without one: $error');
    return MemorySaveStore();
  }
}
