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

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'drawing_repository.dart';
import 'gallery_export.dart';

/// Where every screen reads and writes drawings.
final Provider<DrawingRepository> drawingRepositoryProvider =
    Provider<DrawingRepository>(
      (ref) => throw UnimplementedError(
        'drawingRepositoryProvider has no value: override it in the '
        'ProviderScope, as main() and the test harness do.',
      ),
    );

/// Where an exported drawing goes: the photo library on Android and iOS, a
/// Downloads folder everywhere else (`PLAN-phase-8.md` §3.2, §4.6). Picked by
/// [defaultTargetPlatform] rather than `dart:io`'s `Platform`, the same
/// reason `core/haptics.dart`'s `deviceCanVibrate` does — a test can override
/// the platform and the answer is right on a web build, which `dart:io`
/// cannot even be imported for.
final Provider<GalleryExport> galleryExportProvider = Provider<GalleryExport>(
  (ref) => switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => const GalGalleryExport(),
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => const FolderGalleryExport(),
  },
);
