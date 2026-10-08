// The Riverpod wiring over `features/transfer/data`.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/providers.dart';
import '../../draw/data/providers.dart';
import 'transfer_files.dart';
import 'transfer_service.dart';

/// Where a players file is written and loaded from (`PLAN-transfer.md` §3.3):
/// the system dialogs on Android, the Documents folder on iOS and
/// `<Downloads>/Zibo Games` everywhere else. Picked by [defaultTargetPlatform]
/// for the reason `galleryExportProvider` is: a test can override the platform.
final Provider<TransferFiles> transferFilesProvider = Provider<TransferFiles>(
  (ref) => switch (defaultTargetPlatform) {
    TargetPlatform.android => const ChannelTransferFiles(),
    TargetPlatform.iOS => const FolderTransferFiles(documentsTransferFolder),
    TargetPlatform.fuchsia ||
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => const FolderTransferFiles(desktopTransferFolder),
  },
);

/// Builds and applies players files over the live repositories.
///
/// Watches the progress repository's `.notifier` rather than the repository
/// itself, for the reason `puzzleSourceProvider` does: the value of a
/// [ChangeNotifierProvider] changes on every save, and a service rebuilt in the
/// middle of an import would be a second service half-way through the first
/// one's work. The notifier is the same object for the life of the scope.
final Provider<TransferService> transferServiceProvider =
    Provider<TransferService>(
      (ref) => TransferService(
        progress: ref.watch(progressRepositoryProvider.notifier),
        drawings: ref.watch(drawingRepositoryProvider),
      ),
    );
