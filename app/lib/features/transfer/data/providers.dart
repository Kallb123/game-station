// The Riverpod wiring over `features/transfer/data`.

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show TargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'transfer_files.dart';

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
