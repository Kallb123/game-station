# Phase 1 — app skeleton

Expands [`PLAN.md`](PLAN.md) §7 phase 1 into an ordered set of pull requests. `PLAN.md` stays the
source of truth for scope and phase order; this file is the working detail for one phase and is
deleted or archived when phase 1 closes.

Phase 1 delivers the shell the later phases plug into: theme, storage, profiles, settings, and a home
screen with two entry points. It ships no gameplay.

---

## 1. Scope and constraints

| Constraint | Rationale |
|---|---|
| No new dependency beyond `flutter_riverpod` and `path_provider` | The two `PLAN.md` §2 dependencies this phase needs; the header comment in `app/pubspec.yaml` already assigns them here. Anything else is a later phase's dependency carried through every intervening review. |
| Every save write is atomic | Interrupted writes are the only way a few kilobytes of JSON corrupts. `.tmp` + `rename` removes the failure mode rather than narrowing it. |
| A malformed save never blocks boot | A child cannot fix a boot loop. Losing a high score is recoverable; an app that will not start is not. |
| Storage model and codec import no `dart:io` | Keeps the schema testable without a filesystem, and keeps a fake store possible for widget tests. |
| Tap targets never below 56 dp; primary actions 72 dp | `PLAN.md` §4.2. Enforced by a token, not by eyeballing each widget. |
| No ambient randomness anywhere in `lib/` | The engine's determinism rule (`AGENTS.md`) is easier to keep if `Random` is absent from the app too. Profile IDs come from a counter. |
| `tool/verify.sh` green before every commit | It is what CI runs, in the same order. |

---

## 2. Non-goals

| Not in phase 1 | Where it belongs |
|---|---|
| Any Sudoku or arcade gameplay | Phases 2–4. The two home cards route to placeholder screens. |
| Audio playback, haptic feedback firing | Phases 4–5. Phase 1 stores and surfaces the `sound` and `haptics` settings; nothing consumes them yet. |
| A `music` toggle in the UI | Phase 5. The field exists in schema v1 (`PLAN.md` §5.2) so no migration is needed later; the control is not drawn. |
| Save export and import (`PLAN.md` §5.3) | Phase 6, with the release work. It needs a share sheet on mobile and a file picker on desktop — a dependency and a platform surface each. |
| Accessibility pass, i18n, rotation and tablet layouts | Phase 5. Phase 1 must not actively break them: no fixed pixel heights on text, no colour-only signals. |
| Icons, splash, bundled art assets | Phase 6. Avatars are Material icons plus a token colour, so `app/assets/` stays empty and no asset licence entry is needed yet. |
| `puzzleCache` population and eviction | Phase 3. Schema v1 carries the field; nothing writes it. |
| Gamepad support, deep links, URL routing | Not planned, or phase 7. Offline app with no URLs. |

---

## 3. Approach

Four layers, each usable and testable without the one above it:

1. **Tokens and theme** — `core/ui/`. Pure Flutter, no state, no storage.
2. **Save model and codec** — `core/storage/`. Pure Dart data classes plus JSON encode/decode and
   migration. No `dart:io`, no Flutter.
3. **Store and repository** — `core/storage/`. File IO behind an interface, an in-memory
   implementation for tests, and a Riverpod-held repository owning the debounce and flush rules.
4. **Features** — `features/home`, `features/profiles`, `features/settings`, on top of 1–3.

Alternatives considered:

| Option | Rejected because |
|---|---|
| `go_router` for routing | Its value is deep linking and browser URL sync. An offline app with five screens gets neither, and it is a dependency in every future review. Flutter's `Navigator` with an `onGenerateRoute` table costs nothing. |
| `shared_preferences` for settings | Splits state across two stores with different failure and migration behaviour, and it has no atomic-write guarantee that we control. One `save.json` keeps one migration path. |
| `drift`/SQLite now | `PLAN.md` §2: the data is a few kilobytes. `ProgressRepository` is the seam that makes swapping it later a non-event. |
| `json_serializable` codegen | Two hand-written codecs for ~6 classes are shorter than the build_runner setup, and generated code would need the same golden tests anyway. |
| `AsyncNotifier` exposing `AsyncValue<SaveData>` to every widget | Every screen would handle a loading state that only exists for the first ~10 ms. Loading the save before `runApp` and overriding a synchronous provider removes the state instead of handling it. |
| Freezed for immutable models | Another codegen dependency for `copyWith` on six classes. |

