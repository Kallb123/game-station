# Phase 8 — the drawing board

**PR 6 of 7 landed for Android; PR 7 is not started.** [`PLAN.md`](PLAN.md) is the source of truth for scope and phase order; §7 there
carries this phase's entry and its done-criterion, and §2, §5.2, §5.3, §6 and §8 carry the parts of
this design that the rest of the app has to agree with. Written ahead of its turn for the reason
`PLAN.md` §10 gives: the choice of photo-library dependency is settled by resolving a graph, and the
answer changes the phase's shape.

The plan for `app/lib/features/draw`: a sheet a child draws on with a finger, four pencil sizes,
twelve colours, an eraser, undo and redo, and a round trip to the device photo library. Where this
file and `PLAN.md` disagree, the reason is stated here and the closing pull request updates `PLAN.md`.

The phase's real difficulty is not the canvas. It is that "save and load from the gallery" is five
different platform stories, one of which — reading the library — has no dependency this project is
allowed to take. §3 is mostly about that.

**Contents:**
[1 Scope and constraints](#1-scope-and-constraints) ·
[2 Non-goals](#2-non-goals) ·
[3 Approach](#3-approach) ·
[4 Design](#4-design) ·
[5 Repository layout](#5-repository-layout) ·
[**6 Pull requests →**](#6-pull-requests) ·
[7 Risks](#7-risks) ·
[8 Verification checklist](#8-verification-checklist) ·
[9 Open questions](#9-open-questions) ·
[10 Starting order](#10-starting-order)

---

## 1. Scope and constraints

| Constraint | Rationale and mechanism |
|---|---|
| Exactly one new dependency, and it drags in nothing | `PLAN.md` §2. Resolved before this plan was written: `gal 2.3.3` depends on `flutter` alone, so it adds itself to the graph and no transitive package. `image_picker 1.2.3` and `file_selector 1.1.0` were the obvious choices and both resolve `http 1.6.0` into what ships, through `image_picker_platform_interface` and `file_selector_platform_interface`; `tool/check_offline.dart` reads the resolved graph and fails on `http`, and narrowing that check to admit a picker is the one thing `AGENTS.md` says never to do. §3.2 has the table |
| No permission to read the photo library | A children's app that asks for the family album is a listing liability and a privacy posture worth avoiding. Android's `ActivityResultContracts.PickVisualMedia` and iOS's `PHPickerViewController` both return one image with the app holding no library permission, which is why §3.3 writes the channel rather than taking `photo_manager` — clean graph, whole album |
| Import is off until a parent turns it on | `settings.allowPhotoImport`, default false (`PLAN.md` §5.2). Device-wide rather than per profile because a control that gates a child cannot live where the child can set it. Export stays available either way: writing a drawing out reveals nothing |
| A phone and a tablet draw the same picture | A fixed 1600 x 1200 virtual sheet, scaled to the widget — the same rule as `PLAN.md` §4.1's 224 x 256 field. A stroke is stored in sheet coordinates, so a drawing started on a phone opens undistorted on a tablet and exports at the same size from both |
| Undo and redo cannot cost a frame | Strokes are data (§4.1). Undo moves the last `Stroke` to the redo stack; nothing is re-rasterised. A snapshot-per-move canvas would be megabytes per undo step, which is what `PLAN.md` §3.7 already capped the Sudoku undo stack to avoid in the save |
| A 500-stroke drawing paints inside one 60 Hz frame | Strokes below the 50-stroke undo horizon are baked into a cached `ui.Image` (§4.3), so the painter walks at most 51 strokes plus the live one however long a child draws. Asserted by a test counting the strokes the painter touches, not by watching a device — a bound nobody measures is a bound that drifts |
| No control signals its state by colour alone | `PLAN.md` §7's phase-5 accessibility rule, arriving here already met rather than retrofitted. Selection is a 3 dp `AppBorders.selected` ring plus a size change, never a colour change. The palette itself is the exception that proves the rule: a paint box's swatches *are* colour, and no arrangement of twelve of them is safe under every deficiency — so each carries a spoken name, and a widget test asserts every swatch has a `Semantics` label. Choosing a colour is the one place in the app where a child needs to see one |
| Tap targets: 56 dp for every tool, 72 dp for undo and redo | `AppTapTargets.min` and `.primary` (`core/ui/tokens.dart`). Undo and redo get the primary size for the reason FIRE did in phase 4 — they are tapped repeatedly and in a hurry. Asserted per control in a widget test, as phase 3's keypad and phase 4's pad are |
| Nothing a child made is lost by a mis-tap | There is no clear button. **New sheet** files the current drawing in the in-app gallery and opens a blank one, so the destructive action does not exist rather than being guarded by a dialog a six-year-old will tap through |
| No ambient randomness in `lib/` | `PLAN-phase-1.md` §1, enforced by `app/test/no_random_test.dart`. Drawing ids are `"d1"`, `"d2"`, … from a counter, like profile ids. Nothing here needs a random number, and the existing scanner already fails the build if someone reaches for one |
| The save file stays a few kilobytes | `PLAN.md` §5.2. Drawings are files under `drawings/<profileId>/`; `save.json` keeps three numbers. A test asserts an encoded save with 60 drawings recorded is still under 8 KB |
| Disk use is bounded and the child is told, not surprised | 64 MB per profile, checked against `save.json`'s `bytesUsed` at write time (§4.5). Over budget, the gallery says the drawer is full and offers a deletion. Nothing is silently evicted: a picture deleted without being asked about is indistinguishable from a bug |
| `tool/verify.sh` green before every commit | It is what CI runs, in the same order (`AGENTS.md`). Measured at this phase's planning: 481 tests in 50 s. The model, codec and controller tests here are plain `test()` calls with no widget tree, so the phase budgets **under 70 s** |

---

## 2. Non-goals

Each of these was considered and dropped, because a drawing app is where scope goes to die.

| Not doing | Why |
|---|---|
| Layers | A child cannot see a layer. It doubles the data model and every undo case for something whose whole value is invisible on a 6" screen |
| A fill bucket | It is the most-asked-for tool and the one that breaks §4.1: a flood fill's result is pixels, not a stroke, so it cannot be undone by dropping a stroke and cannot be baked below the horizon. Revisit only with a design that keeps fills as data — a fill of a closed region as a path, not as pixels |
| Shapes, stamps and stickers | Each is an asset file with a licence line (`PLAN.md` §6) and a picker UI. The pencil is the phase; a stamp sheet is a later minor release if children ask for one |
| Text on the drawing | A keyboard on a drawing screen for an audience that mostly cannot spell |
| Zoom and pan | It competes with the drawing gesture for the same fingers, and a child who zooms cannot get back. The sheet is exactly the screen |
| Stylus pressure, tilt and palm rejection | Pressure needs a stroke model with per-point width, which is a wider `Stroke` for every user to serve the few on a tablet with a pen. `PointerEvent.pressure` is recorded nowhere; a size is chosen from the row |
| Editing an imported photo's pixels | The backdrop is locked. Crop, rotate and filter are a photo editor, and a photo editor is a different app |
| Sharing to another app, or printing | `PLAN.md` §1's no-network constraint does not forbid a share sheet, but a share sheet is how a child's drawing leaves the device, and "nothing leaves the device" is the promise the project is built on. The photo library is the handover point; what a parent does from there is the parent's |
| Animation, GIF, video | `gal` can save video. Nothing here produces one |
| A colour wheel or eyedropper | A continuous picker is a poor control for a small hand and cannot be given a spoken name. Twelve named swatches can |
| Unbounded undo | §4.3's horizon is 50. An undo stack that reaches the first stroke of the afternoon holds every point of it in memory |
| Drawings in the save file, or synced anywhere | `PLAN.md` §5.2 and §5.3. No cloud, by design, and a picture is not a few kilobytes |

---

## 3. Approach

### 3.1 Flutter widgets and `CustomPainter`, not Flame

Flame is already a dependency, and it is the wrong tool here. `PLAN.md` §2 chose Flutter's widget
layer for the Sudoku grid because that screen is layout and input rather than rendering, and a drawing
board is the same shape of problem: it has no simulation, no clock and nothing that moves when the
child's finger is still. A `FlameGame` would run a game loop and a `render` pass every frame over a
picture that changes only on a pointer event.

| Alternative | Rejected because |
|---|---|
| A `FlameGame` with a component per stroke | A per-frame loop for a static image, plus `ordered_set` bookkeeping for components nothing sorts. The bake in §4.3 has no equivalent |
| `Canvas.drawPoints` per pointer sample | Renders as visible dots at the two larger pencil sizes. §4.2's path smoothing exists for this |
| A `ui.Scene` built by hand through `SceneBuilder` | Bypasses the widget layer's hit testing and safe areas, which §1's tap-target and inset rules are enforced through everywhere else in the app |
| A raster canvas — draw into a `ui.Image`, keep no strokes | The load-bearing decision, taken the other way. It makes undo a stack of full-canvas snapshots, ties the export resolution to the screen's, and makes the save format a bitmap. §4.1 |

### 3.2 Writing to the photo library: `gal`

Resolved against this repository's SDK — Flutter 3.44.9, Dart 3.12.2 — before this plan was written,
because the resolution is the decision:

| Candidate | Adds to the resolved graph | Verdict |
|---|---|---|
| `gal 2.3.3` | itself only (`flutter`) | **Chosen.** Android SDK 21+, iOS 11+, and also macOS 11+ and Windows 10+, which §4.6 does not use: on desktop the photo app indexes a folder, so a plain file write is one code path instead of a plugin on three targets nobody here has run. `Gal.putImageBytes(bytes, name:)` is exactly the call site §4.6 needs, and it handles the Android `MediaStore` split and the iOS add-only permission prompt |
| `image_picker 1.2.3` | `http 1.6.0`, `cross_file`, `mime`, `web`, `flutter_web_plugins`, `flutter_plugin_android_lifecycle`, six platform packages | **Rejected.** `http` ships, so `tool/check_offline.dart` fails the build. It is a runtime dependency, not test-only, so the "present but test-only" note the check already prints for `sync_http` does not apply |
| `file_selector 1.1.0` | `http 1.6.0` via `file_selector_platform_interface`, plus seven platform packages | **Rejected**, same reason |
| `saver_gallery 5.1.0` | `path`, `mime`, `path_provider`, `uuid` | Rejected. Clean of `http`, but four packages instead of none, and `uuid` is a random-id generator in a repository whose scanner forbids ambient randomness |
| Writing `MediaStore` and `PHPhotoLibrary` in-repo | nothing | Rejected **for the write direction only**: `gal` is eighty lines of Kotlin and Swift this phase does not have to write, review or test on two platforms, for zero graph cost. §3.3 does write the read direction, because there nothing is available at that price |

`gal`'s own `AndroidManifest.xml` declares no permissions — the `INTERNET` line in its repository is
in its *example* app, not in the plugin — so the app's manifest stays the only place a permission can
come from, and `tool/check_offline.dart`'s manifest audit keeps watching the same file it does today.
The app adds one line for Android 8 and 9, where a `MediaStore` write still needs it:

```xml
<uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"
                 android:maxSdkVersion="28" />
```

`maxSdkVersion` matters for the listing as well as for correctness: on Android 10 and up the
permission is not requested at all, so the store page shows storage access only to the devices that
actually need it. **28, not the 29 `gal`'s own example declares** — from API 29 a `MediaStore` insert
into `Pictures` needs no permission, and 29 is in that example because saving to a *named album* there
does. This app saves to no album, so 28 is the tighter and correct bound; PR 5 reads the merged
manifest out of the built artifact rather than trusting that reasoning.

Saving with no album. `gal` can create a named album, which on API 29 needs
`android:requestLegacyExternalStorage="true"` in the manifest — a whole-app storage behaviour change
to get a folder name. The drawing lands in the camera roll instead.

### 3.3 Reading the photo library: an in-repo method channel

Nothing on pub gives a photo-library picker with a graph this project can accept. The two directions
are therefore not symmetrical, which is worth saying plainly because it looks like an inconsistency.

| Alternative | Rejected because |
|---|---|
| `image_picker` | `http` in the shipped graph (§3.2). This is the package the feature would otherwise be one line of |
| `photo_manager 3.12.0` | Graph is clean (`flutter`, `path`). It enumerates the library, so it needs `READ_MEDIA_IMAGES` on Android 13+ and `NSPhotoLibraryUsageDescription` on iOS, and the app would then build its own grid over the family album. Both the permission and the grid are worse than the system picker |
| `flutter_file_dialog 3.3.2` | Graph is clean (`flutter`). On Android its `ACTION_OPEN_DOCUMENT` can reach photos through the Documents UI; on iOS `UIDocumentPickerViewController` cannot see the Photos library at all. A feature that works on one of the two mobile targets is not the feature |
| Receiving a share intent from the Photos app instead of picking | Inverts the flow — the child starts in Photos, not in the drawing app — and still needs native code, plus an intent filter and a cold-start path to test |

**Chosen:** one `MethodChannel('zibo/photos')` with a single `pick()` call returning `Uint8List?`.

- **Android**, Kotlin, ~40 lines: `ActivityResultContracts.PickVisualMedia` with
  `PickVisualMediaRequest(ImageOnly)`. It uses the system photo picker where one exists and falls back
  to `ACTION_OPEN_DOCUMENT` on older devices by itself, which is what makes API 26 work without a
  permission or a version branch of ours.
- **iOS**, Swift, ~60 lines: `PHPickerViewController` with `filter: .images` and `selectionLimit: 1`,
  loading the item through `NSItemProvider`. No `NSPhotoLibraryUsageDescription`, because a picker
  result is not library access.
- **Windows, macOS, Linux:** no channel implementation. `pick()` returns `null` and the platform
  reports itself unavailable, and the import list reads the export folder instead (§4.6). A desktop
  photo library is not a thing the three of them agree on, and a file dialog would need
  `file_selector`.

`PHPickerViewController` is iOS 14. `PLAN.md` §1 says iOS 13+, so on 13 the import control is absent
rather than broken — §9 carries whether that floor should just move.

### 3.4 The load-bearing decision

**Strokes are data, not pixels** (§4.1). Undo, redo, the autosave format, the bake, the resolution of
the export and the size of a saved file all follow from it. If it were reversed, the save format
becomes a bitmap, undo becomes snapshot-based and bounded by memory rather than by a count, the export
resolution becomes the screen's, and §4.3's horizon has nothing to bake. Nothing else in the phase is
close to as expensive to change later.

---

## 4. Design

### 4.1 The stroke model

`features/draw/model/`: `dart:ui` for `Offset` and `package:flutter/foundation.dart` for the
controller's `ChangeNotifier`, and no widget, so the tests are `test()` calls without a
`WidgetTester`. `SudokuSession` (`features/sudoku/model/`) is the same shape over the same base class,
and `ChangeNotifierProvider` is how the app already reaches one.

```dart
/// Sheet coordinates: 0..1599 x 0..1199, independent of the screen (§1).
const Size sheetSize = Size(1600, 1200);

@immutable
class Stroke {
  final int colorIndex;      // index into DrawPalette.colors; -1 when erasing
  final int sizeIndex;       // index into DrawPencils.widths
  final List<Offset> points; // sheet coordinates, first point included
}

@immutable
class Drawing {
  final String id;           // "d1", "d2", … — a counter (PLAN-phase-1.md §1)
  final DateTime createdAt;  // UTC
  final List<Stroke> strokes;
  final Uint8List? backdrop; // an imported photo, downscaled to sheetSize, PNG
}
```

`colorIndex` and `sizeIndex`, not an `int` colour and a `double` width: the palette and the four sizes
are a closed set, and storing the index means a later change to a swatch's exact value redraws old
drawings in the new colour instead of freezing twelve constants into every file a child has saved.
The trade is deliberate and the opposite of `PLAN.md` §3.1's frozen-forever rule for puzzles — a
drawing that shifts one shade of blue is not a drawing that has been lost, whereas a puzzle that
changes is a solved puzzle that comes back unsolved.

Points are `Offset`s rather than 16-bit integers. A stroke's points are already sampled at 2 sheet
units (§4.2) so the count is bounded, and the codec rounds to one decimal place on the way out, which
costs about 12 bytes a point in JSON.

### 4.2 Sampling and smoothing

A raw `PointerMove` stream on a 120 Hz screen is far denser than a drawing needs, and a polyline
through it renders as visible corners at the larger pencil sizes.

- **Sampling:** a point is appended only if it is more than 2 sheet units from the previous one. A
  60-unit-long stroke is then at most 30 points regardless of how slowly the finger moved, which is
  what bounds a file rather than a cap on the count.
- **Smoothing:** the stroke is drawn as a `Path` of quadratic segments — control point at each sample,
  end point at the midpoint of that sample and the next — so the curve passes through the midpoints
  and never corners at a sample. A single-point stroke (a tap) draws a filled circle of the pencil's
  width, because a child tapping to make a dot must get a dot.
- **Paint:** `StrokeCap.round`, `StrokeJoin.round`, `isAntiAlias: true`. Erase is the same path with
  `BlendMode.clear` into the strokes layer, which is why §4.3 keeps the sheet's paper colour *under*
  that layer rather than as its first stroke — an erase that punched through the paper would show the
  screen behind it.

### 4.3 Painting, and the bake

`DrawingPainter extends CustomPainter`, inside a `RepaintBoundary`, and it walks three things:

1. `baked` — a `ui.Image` of every stroke below the undo horizon, drawn in one `drawImageRect`.
2. `strokes` — at most 50 live strokes, drawn as paths.
3. `live` — the stroke under the finger, rebuilt each pointer event.

`shouldRepaint` compares the live stroke's point count, the stroke-list length and the baked image's
identity, so a rebuild that changed neither does not repaint.

**The bake.** When a 51st stroke ends, the oldest live stroke is drawn into the baked image through a
`ui.PictureRecorder` and dropped from the list, and the redo stack is untouched by it. Consequences,
both intended: memory and paint cost are constant however long a child draws, and undo reaches back
exactly 50 strokes and then stops with the button greyed. A child cannot undo away an afternoon by
holding a button, and the button that has stopped working says so rather than doing nothing.

The backdrop, if any, is drawn beneath the baked image and is never part of it — an imported photo
stays separable from the strokes over it, so a later "remove the photo" is a field change rather than
a re-render of pixels that have already been mixed.

No image golden tests. `matchesGoldenFile` output differs between Skia and Impeller and between
platforms, so a golden here fails on somebody's machine for a reason that is not the code. The painter
is tested against a recording `Canvas` that counts operations and asserts their order — which is also
how the "walks at most 51 strokes" bound in §1 is checked.

### 4.4 Undo and redo

```dart
class DrawingController extends ChangeNotifier {
  void beginStroke(Offset atSheetPoint);
  void extendStroke(Offset atSheetPoint);
  void endStroke();          // appends, clears redo, bakes if over the horizon
  bool get canUndo;
  bool get canRedo;
  void undo();               // strokes.removeLast() -> redo
  void redo();               // redo.removeLast() -> strokes
}
```

A new stroke clears the redo stack — the standard rule, and the one a child's expectation matches:
having drawn something new, "redo" has nothing to mean. `canUndo` is false when `strokes` is empty,
which after a bake means 50 strokes back, not the beginning. Both buttons stay visible and greyed
when their stack is empty rather than disappearing, so the row does not move under a finger already
reaching for it and the control's position is learnable.

Neither stack is persisted. `PLAN.md` §3.7 keeps a Sudoku undo stack in the save because a puzzle is
one long session that a child returns to mid-thought; a drawing reopened tomorrow is a finished
picture, and 50 strokes of history is what would make the file large for a case nobody wants.

### 4.5 Storage

`drawings/<profileId>/<drawingId>.json` for the strokes, `<drawingId>.bg.png` for a backdrop (PR 6).
Both under the app support directory `path_provider` already resolves for `save.json`, written through
the same tmp-then-rename helper `FileSaveStore` uses (`core/storage/save_store.dart`), for the same
reason: a tablet that dies mid-write costs the last stroke, not the picture.

Why not in `save.json`: `PLAN.md` §5.2's few-kilobyte target, and blast radius — a corrupt drawing
file loses one picture and is moved aside the way `save.corrupt.json` is, whereas the same bytes
inside `save.json` would lose the profile. The gallery lists what it can decode and says nothing about
the rest; `AGENTS.md`'s rule is that a child never sees an internal error, and a missing picture in a
grid is self-explanatory in a way an error card is not.

**No `<drawingId>.thumb.png`, taken the other way from what this section first specified.** PR 4's
gallery grid renders each tile straight from the strokes, through the same `DrawingPainter` the sheet
itself paints with, scaled to the tile — a drawing has at most a few hundred strokes, which
`drawing_painter_test.dart` already shows painting inside a frame budget, so caching would trade a PNG
encode and a second file on disk for a cost the grid already pays each time it is built. Worth
revisiting once PR 7's device pass has a gallery large enough to measure the difference.

Autosave is `PLAN.md` §5.3's rule unchanged: debounced 500 ms after a stroke ends, and again on the
app leaving the foreground and on the screen being popped.

`save.json` carries `draw.drawingCount`, `draw.lastDrawingId` and `draw.bytesUsed` per profile
(`PLAN.md` §5.2), all three written by PR 4. **`bytesUsed` is recomputed by
`DrawingRepository.profileBytes` — a directory walk over `File.lengthSync`, stat calls rather than
content reads — after every save and delete, not tracked as a running total and healed once**, taken
the other way from what this section first specified: a number that is recomputed from what is
actually on disk cannot drift, so there is nothing for a healing step to fix, and a profile's drawing
count is small enough that the walk costs nothing an autosave needs to avoid. The 64 MB budget itself
and the gallery's "drawer is full" state are not wired up yet — `bytesUsed` is correct and available,
but nothing reads it against the cap until a PR asks a child to do something about being over it.

### 4.6 Export and import

**Export.** `ui.PictureRecorder` at 1600 x 1200, the same painter, `Picture.toImage`, then
`toByteData(format: ImageByteFormat.png)`. `dart:ui` encodes the PNG, so `package:image` is not a
dependency and the export path is the paint path — a drawing cannot export differently from how it
looked.

```dart
abstract interface class GalleryExport {
  Future<bool> get available;
  Future<void> savePng(Uint8List bytes, String name);
}
```

**`available` returns a `Future<bool>`, not the plain `bool` this section first sketched.**
`FolderGalleryExport` can only answer by asking `path_provider` for a downloads directory, which is
itself async, so both implementations answer the same way. `GalGalleryExport.available` is
unconditionally `true` — every Android and iOS device has a photo library, so there is nothing to
check — rather than probing `Gal.hasAccess()`: export stays available either way (§1), and asking for
permission from an availability check would show a dialog before a child has tapped anything.
`Gal.putImageBytes` is what actually asks, at the point of the write.

`GalGalleryExport` is the only file in `app/lib` that imports `package:gal`, and a scanner test
asserts it — the same shape of guard as `no_random_test.dart`, with its own self-tests, because a
plugin call that leaks into a widget is a call `flutter test` cannot run. On Windows, macOS and Linux
`FolderGalleryExport` writes to `<getDownloadsDirectory()>/Zibo Games/`. Downloads and not Pictures
because `path_provider` offers `getDownloadsDirectory()` and offers nothing for Pictures, and
hard-coding three platform conventions is the thing `PLAN.md` §2 took `path_provider` to avoid.

**`ios/Runner/Info.plist` needs two keys this section did not name.** `gal`'s own setup docs call
`NSPhotoLibraryAddUsageDescription` required unconditionally for a write, and
`NSPhotoLibraryUsageDescription` required below iOS 14 — `PLAN.md` §1's floor is 13, so both are set,
to the same add-only sentence. §3.3's "no permission" claim is about the *read* channel only; a write
through `gal` still shows an add-only prompt the first time, which is what these two strings are for.
macOS never reaches `Gal` (`FolderGalleryExport` handles it instead, §3.2's table), so
`macos/Runner/Info.plist` needs neither key.

**Import.** `photo_import.dart` over the §3.3 channel. The returned bytes are decoded with
`instantiateImageCodec`, downscaled to fit 1600 x 1200 with the aspect ratio kept, re-encoded to PNG
and stored as the drawing's `backdrop`. Downscaling on the way in and not on the way out is what keeps
a 12 MP phone photo from costing 30 MB of a 64 MB budget. The backdrop is locked: it cannot be moved,
scaled or erased, and **New sheet** is how a child gets rid of it.

On desktop, "the gallery" for import is the export folder, listed with `dart:io`. That is honest about
what the three desktop platforms have, and it makes the round trip — export, then re-import — work
everywhere without a file dialog.

### 4.7 The screens

Three, all `ScreenScaffold`:

- **The Draw card** on the home screen, a third `_GameCard` beside Sudoku and Arcade, taking a third
  `_Role` for its palette colour. The home column is three `Expanded` cards now; it already scrolls
  when the content does not fit (`home_screen.dart`), and the widget test that pumps it at 200% text
  scale is where a third card either fits or is caught.
- **The gallery**, a grid of thumbnails, newest first, with a **New sheet** tile first. Long-press
  selects for deletion, with a confirmation, because a delete is the one destructive action left.
- **The sheet.** The canvas fills what is left after the tool row, which sits in a band of its own
  below it — not an overlay, for the reason `PLAN-phase-4.md` gave for the control pad: a band cannot
  overlap the thing it controls, and `SafeArea` handles the gesture inset once. Landscape moves the
  band to the side the profile's `padSide` already names, which is a setting the child has set once
  for the arcade and should not have to set twice.

The tool row: four pencil dots at their actual widths, twelve colour swatches in two rows, an eraser,
undo, redo, and a **New sheet** button. No labels; `Semantics` on every one of them.

**Landscape lays that out as a panel rather than a column** — a change made after PR 3, because the
column it first shipped as put all twenty controls in single file, which is taller than any landscape
window: everything below the pencil dots had to be scrolled to. The panel keeps the same three
groups and the same order of them, each on its own line or lines: the four sizes, then undo, redo,
the eraser and **New sheet**, then the twelve colours in equal rows of six. The eraser moves up to
the action line there because that line has the room, and because twelve colours divide evenly into
rows where thirteen controls do not. The panel is as wide as six swatches where the window can spare
that much and as wide as the action line where it cannot — never more than half of what it and the
sheet share, so the sheet always keeps its own half — and every group folds onto more lines when it is given less, so a
window narrower than either still lays out rather than overflowing. Two rows of six is what makes the
whole panel fit a 400 dp-tall phone without scrolling; three rows of four does not
(`tool_row.dart`, `draw_sheet_screen.dart`).

**The sheet's header also carries a Save-picture action and, once §1's `allowPhotoImport` says yes,
an Add-a-photo one** — added at PR 6 rather than named here originally. Neither PR 5 nor this section
put a control on the export pipeline PR 5 built: §6's own done-criteria for PR 5 tests
`exportDrawingToPng` and `GalleryExport` directly and never asks for a button, which meant the whole
export feature had no way for a child to reach it until a device pass on PR 6 surfaced the gap.
`DrawSheetRoute` checks `GalleryExport.available` the same way it checks `PhotoImport.available` for
import, and shows the header action once it answers — on Android that answer is unconditional, so the
action appears as soon as the route mounts. Export carries no gate of its own beyond that: unlike
import, nothing here is a parental control, so there is nothing to check besides whether the platform
has somewhere to save to at all (`§4.6`).

---

## 5. Repository layout

```
app/lib/features/draw/
├─ model/
│  ├─ stroke.dart                # Stroke, Drawing, sheetSize
│  ├─ palette.dart               # the twelve colours and their spoken names, the four widths
│  └─ drawing_controller.dart    # strokes, redo stack, the horizon and the bake trigger
├─ data/
│  ├─ drawing_codec.dart         # Drawing <-> JSON, rounding as §4.1
│  ├─ drawing_repository.dart    # drawings/<profileId>/, tmp-then-rename, the byte budget
│  ├─ png_export.dart            # PictureRecorder -> PNG bytes
│  ├─ gallery_export.dart        # the interface, GalGalleryExport, FolderGalleryExport
│  └─ photo_import.dart          # MethodChannel('zibo/photos')
└─ ui/
   ├─ draw_gallery_screen.dart
   ├─ draw_sheet_screen.dart
   ├─ drawing_painter.dart
   └─ tool_row.dart              # sizes, palette, eraser, undo, redo, new sheet
app/android/app/src/main/kotlin/…/PhotoPickerPlugin.kt
app/ios/Runner/PhotoPicker.swift
```

`model/` holds no widget and no repository, so its tests run without a `WidgetTester` — the same split
`features/sudoku/model/` and `features/arcade/invaders/model/` use, and the reason the app suite's
budget in §1 survives a few hundred more tests. `data/gallery_export.dart` is the only importer of
`package:gal` (§4.6), and `data/photo_import.dart` the only file that knows a channel name.

---

## 6. Pull requests

Seven, each independently reviewable and each leaving `tool/verify.sh` green. The estimates assume one
developer part time, and the two native ones are wide because a device is in the loop.

### PR 1 — the model, the codec and the store (0.75–1 day)

`Stroke`, `Drawing`, `DrawingController` with undo, redo and the horizon, `drawing_codec.dart`,
`DrawingRepository`, and `PLAN.md` §5.2's `draw` block and `settings.allowPhotoImport` in
`save_data.dart` and `save_codec.dart`. No UI.

**Done when:** a 200-stroke drawing round-trips through the codec to an equal `Drawing`; undo then
redo returns the identical stroke list; a new stroke after an undo empties the redo stack; the 51st
stroke triggers a bake callback exactly once; a save with 60 drawings recorded encodes under 8 KB;
and a pre-phase-8 `save.json` still decodes with `allowPhotoImport` false.

### PR 2 — the canvas (1–1.25 days)

`DrawingPainter`, the sampling and smoothing of §4.2, the bake, `RepaintBoundary`, and the sheet
screen with no tool row — one colour, one size.

**Done when:** a `TestGesture` dragging 400 logical pixels produces a stroke whose point count matches
the 2-unit sampling rule; a tap produces a one-point stroke that paints a circle; the recording canvas
shows at most 51 stroke paths plus one image on a 500-stroke drawing; and the painter does not repaint
on a rebuild that changed nothing.

### PR 3 — the tool row (0.5–0.75 day)

Four sizes, twelve colours, the eraser, undo and redo with greyed states, **New sheet**.

**Done when:** every control's hit rect is at least 56 dp and undo and redo are at least 72 dp;
selection is asserted by border width, not colour; every control has a `Semantics` label; undo is
disabled with an empty stroke list and reports itself disabled to the semantics tree rather than only
to the eye; and the row lays out without overflow at 200% text scale in portrait and landscape.

### PR 4 — the gallery, the route and the home card (0.75–1 day)

`AppRoutes.draw` and `AppRoutes.drawSheet`, the gallery grid, thumbnails, delete with confirmation,
the third home card, autosave on stroke end and on lifecycle events.

**Done when:** a drawing survives a rebuild of the app from disk with its strokes intact — the test
phase 3 wrote for a Sudoku board, over a drawing; the home screen shows three cards and still does not
overflow at 200% text scale; a deleted drawing is gone from disk and from `bytesUsed`; and a drawing
file corrupted on purpose leaves the other drawings listed and shows no error card.

### PR 5 — export (0.5–0.75 day)

`png_export.dart`, `GalleryExport` with both implementations, `gal` in `pubspec.yaml` with the comment
`PLAN.md` §2's convention asks for, the Android manifest line, the macOS
`com.apple.security.files.downloads.read-write` entitlement that a sandboxed write to Downloads needs,
and the single-importer scanner test with its self-tests.

**Done when:** `tool/check_offline.dart` is clean with `gal` resolved and its output names no new
package; the exported PNG is 1600 x 1200 and its pixels match a small reference drawing rasterised in
the test; the scanner fails against a source that imports `package:gal` from a second file; and the
Android release manifest still contains no `INTERNET` permission, verified in the built artifact.

### PR 6 — import (1–1.25 days)

The `zibo/photos` channel, the Kotlin and Swift implementations, the backdrop field end to end, the
downscale, and `allowPhotoImport` in the settings screen.

**Done when:** picking a photo on an Android device and on an iPhone puts it under the strokes and
prompts for no permission; the stored backdrop is at most 1600 x 1200; the import control is absent
when `allowPhotoImport` is false and when the channel reports unavailable, asserted with a fake
channel; and a desktop build lists the export folder instead. This PR is droppable: if the device pass
fails, the phase closes without it and `PLAN.md` §7 records that, rather than the phase slipping.

**Built for Android only, taken the other way from "both platforms in one pull request."** The Kotlin
side (`PhotoPickerPlugin.kt`) is built and wired into `MainActivity.kt`, which changes from
`FlutterActivity` to `FlutterFragmentActivity` so `registerForActivityResult` — an
`androidx.activity.ComponentActivity` API — is available to call `PickVisualMedia` from
(`androidx.activity:activity-ktx` pinned in `app/android/app/build.gradle.kts` for the same reason).
The Swift side is not built. This is the droppability the paragraph above already names, applied per
platform rather than to the whole pull request: [ChannelPhotoImport.available] reads
`MissingPluginException` — what every call on the channel gets back on a platform with no native
handler registered — the same way it would read a handler that answered `false` on purpose, so an
unbuilt platform's import control simply does not appear rather than crashing. The desktop
export-folder fallback for import (§4.6's "the gallery is the export folder") is left for the same
reason: `available` reporting `false` there is honest, not a placeholder, until a later pull request
gives it something more specific to say. The backdrop field, the downscale, `allowPhotoImport` in
settings, and the round trip through the sheet's canvas, the export and the autosave are all built and
covered by `app/test/features/draw/` — only the two native pickers are split across pull requests
instead of shipping together.

### PR 7 — device pass and phase close (0.5 day)

Ten minutes of drawing on a phone and on a desktop target, a six-year-old drawing unaided, the numbers
in §1 confirmed or moved, and `PLAN.md` §7 updated with the outcome and anything that differed.

**Done when:** `PLAN.md` §7's phase-8 done-criterion is quoted with its result, met or not, and §8
below is ticked or has its unticked lines explained.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `image_picker` looks like the obvious fix when the channel misbehaves on a device | High | The reason it is banned is in `PLAN.md` §2's banned list, not only here, so it is read by anyone adding a dependency. `tool/check_offline.dart` fails the build either way — the risk is somebody weakening the check, which `AGENTS.md` names as the thing never to do |
| The native picker cannot be run in CI, so it rots | Medium | It is one channel with one method and a fake behind the same interface, so everything above it is tested. PR 6 is droppable, and PR 7's device pass is where it is confirmed. Not mitigated: a regression in the Kotlin or Swift after this phase is caught by a person or not at all — the same gap `AGENTS.md` records for `integration_test/` |
| `gal` is one maintainer's package | Low | Reached only through `GalleryExport`, so replacing it is a `MediaStore` insert and a `PHPhotoLibrary` request in one file. It adds no transitive package, so there is no graph to unpick |
| The bake makes an undo silently stop working at 50 | Medium | The button greys, which is a visible answer rather than a dead tap. Asserted in PR 3's test that it reports itself disabled to the semantics tree as well as to the eye |
| Erase with `BlendMode.clear` punches through to the screen | Medium | The paper colour is painted under the strokes layer, not as a stroke (§4.2), and the recording-canvas test asserts that order. It is the kind of bug that only shows on a dark theme, which is why it is an ordering assertion and not a look |
| A 12 MP backdrop blows the disk budget | Medium | Downscaled on the way in (§4.6), and the budget is checked before the write. One test imports a 4000 x 3000 image and asserts what lands on disk |
| Three `Expanded` home cards overflow a small phone in landscape | Low | The home screen already scrolls when content does not fit; PR 4's test pumps it at 200% text scale in both orientations |
| A child taps New sheet and loses the drawing | Low | New sheet files the drawing in the gallery; nothing is destroyed, so there is nothing to confirm (§1) |
| The phase grows a fill bucket, then stickers, then layers | High | §2 names each one and why it is out. The release line is already past — `PLAN.md` §7 ships at phase 6 — so this phase cannot delay a release, only itself |

---

## 8. Verification checklist

Ticked by the closing pull request. Each names how it is checked.

- [ ] `tool/verify.sh` green, app suite under 70 s.
- [ ] `dart tool/check_offline.dart` clean with `gal` in `pubspec.lock`, and its notes name no package
      that was not there before.
- [ ] `flutter pub deps --style=compact` in `app/` shows `gal` depending on `flutter` alone.
- [ ] The built release APK's manifest contains no `INTERNET` permission and contains
      `WRITE_EXTERNAL_STORAGE` with `android:maxSdkVersion="28"` — read out of the artifact, not out
      of the source.
- [ ] `app/test/features/draw/` covers: codec round trip, undo/redo invariants, the bake at 51, the
      2-unit sampling rule, the tap-to-dot case, the paper-under-strokes ordering, the 56 dp and 72 dp
      floors, semantics labels on every control, the disabled undo reported to semantics, the
      single-`gal`-importer scanner and its self-tests.
- [ ] A drawing survives an app rebuilt from disk, strokes identical, over a temp-directory store.
- [ ] A deliberately corrupted drawing file leaves the gallery listing the others, with no error card.
- [ ] A 500-stroke drawing paints at most 51 stroke paths plus one image, asserted on a recording
      canvas.
- [ ] A 4000 x 3000 imported image lands on disk at no more than 1600 x 1200.
- [ ] On an Android phone: draw, change size and colour, erase, undo, redo, export, and find the PNG
      in the Photos app. Name the device in the pull request.
- [ ] On the same phone: import a photo with no permission prompt, draw over it, force-quit, reopen
      and find both the backdrop and the strokes.
- [ ] On one desktop target: the same round trip through the `Zibo Games` folder under Downloads.
- [ ] A six-year-old draws, changes colour, undoes and exports without being told how. Say which parts
      needed telling.
- [ ] `PLAN.md` §7's phase-8 criterion quoted with its result, and §2, §5.2, §5.3, §6 and §8 there
      reconciled with what was built.

Not on this list and deliberately: an iOS device pass, which needs the Mac and the developer account
`PLAN.md` §7 puts in phase 6. Until then the Swift in PR 6 is code nobody has run — stated here rather
than ticked.

---

## 9. Open questions

| Question | What would resolve it |
|---|---|
| Is the system photo picker legible to a six-year-old, or does an adult have to drive the import? | PR 7's pass. If an adult has to drive it, that is an argument for leaving `allowPhotoImport` off by default, which is where it already is |
| Are twelve colours and four sizes the right counts for a small hand, or does the row need to be shorter? | PR 7. The counts are one constant each in `palette.dart` |
| Is 64 MB per profile the right budget, and 50 the right undo horizon? | Both are guesses with a stated basis, not measurements. A tablet with several profiles and a few weeks of drawings answers the first; a child holding undo answers the second |
| Should the iOS floor move from 13 to 14 so `PHPickerViewController` is always there? | Phase 6, when iOS is built at all. iOS 13 devices are the ones that would lose the app, against a feature the rest gain |
| Should `allowPhotoImport` default to true after all? | The user's call, not a technical one. It is stated as an assumption in §1 rather than settled: default false means the feature is invisible until a parent finds it in settings, which is the safe direction and also the one that gets a bug report saying import is missing |
| Does the drawing board want sound, given phase 5 will have `flutter_soloud` by then? | Left out of this plan entirely. A pencil that squeaks is a decision for whoever has heard one |

---

## 10. Starting order

1. **PR 1's model and codec**, before any pixel is drawn. Undo, redo and the bake are the phase's only
   real invariants, and they are testable without a canvas — the same reason `PLAN.md` §10 wrote `Rng`
   and its determinism test before the generator.
2. **`gal` and `tool/check_offline.dart` together**, early, even though PR 5 is where the export
   lands. The whole phase's dependency story rests on that check staying clean, and the cheapest
   time to discover otherwise is before three pull requests are built on it. `gal 2.3.3` was resolved against
   this SDK while writing §3.2 and adds only itself; that is evidence, not a guarantee about the
   version that resolves on the day.
3. **The Android half of the channel before the iOS half.** Android is `PLAN.md` §7's primary target,
   it is the device this project has, and `PickVisualMedia`'s own fallback is the part most likely to
   surprise on an API 26 tablet.
