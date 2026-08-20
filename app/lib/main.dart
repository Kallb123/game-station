// The launch path: resolve where the save lives, read it, then start the app
// with both handed to the provider scope (PLAN-phase-1.md §4.4).
//
// Reading before `runApp` is what lets every screen read a synchronous
// `SaveData`. The file is a few kilobytes, which is well inside the two-second
// cold-start budget in PLAN.md §9.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/storage/providers.dart';
import 'core/storage/save_store.dart';
import 'features/draw/data/drawing_repository.dart';
import 'features/draw/data/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final directory = await _resolveDirectory();
  final store = directory == null
      ? MemorySaveStore()
      : FileSaveStore(directory);
  final loaded = await store.load();

  runApp(
    ProviderScope(
      overrides: [
        saveStoreProvider.overrideWithValue(store),
        initialSaveProvider.overrideWithValue(loaded),
        // A drawing needs a real directory even when `save.json` does not —
        // `DrawingRepository` is `dart:io`-only, unlike `SaveStore`, which
        // has a [MemorySaveStore] to fall back to. `Directory.systemTemp` in
        // the failure case matches [store]'s own fallback: the app still
        // starts (`AGENTS.md`), and persistence is what is lost.
        drawingRepositoryProvider.overrideWithValue(
          DrawingRepository(directory ?? Directory.systemTemp),
        ),
      ],
      child: const ZiboGamesApp(),
    ),
  );
}

/// The platform's application support directory, or null if it cannot be
/// resolved.
///
/// `path_provider` throwing is the one failure here that a child cannot do
/// anything about — a Linux desktop with no writable data directory is the
/// case PLAN-phase-1.md §7 names — and an app that will not start is worse than
/// one that forgets (`AGENTS.md`).
Future<Directory?> _resolveDirectory() async {
  try {
    return await getApplicationSupportDirectory();
  } on Exception catch (error) {
    debugPrint('Zibo Games: no save directory, running without one: $error');
    return null;
  }
}