**Load-bearing decision:** the `SaveData` shape and the `ProgressRepository` interface. Phases 3, 4
and 5 all write through them. Changing either later means a schema migration plus edits in every
feature, so they get their tests in phase 1 and change deliberately after.

---

## 4. Design

### 4.1 Design tokens and theme

`core/ui/tokens.dart` holds the raw values; nothing else in the app hard-codes a number.

| Token group | Values |
|---|---|
| Spacing | 4, 8, 12, 16, 24, 32, 48 |
| Radii | 12 (card), 24 (button), 999 (pill) |
| Tap targets | `minTap = 56`, `primaryTap = 72` |
| Type scale | display 40 / title 28 / body 18 / caption 14, all scaling with `MediaQuery.textScaler` |
| Palette | One seed per surface role, day and night, chosen so no state is signalled by colour alone |

`core/ui/theme.dart` builds day and night `ThemeData` from those tokens, and sets
`MaterialTapTargetSize` plus button minimum sizes from `minTap`, so a button below the minimum is
impossible rather than discouraged.

`core/ui/` also gets the two shared widgets phase 3 and 4 will reuse: `BigButton` (icon, label,
`primaryTap` minimum, no colour-only state) and `ScreenScaffold` (safe-area padding, back affordance,
title).

Theme selection: `day | night | system`, default `system`. `PLAN.md` §5.2 shows only `day`; the
`system` value is added there in the same PR.

Reduced motion is the **or** of the stored setting and `MediaQuery.disableAnimations`, so a device-level
setting is honoured without the child touching the app's settings.

### 4.2 Save model and codec

```dart
// app/lib/core/storage/save_data.dart — no dart:io, no flutter imports
const int currentSchemaVersion = 1;

class SaveData {
  final int schemaVersion;      // == currentSchemaVersion in memory
  final int generatorVersion;   // from puzzle_engine, recorded at write time
  final String activeProfileId;
  final AppSettings settings;
  final List<Profile> profiles; // never empty
  final Map<String, String> puzzleCache;
}

class AppSettings {
  final bool sound, music, haptics, showTimer, reduceMotion;
  final ThemeChoice theme;      // day | night | system
}

class Profile {
  final String id;              // "p1", "p2", … — counter, never random
  final String name;
  final AvatarId avatar;        // fixed enum, mapped to an icon + token colour
  final DateTime createdAt;     // UTC
  final SudokuProgress sudoku;  // solved / inProgress / streak / bestTimes
  final ArcadeProgress arcade;  // high scores per game
}
```

`SudokuProgress` and `ArcadeProgress` are declared with their phase-3/4 fields and encoded as written
in `PLAN.md` §5.2, but nothing in phase 1 writes to them. Declaring them now is what keeps schema v1
final; adding them in phase 3 would mean a migration for a file that already shipped.

```dart
// save_codec.dart
SaveData decodeSave(String json);           // throws SaveFormatException
String   encodeSave(SaveData data);
Map<String, Object?> migrate(Map<String, Object?> raw);
```

Decisions:

- **Unknown `schemaVersion` higher than current** throws `UnsupportedSaveVersion`. A downgrade after a
  test-flight install is rare; guessing at a newer file's meaning is how data is destroyed silently.
- **Migration is a chain of single-step functions** (`_v1FromV0`, …) rather than one branching
  function, so each step is testable against a fixture in isolation.
- **Decode is strict about types and lenient about missing optional fields.** A missing `settings`
  block yields defaults; a `settings` block whose `sound` is a string is a format error. Silent
  coercion hides the bug that produced it.
- **`DateTime` is stored as an ISO-8601 UTC string** and parsed back as UTC, matching `PLAN.md` §3.2's
  reason for using UTC for the daily index.
- **Keys that come from the data — puzzle ids, game ids — are written sorted.** The encoded bytes are
  then a function of the content alone, not of the order the app inserted things in, so a re-encode of
  an unchanged save is byte-identical and a hand-diff of the file is readable.
- **A dangling `activeProfileId` is repaired to the first profile; everything else is refused.** It is
  a stale pointer with a lossless fix, and refusing it would move every profile aside over one wrong
  string. It is the only repair the codec makes.

### 4.3 Store and repository

```dart
// save_store.dart
abstract interface class SaveStore {
  Future<SaveLoad> load();
  Future<void> write(SaveData data);
}

enum SaveRecovery { missing, corrupt, unsupportedVersion }
class SaveLoad { final SaveData data; final SaveRecovery? recovery; }

class FileSaveStore implements SaveStore { FileSaveStore(this.directory); … }
class MemorySaveStore implements SaveStore { … }   // widget tests, no filesystem
```

