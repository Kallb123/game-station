// The Riverpod wiring over `features/draw/data`.
//
// Same shape as `core/storage/providers.dart`'s `saveStoreProvider`: no
// default, so `main` overrides it with a [DrawingRepository] over the
// directory `path_provider` resolved for `save.json`, and a widget test
// overrides it with one over a temp directory. It is not derived from a
// shared "save directory" provider in `core/storage` — that file is the one
// place `PLAN-phase-1.md` §5 keeps free of `dart:io` outside `save_store.dart`
// and `atomic_write.dart` (`save_store_test.dart`'s own layer-boundary test),
// and this repository is the only thing that would ever read such a
// provider.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drawing_repository.dart';

/// Where every screen reads and writes drawings.
final Provider<DrawingRepository> drawingRepositoryProvider =
    Provider<DrawingRepository>(
      (ref) => throw UnimplementedError(
        'drawingRepositoryProvider has no value: override it in the '
        'ProviderScope, as main() and the test harness do.',
      ),
    );
