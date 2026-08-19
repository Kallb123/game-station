// The write-a-temp-file-then-rename pattern every file this app writes uses
// (`PLAN.md` §2, §5.3): `save.json` in `save_store.dart`, and a drawing's
// `<id>.json` in `features/draw/data/drawing_repository.dart`
// (`PLAN-phase-8.md` §4.5). One helper rather than two copies, so the rule —
// flush before rename, rename over whatever was there — is enforced in one
// place for every file that needs it.
//
// Rename is atomic on every platform this app ships to, so a crash or a flat
// battery mid-write leaves either the old file or the new one, never half of
// either.

import 'dart:io';

/// Writes [contents] to [target] by way of a `.tmp` sibling: open, write,
/// flush, close, then rename over [target].
///
/// Flushed before the rename, not after: renaming a file whose contents are
/// still in a buffer would publish an empty or truncated file if the power
/// went at the wrong moment.
Future<void> writeFileAtomically(File target, String contents) async {
  final temp = File('${target.path}.tmp');
  final handle = await temp.open(mode: FileMode.writeOnly);
  try {
    await handle.writeString(contents);
    await handle.flush();
  } finally {
    await handle.close();
  }
  await temp.rename(target.path);
}