`FileSaveStore` behaviour:

| Situation | Action |
|---|---|
| Write | Encode to `save.json.tmp`, `flush()`, `close()`, then `rename` over `save.json`. |
| Leftover `save.json.tmp` on load | Delete it, unread. A half-written temp file is not a save. |
| No `save.json` | Return defaults with `recovery: missing`. Not an error — it is first launch. |
| Parse or format failure | Move to `save.corrupt.json` (overwriting any previous one), return defaults with `recovery: corrupt`. |
| `schemaVersion` above current | Move to `save.unsupported.json`, return defaults with `recovery: unsupportedVersion`. |

Recovery is surfaced once, on the home screen, in words a child can read ("We couldn't find your old
games, so we started fresh"), then dismissed. It is deliberately not persisted: the next launch reads
a valid file, so the message cannot repeat.

`ProgressRepository` owns the write rules from `PLAN.md` §5.3:

- The save is read once at startup; every later read is from memory.
- Mutations update memory immediately and schedule a write **debounced 500 ms**.
- **Single-slot write queue, latest wins.** While a write is in flight, a new one replaces any queued
  state rather than stacking. Two concurrent `rename` calls over the same path is the one way this
  design corrupts, and a queue of one removes it.
- `flush()` awaits the pending and in-flight writes. It is called from an `AppLifecycleListener` on
  `paused`/`detached` and from `onExitRequested` on desktop, and awaited in tests instead of pumping
  timers.

Profile rules:

- IDs are `p{max existing + 1}`, so no `Random` and no clock in an identifier.
- The profile list is never empty. Deleting the last profile is refused by the repository, not only
  hidden in the UI. Deleting the active profile selects the first remaining one.
- Names are trimmed, capped at 12 characters, and an empty name falls back to `Player {n}` — a child
  who taps *Create* without typing gets a profile, not a validation error.

### 4.4 State wiring

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = FileSaveStore(await getApplicationSupportDirectory());
  final loaded = await store.load();
  runApp(ProviderScope(
    overrides: [saveStoreProvider.overrideWithValue(store),
                initialSaveProvider.overrideWithValue(loaded)],
    child: const GameStationApp(),
  ));
}
```

Loading before `runApp` means widgets read a synchronous `SaveData` and no screen carries a loading
branch. The file is a few kilobytes, which is well inside the 2 s cold-start budget in `PLAN.md` §9.

Selectors (`settingsProvider`, `activeProfileProvider`) are derived providers, so a settings toggle
does not rebuild the profile list.

### 4.5 Routing and screens

`Navigator` with an `onGenerateRoute` table in `app.dart`. Routes in phase 1:

| Route | Screen |
|---|---|
| `/` | Home — two `BigButton` cards, Sudoku and Arcade, plus profile chip and settings icon |
| `/profiles` | Profile picker, create, rename, delete |
| `/settings` | Sound, haptics (mobile only), show timer, theme, reduced motion |
| `/sudoku`, `/arcade` | Placeholder screens: title and "Coming soon" |

The placeholders are deliberate. Phase 3 and 4 replace the body of a screen that already exists, sits
under a working router, and has a widget test, rather than adding all three at once.

Haptics is hidden on desktop via `defaultTargetPlatform`, because a toggle that does nothing on the
device in front of you is worse than an absent one.

---

## 5. Repository layout

```
app/lib/
├─ main.dart                    # load save, ProviderScope overrides, runApp
├─ app.dart                     # MaterialApp, themes, onGenerateRoute
├─ core/
│  ├─ ui/
│  │  ├─ tokens.dart            # spacing, radii, tap targets, type scale, palette
│  │  ├─ theme.dart             # day/night ThemeData built from tokens
│  │  ├─ big_button.dart
│  │  └─ screen_scaffold.dart
│  └─ storage/
│     ├─ save_data.dart         # models — no dart:io, no flutter
│     ├─ save_codec.dart        # encode/decode/migrate
│     ├─ save_store.dart        # SaveStore, FileSaveStore, MemorySaveStore
│     ├─ progress_repository.dart
│     └─ providers.dart         # riverpod providers and selectors
└─ features/
   ├─ home/home_screen.dart
   ├─ profiles/profile_screen.dart
   ├─ settings/settings_screen.dart
   └─ placeholders/coming_soon_screen.dart
