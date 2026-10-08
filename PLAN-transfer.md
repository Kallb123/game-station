# Moving players between devices

[`PLAN.md`](PLAN.md) §5.3 has always promised it: "Export and import the save as a file — the share
sheet on mobile, a file picker on desktop. That is how a family moves to a new tablet without an
account or a server." This plan is that feature: a parent writes one player, or every player, to a
file, carries it to another device by whatever means they already have, and loads it there. Where
this file and `PLAN.md` disagree, the reason is stated here and `PLAN.md` is updated in the same
change.

## 1. Scope and constraints

- **One player or all of them.** Siblings move tablets together; one child moves to a new phone
  alone. Both are one file of the same format, differing in how many profiles it holds.
- **Everything a profile owns travels with it.** Name, avatar, `createdAt`, every option on the
  profile (`mistakeFeedback`, `arcadeEasyMode`, `arcadeAutoFire`, `padSide`, `snakeCounting`), all of
  `sudoku` (solved, in progress, streak, best times), all of `arcade` (high scores, games played,
  kills, best length), `draw`'s counters, and the drawings themselves. A file without the drawings
  would carry a `drawingCount` and `bytesUsed` describing pictures that are not there.
- **Device settings travel too, and are applied only when asked.** `settings` is in every file.
  Importing *everyone* applies it by default — that is a whole tablet moving. Importing *some*
  defaults to leaving this device's settings alone, because one child moving onto a sibling's tablet
  does not get to change its parental controls (`allowPhotoImport`).
- **No network, no new dependency.** `file_selector` resolves `http` into the shipped graph
  (`app/pubspec.yaml`, `PLAN-phase-8.md` §3), and every other picker package is a graph to audit for
  what two Storage Access Framework intents and a folder already do. The platform edge is an in-repo
  method channel and the folder `FolderGalleryExport` already writes to.
- **A bad file is refused in words, never a crash.** A file from a newer build, a file that is not a
  players file, or a truncated one is answered with one sentence and nothing on the device changes
  (`AGENTS.md`: never surface an internal error).
- **The engine stays pure** and `core/storage`'s codec stays free of Flutter and `dart:io`.

## 2. Non-goals

- Sync, merge or conflict resolution. A file is a snapshot; loading it replaces or adds, it never
  combines two histories of one child.
- The puzzle cache. It is regenerable by definition (`PLAN.md` §5.2), and leaving it out keeps the
  file a function of the profiles alone. An in-progress puzzle regenerates on resume.
- Encryption or a password. Nothing in a profile is worth locking (`PLAN.md` §5.1).
- An iOS document picker. iOS gets the Files-app folder instead (§3.3); a native picker can follow
  without changing the format.

## 3. Approach

### 3.1 The file

One JSON document, extension `.zibo.json`:

```json
{
  "format": "zibo-games-players",
  "formatVersion": 1,
  "exportedAt": "2026-10-08T09:00:00.000Z",
  "everyone": true,
  "save": { "schemaVersion": 1, "generatorVersion": 1, "activeProfileId": "p1",
            "settings": { … }, "profiles": [ … ], "puzzleCache": {} },
  "drawings": { "p1": { "d1": { …drawing JSON… }, "d2": { … } } }
}
```

`save` is exactly what `encodeSave` writes, restricted to the exported profiles and with an empty
cache. Reusing the save codec rather than writing a second one is the decision that makes "all stats"
true by construction: a field added to `Profile` and to the save codec is in the transfer file with no
further change, and a migration step added to `save_codec.dart` migrates an old transfer file too.
Rejected: a bespoke per-field format, which would be a second codec to keep in step with the first
and would silently drop the next field someone forgets to add to it.

`drawings` is keyed by the profile ids *inside the file*, then by drawing id, and holds each drawing
as a parsed JSON object rather than as an escaped string — nesting costs nothing, escaping a 64 MB
budget's worth of quotes costs a fifth again. The transfer codec treats each drawing as opaque; the
import step decodes it with `decodeDrawing` and skips one that fails, the same rule the gallery
applies (`PLAN-phase-8.md` §4.5).

A file whose `save.generatorVersion` differs from the engine's is refused: its in-progress puzzle ids
would resolve to different boards. A `formatVersion` or `schemaVersion` above this build's is refused
as newer, matching `UnsupportedSaveVersion`.

### 3.2 Import rules

- **Identity is `createdAt`.** Profile ids are per-device counters, so `p2` here and `p2` there are
  unrelated. `createdAt` is a UTC instant to the microsecond, written once and never changed, so an
  incoming profile whose `createdAt` equals a local one's *is* that child — loading a file back onto
  the device it came from restores rather than duplicates. A match **replaces** the local profile's
  contents and keeps its local id; the import screen says which local player each match replaces
  before anything is written. Rejected: matching on name, which a child changes and two devices'
  "Player 1"s share.
- **Anything unmatched is added** under the next free `p<n>`, exactly as `createProfile` numbers.
- **An untouched starter profile is dropped.** A fresh install holds one `Player 1` with nothing
  played; importing a family onto it should not leave that ghost at the top of the list. A profile is
  untouched when it equals a fresh `Profile` in everything but `createdAt` (default name `Player n`,
  fox avatar, every option at its default, no progress). It is removed only when the import adds at
  least one profile, so the save never empties, and the active profile then becomes the first
  imported one.