```

The `core/storage` split is where the boundaries matter: `save_data.dart` and `save_codec.dart` are
pure, so their tests need no temp directory; `save_store.dart` is the only file in the layer that
touches the filesystem. The models do not live in `packages/puzzle_engine` — that package is Sudoku
generation, and a save schema that referenced arcade high scores would break its single purpose.

---

## 6. Pull requests

One PR per row, merged in order; each is reviewable on its own and leaves the app running. Estimates
assume one developer, part time (roughly half a working day per unit), which is where the spread comes
from — the ranges widen where a platform check is involved. Total 4–4.5 days, against `PLAN.md` §7's
3–4 days for the phase; the extra is the six-target check in PR 7.

Every PR runs `tool/verify.sh` and a `/caveman-review` pass before it opens, per `AGENTS.md`.

### PR 1 — Design tokens and theme (0.5 day)

Commits:
1. `core/ui/tokens.dart` — spacing, radii, tap targets, type scale, day and night palettes.
2. `core/ui/theme.dart` — `ThemeData` builders; button minimum sizes derived from `minTap`.
3. `BigButton` and `ScreenScaffold`, with widget tests.

**Done when:** a widget test asserts a default `BigButton` renders at least 72 dp high and a default
`ElevatedButton` at least 56 dp, in both themes, and at 200% text scale nothing overflows in the test
harness. No app screen changes yet.

### PR 2 — Save schema and codec (0.5 day)

Commits:
1. `save_data.dart` — all of schema v1, including the phase-3/4 fields nothing writes yet.
2. `save_codec.dart` — encode, decode, `migrate`, `SaveFormatException`,
   `UnsupportedSaveVersion`.
3. Tests: round trip equality; a hand-written v1 fixture decodes to the expected object; the
   `PLAN.md` §5.2 example JSON decodes without loss; malformed and wrong-typed inputs throw; a
   `schemaVersion: 99` file throws `UnsupportedSaveVersion`.

**Done when:** `flutter test` covers encode→decode→encode byte equality for a fixture containing every
field, and `dart tool/check_offline.dart` still passes with no new violations.

### PR 3 — Store and repository (0.75 day)

Commits:
1. Add `path_provider` to `app/pubspec.yaml`; confirm `check_offline` passes on the resolved graph.
2. `FileSaveStore`: atomic write, `.tmp` cleanup, corrupt and unsupported recovery.
3. `MemorySaveStore` plus `ProgressRepository`: debounce, single-slot queue, `flush()`, profile and
   settings mutations.
4. Tests over `Directory.systemTemp.createTemp()`: write→reload round trip; a pre-planted corrupt
   file loads defaults and leaves `save.corrupt.json` behind; a pre-planted `.tmp` is deleted and
   ignored; ten rapid mutations produce one file write and the last state survives `flush()`;
   deleting the last profile is refused.

**Done when:** the temp-directory suite passes, and a test that constructs a second
`FileSaveStore` over the same directory — the "kill and relaunch" case — reads back the exact state
the first one flushed.

### PR 4 — Riverpod wiring, router, home screen (0.75 day)

Commits:
1. Add `flutter_riverpod`; `providers.dart`; `main.dart` loads the save before `runApp`.
2. `onGenerateRoute` table, `ComingSoonScreen`, `/sudoku` and `/arcade` placeholders.
3. `HomeScreen` with the two cards, the active-profile chip and the settings icon; delete
   `ScaffoldHomePage` and rewrite `app/test/app_test.dart` against the real screen.
4. The corrupt-save banner, shown once from `SaveLoad.recovery`.

**Done when:** tapping each home card lands on its placeholder and back returns home, in a widget
test with a `MemorySaveStore`; and a `MemorySaveStore` seeded with `recovery: corrupt` shows the
banner exactly once.

Differed from the plan, decided while building it:

- `flutter_riverpod` is pinned to `^2.6.1`. Riverpod 3 declares `package:test` as a *runtime*
  dependency, which puts `web_socket_channel` and `web_socket` in the app's resolved graph;
  `tool/check_offline.dart` reads the graph rather than trusting reachability, and narrowing that
  check to admit a state library is the wrong way round.
- `/profiles` and `/settings` route to `ComingSoonScreen` here rather than being added in PR 5 and
  PR 6. The home screen's profile chip and settings button exist in this PR, and a control that does
  nothing reads to a child as a broken app; PR 5 and PR 6 change the target, not the call site.
- The `AppLifecycleListener` flush from §4.3 landed here, since it is the wiring that gives the
  repository somewhere to be flushed from.
- `main` falls back to a `MemorySaveStore` when `path_provider` cannot resolve a directory (§7's
  Linux-desktop risk). The app then runs and forgets rather than failing to start.

### PR 5 — Profiles (0.5 day)

Commits:
1. `ProfileScreen`: picker grid of avatar buttons, create, rename, delete with confirmation.
2. Wire the home profile chip to it; avatar enum to icon and colour mapping.
3. Widget tests: create then select persists across a repository reload; delete the active profile
   selects another; the delete control is absent when one profile remains.

**Done when:** a widget test creates a second profile, selects it, rebuilds the app over the same
store, and finds the second profile still active.

Differed from the plan, decided while building it:

- **A single column, not a grid.** A `GridView` tile has a fixed aspect ratio, so at 200% text scale
  a wrapped name is clipped inside a box that cannot grow. There are at most a handful of profiles,
  so one scrolling column costs nothing and never cuts a name off.
- **Selecting or creating a player returns to the home screen.** Picking a player is the question the
  screen was opened to answer; a child who has answered it should not have to find the back arrow to
  start playing. Renaming, changing the picture and deleting leave the picker open, because they are
  adjustments rather than answers.
- **Rename, picture and delete sit behind one edit control per row**, not beside the name. The row
  itself is what a child taps to play, so everything that changes or loses a profile is one
  deliberate step away from it, and deleting takes a second confirmation on top — with *Keep* as the
  emphasised button, since losing a profile's games is the one thing in the app that cannot be
  undone.
- **The avatar mapping grew a colour and a name.** §2 already said avatars are "Material icons plus a
  token colour", so `tokens.dart` gained one swatch per avatar and `avatars.dart` the enum-to-swatch
  mapping. `avatarLabel` came with it: the pictures are icon-only controls, and without a name a
  screen reader reads the picker as a row of unlabelled buttons.

### PR 6 — Settings (0.5 day)

Commits:
1. `SettingsScreen` with the five phase-1 controls; haptics hidden off-mobile.
2. Theme and reduced-motion applied at `MaterialApp`; reduced motion or-ed with
   `MediaQuery.disableAnimations`.
3. Widget tests: toggling theme changes `Theme.of(context).brightness`; every toggle survives a
   repository reload; the haptics row is absent with `debugDefaultTargetPlatformOverride` set to a
   desktop platform.

**Done when:** switching theme to night, restarting the app in a test over the same store, and
reading `Theme.of(context).brightness` gives `Brightness.dark`.

Differed from the plan, decided while building it:

- **Reduced motion also switches the screen-to-screen slide off**, which §4.1 did not ask for. A
  setting that changes nothing until phase 4 is a promise rather than a mechanism, and the page
  transition is the only animation phase 1 has.
- **The **or** in §4.1 is not a branch in the app.** Only the stored half needs anything doing: the
  device's half is already in the ambient `MediaQuery`, and Flutter acts on it by itself — an
  `AnimationController` cuts its duration to a twentieth when the platform asks for less motion. The
  app therefore adds its own half into the same `MediaQuery` flag, so that a phase-4 animation reads
  one value and gets both answers. The tests assert what the app *does*, because a test that read the
  flag back would have passed whether or not the app had looked at it.
- **The theme choice is three buttons, not a dropdown or a segmented control.** The chosen one is
  visible without opening anything, each clears the primary tap target, and selection is a border and
  a check as well as a colour. It makes the screen taller than a phone, so it scrolls.
- **`pumpApp` in the test harness now tears the previous tree down first.** `pumpWidget` updates an
  element tree in place when the root widget matches, so a second call kept the first launch's
  navigator and route stack — a "relaunch" that had not relaunched. Every test that restarts the app
  over the same store depends on this, PR 5's included.

### PR 7 — Phase 1 close (0.5–1 day)

Commits:
1. Manual six-target run: Android, iOS, Windows, macOS, Linux, plus one tablet form factor. Record
   the result per target in the PR body, including any target not checked and why.
2. `PLAN.md`: mark phase 1 done, add the `system` theme value to §5.2, note anything that differed
   from the plan.
3. `README.md` status section; delete or archive this file.

**Done when:** on every target that was checked, changing a setting and creating a profile, then
force-quitting and reopening, restores both — and every target not checked is named in the PR body
with the reason.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `File.rename` over an existing file fails on Windows (locked by antivirus or an indexer) | High | Exercised by the temp-directory suite on the Windows CI job, which is gated to `main`/dispatch — so PR 3 triggers a `workflow_dispatch` run before merge. If it fails, fall back to delete-then-rename and recover from `.tmp` on next load. |
| Debounced write lost on force-kill | Medium | `flush()` on `paused`/`detached` and `onExitRequested`; the ten-mutations test asserts the last state survives `flush()`. Residual risk: a kill inside the 500 ms window loses one toggle, which is acceptable for a settings flip and is why phase 3's move-by-move save also flushes on pause. |
| Two writes race and interleave their renames | High | Single-slot write queue in `ProgressRepository`; the concurrent-mutation test asserts one resulting file and the latest state. |
| Schema v1 turns out to be wrong in phase 3 | Medium | Phase-3/4 fields are declared and round-trip-tested now, before any file ships. If it still changes, the migration chain and `schemaVersion` exist from PR 2 — the cost is a migration step, not a data loss. |
| `path_provider` returns an unwritable or surprising directory on Linux desktop | Medium | Checked on the Linux target in PR 7; a write failure is caught and surfaced as "couldn't save", never an unhandled exception. |
| "All six targets" cannot be honestly verified without a Mac, a Windows box and two phones | Medium | No technical mitigation. PR 7 records per target what was checked; unchecked targets are stated in the PR body rather than implied by silence. |
| Scope creep into Sudoku UI while building the home screen | Medium | `/sudoku` and `/arcade` route to `ComingSoonScreen` in PR 4. Adding a grid there is a visible diff in the wrong file. |
| `path_provider` drags a platform permission into the Android release manifest | Low | CI's release-APK permission assertion already fails on any unexpected permission; PR 3 relies on it rather than on inspection. |

---

## 8. Verification checklist

- [ ] `tool/verify.sh` passes from a clean checkout.
- [ ] `dart tool/check_offline.dart` reports no violations after both new dependencies are added.
- [ ] The CI Android job's permission assertion still passes with `path_provider` in the graph.
- [ ] `flutter test` covers: codec round trip, corrupt recovery, `.tmp` cleanup, unsupported version,
      debounce coalescing, refusal to delete the last profile.
- [ ] A second `FileSaveStore` over the same temp directory reads back the flushed state.
- [ ] `grep -rn "Random(" app/lib` returns nothing.
- [ ] No literal spacing or size numbers outside `core/ui/tokens.dart` (`grep` for `EdgeInsets.all(`
      with a bare number in `features/`).
- [ ] Every screen renders at 200% text scale in a widget test without an overflow error.
- [ ] On each checked target: set a setting, create a profile, force-quit, reopen — both restored.
- [ ] Android: airplane mode on, full run through home → profiles → settings, no errors.
- [ ] `PLAN.md` §5.2 and §7 match what was built.

---

## 9. Open questions

| Question | What resolves it |
|---|---|
| Is `theme: "system"` acceptable alongside `PLAN.md` §5.2's `day`/`night`? | Owner's call. Assumed yes and written into PR 6; §5.2 is updated in PR 7. |
| Should save export/import (§5.3) land in phase 1 rather than phase 6? | Owner's call. Assumed phase 6, because it needs a share sheet and a file picker — a dependency each, which §2 of this plan excludes. |
| Which physical devices are available for the PR 7 six-target check? | Ask before PR 7 starts. It decides whether "done when" is met or partially recorded as unchecked. |
| Avatars as Material icons now, or bundled art? | Assumed icons, so phase 1 adds no asset licensing. Art is a phase-6 item if wanted. |
| Does the corrupt-save banner need parent-facing detail (a file path) as well as the child message? | Ask. Assumed no: one sentence, dismissible, no path. |

---

## 10. Starting order

1. PR 1 — tokens and theme. It unblocks every screen and touches no state.
2. PR 2 — schema and codec, with the `PLAN.md` §5.2 example JSON as the first fixture. Writing the
   schema before the store means the store has something real to serialise.
3. PR 3 — `FileSaveStore` and `ProgressRepository`, and trigger a Windows CI run on that branch before
   merging, because the rename behaviour is the one thing in this phase that a Linux run cannot tell
   us.

**Release line is unchanged:** `PLAN.md` §7 ships at phase 6. Nothing here is user-visible on its own.