- **Drawings land before the save changes.** For each imported profile the target
  `drawings/<localId>/` folder is emptied and the file's drawings written into it, then `bytesUsed`
  is recomputed from disk and `lastDrawingId` cleared if it named a drawing that did not decode. Only
  then is the save mutated, in one `_apply`, and flushed. A failure part-way leaves a folder the save
  does not yet point at, never a save pointing at missing pictures. Emptying the folder first also
  clears orphans: `deleteProfile` leaves a profile's drawings on disk, and a new `p<n>` can reuse a
  deleted one's id.

### 3.3 The platform edge

`TransferFiles` has two shapes, picked per platform the way `galleryExportProvider` picks:

| Platform | Export | Import |
|---|---|---|
| Android | `ACTION_CREATE_DOCUMENT` through a `zibo/transfer` channel (`TransferPlugin.kt`) — the system's own save dialog, which reaches Downloads, an SD card or any document provider the parent has installed | `ACTION_OPEN_DOCUMENT`, same channel |
| iOS | The app's Documents folder, made visible in the Files app by `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` | A list of `.zibo.json` files in that folder |
| Windows, macOS, Linux | `<Downloads>/Zibo Games/`, the folder drawings already export to (macOS already holds the Downloads entitlement) | A list of `.zibo.json` files in that folder |

Neither Storage Access Framework action takes a permission, so the APK's "requests no permission"
release check (`PLAN.md` §9) still holds. The channel's launchers are registered from
`MainActivity.configureFlutterEngine`, before `STARTED`, for the reason `PhotoPickerPlugin.kt`
records. Rejected: a share sheet on Android, which needs a `FileProvider` and lets a child send the
file to any app on the device; the save dialog puts it somewhere a parent chose.

### 3.4 The screen

A **Move players** row at the bottom of Settings — the parent's screen, not the child's player
picker — opens `/transfer`, with two halves:

- **Save to a file:** one big button per player and one for *Everyone*. A tap writes the file and
  says where it went in one line.
- **Load from a file:** on Android, opens the system picker; elsewhere, lists the files in the folder
  newest first. A readable file opens a confirmation listing each player in it with their avatar, a
  checkbox (all ticked), and "replaces <local name>" under a match; a *Copy settings too* switch
  defaulted per §1; and a *Load* button. A refused file shows its one sentence instead.

## 4. Layout

```
app/lib/features/transfer/
  data/transfer_codec.dart    pure Dart: TransferBundle <-> JSON, over save_codec
  data/transfer_files.dart    the platform edge: channel and folder implementations
  data/transfer_service.dart  builds a bundle from the repositories; applies one
  data/providers.dart
  ui/transfer_screen.dart
app/android/app/src/main/kotlin/net/nawt/zibo_games/TransferPlugin.kt
```

`core/storage/save_codec.dart` gains `saveToJson`/`saveFromJson` over the decoded map, so the transfer
codec nests a save without encoding it to text and parsing it back. `ProgressRepository` gains
`importProfiles`, the one mutation §3.2 describes. `DrawingRepository` gains `deleteAllFor` and a raw
read of every drawing's JSON for export.

## 5. Phases

One pull request, built in three parts.

1. **Data.** Codec, service, repository additions, and their tests.
   **Done when:** a bundle of two profiles with drawings round-trips through text to equal values; an
   import onto a fresh save drops the starter profile, adds both, and writes their drawings; an
   import of a profile with a matching `createdAt` replaces it under its local id; a newer
   `formatVersion`, a different `generatorVersion` and a non-players file each throw a typed
   exception and leave the repository unchanged.
2. **Platform.** `TransferFiles`, `TransferPlugin.kt`, the iOS keys.
   **Done when:** the channel implementation's tests pass against a mocked channel, including a
   dismissed dialog returning null; the folder implementation lists only `.zibo.json`, newest first,
   against a temp directory; the Android build compiles.
3. **Screen.** Route, Settings row, transfer screen.
   **Done when:** a widget test exports everyone through a fake `TransferFiles`, loads the written text
   back into a second app instance, and finds every player and their high scores there; the layout
   sweep covers the new route at 200% text scale.

## 6. Risks

| Risk | Mitigation |
|---|---|
| A field added to `Profile` later is missing from transfers | The file *is* the save codec's output (§3.1); `transfer_codec_test.dart` round-trips a profile with every field off its default, so a field the save codec drops fails there too |
| A large drawings folder exhausts memory on a cheap tablet | A profile is capped at 64 MB of drawings (`PLAN-phase-8.md` §4.5), so a family of four is at worst a few hundred MB held briefly. Accepted for now; streaming the file is the fix if a device pass shows it |
| A parent loads the same file twice and gets duplicates | Matching on `createdAt` makes the second load a replace; covered by a repository test |
| Import half-applies | Drawings first, save in one mutation (§3.2); a test fails the drawing write and asserts the save is unchanged |
| The channel is broken on a device and nobody notices | Like `zibo/photos`, CI cannot run it; the device pass in §7 is the check, and the PR says which device it ran on |

## 7. Verification checklist

- [ ] `tool/verify.sh` passes.
- [ ] On Android: export everyone to Downloads, uninstall, reinstall, load the file, and find every
      player, score, streak and drawing.
- [ ] On a desktop target: the same through `<Downloads>/Zibo Games/`.
- [ ] On iOS: the exported file is visible in the Files app under *On My iPhone › Zibo Games*.
- [ ] The release APK still requests no permission (`tool/check_apk_permissions.sh`).
