# Zibo Games — Implementation Plan

A local, offline, ad-free games app for children. Sudoku (9x9 and 6x6, deterministic from a date or
index) plus retro arcade games driven by on-screen controls, with progress that persists across
sessions. A drawing board arrives after the release line, as §7's phase 8.

---

## 1. Scope and constraints

| Constraint | Rationale |
|---|---|
| No ads | Ads compete for a child's attention and interrupt play. |
| No network | The app works on a plane, in a car, anywhere. |
| No tracking | No analytics, no crash reporting, no telemetry. Nothing leaves the device. |
| No purchases | No IAP, no energy timers, no gated content. |
| Persistent progress | Solved puzzles, best times and high scores survive restarts. |
| Kid-first UI | Large touch targets, minimal reading, no time pressure. |

Targets: Android 8+ (phone and tablet), iOS 13+ (phone and tablet), Windows 10+, macOS 11+, Linux
(GTK).

---

## 2. Tech stack

**Flutter + Flame, in Dart. One codebase, six platforms.**

Reasons:

- Real desktop support, not a wrapped web view.
- Flutter's widget layer suits the Sudoku grid, which is layout and input rather than rendering.
- Flame supplies the game loop, sprites, collision and on-screen controls on top of that same layer,
  so the arcade games share the app's widgets and theme.
- Dart is fast enough for the constraint propagation that puzzle generation needs.
- Free and open source. No engine revenue share, no seat licensing.
- Small binaries; no embedded browser runtime.

Alternatives rejected:

| Option | Reason rejected |
|---|---|
| Godot | Strong game engine, weak app-shell and menu UI. Rougher iOS release path. Two mental models for the Sudoku grid. |
| React Native | Weak desktop story; the Windows and macOS ports lag the mobile ones. |
| Unity | Heavy runtime and licensing churn for what is mostly 2D and UI. |
| Electron / Tauri | Good on desktop, weak on mobile, large binaries. |
| Six native apps | Six implementations of the same puzzle engine. |

### Dependencies

| Need | Package | Note |
|---|---|---|
| Game engine | `flame` | Game loop, sprites, collision, on-screen controls |
| State and DI | `flutter_riverpod` | Small, no code generation |
| Save location | `path_provider` | Resolves the per-platform app support directory |
| Audio | `minisound` | Playback on all six targets from one MIT package, with `miniaudio` vendored rather than fetched at build time. **Not `flutter_soloud`**, which `PLAN.md` named until phase 5 resolved the graph: it declares `http: ^1.3.0` at 2.1.7, 3.5.4 and 4.1.7 alike, so `tool/check_offline.dart` fails on it (`PLAN-phase-5.md` §3.1). `minisound_ffi` declares `RECORD_AUDIO` for a recorder this app never uses, which the app's manifest removes with `tools:node="remove"` — the built APK is checked by `tool/check_apk_permissions.sh` in CI (`PLAN-phase-5.md` §3.2) |
| Haptics | `HapticFeedback` | Built in. Guard by platform check; mobile only |
| Save a drawing to the photo library | `gal` | Phase 8, used on Android and iOS only although it also supports macOS and Windows. Depends on `flutter` and nothing else, so it adds one package to the resolved graph and no transitive one. Desktop has no photo library: the PNG goes to a folder under `getDownloadsDirectory()` through `dart:io` |
| Test | `flutter_test`, `test`, `integration_test` | Built in |
| Lint | `flutter_lints` plus strict analyzer options | Built in |

Banned dependencies:

- No ad SDKs — no `google_mobile_ads` or equivalent.
- No `firebase_*`, no `sentry`, no analytics or crash reporting.
- No `google_fonts` — it fetches fonts over the network at runtime. Bundle font files in
  `assets/fonts/` instead.
- No `http`, no `dio`. If no networking code exists, no networking can leak.
- No `flutter_soloud`, `audioplayers`, `flame_audio`, `assets_audio_player` or `soundpool` — every
  audio package with a plausible claim to this app except `minisound` resolves `http` into the shipped
  graph. `flutter_soloud` declares it directly for its `loadUrl`, and `flame_audio` inherits it from
  `audioplayers`. Resolutions were run against this SDK before phase 5 started rather than reasoned
  about; `PLAN-phase-5.md` §3.1 has the table, including `flutter_pcm_sound`, which is clean and
  covers only three of the six targets.
- No `image_picker` and no `file_selector`, which phase 8 would otherwise have reached for. Both
  resolve `http` into the **shipped** graph through `image_picker_platform_interface` and
  `file_selector_platform_interface`, and `tool/check_offline.dart` reads the resolved graph rather
  than trusting that nothing calls it. Phase 8 reads the photo library through an in-repo platform
  channel instead (§7).
- No `photo_manager`. Its graph is clean — `flutter` and `path` — but it enumerates the whole photo
  library, which means `READ_MEDIA_IMAGES` on Android 13+ and `NSPhotoLibraryUsageDescription` on
  iOS. A children's app asking to read the family album is a worse trade than writing the picker: the
  system picker returns one image and asks for no permission at all.

Enforce the constraints in the build rather than by convention:

- **Android:** omit `android.permission.INTERNET` from the manifest. The OS then blocks network
  access itself, and the store listing shows the app has no network permission — stronger evidence
  for a parent than a claim in the description.
- **iOS / macOS:** no network entitlement. Leave `com.apple.security.network.client` off under the
  macOS sandbox.
- **CI:** fail the build if `http://`, `https://`, `Socket` or `HttpClient` appear in `lib/`.

### Persistence

The data is a few kilobytes, so no database is needed.

- A single `save.json` in the app support directory, located via `path_provider`.
- Write to `save.json.tmp`, flush, then `rename` over the original. Rename is atomic, so a crash or
  power loss mid-write cannot corrupt the save.
- A `schemaVersion` integer with a migration step on load.
- All access behind a `ProgressRepository`. If the data outgrows a JSON file, swap the implementation
  for `drift` (SQLite) without touching callers.

---

## 3. Sudoku

A child on a phone and a child on a PC must see the same puzzle for the same day, with no server. So
the puzzle is derived from a number, not from ambient randomness.

### 3.1 Hand-rolled PRNG

Dart's `dart:math` `Random(seed)` is **not** guaranteed to produce the same sequence across Dart
versions. If it changes, every previously generated puzzle changes with it, which silently invalidates
saved progress: the save file stores puzzle IDs, not grids, so a solved puzzle would come back as a
different unsolved one.

The PRNG is implemented in-repo instead, and frozen once written. **Xoshiro128+**, built in phase 2:

```dart
// packages/puzzle_engine/lib/src/rng.dart — not exported from the package
class Rng {
  Rng(int seed);                 // four 32-bit words, seeded by SplitMix32 expansion
  int nextUint32();              // the raw step
  int nextInt(int bound);        // 1 <= bound <= 2^32, unbiased by rejection
  void shuffle<T>(List<T> list); // Fisher-Yates, descending
}
```

Three things differ from the two-word sketch this section first carried, each for a reason recorded
in `PLAN-phase-2.md` §4.1. Four 32-bit words give a 2^128−1 period for the same twenty lines, and are
natively 32-bit so nothing needs splitting. SplitMix32 avalanches the seed before it reaches the
state, which does the job the "discard eight outputs" loop was there for — and that loop's iteration
count would itself have been a frozen constant. The all-zero-state guard is gone because SplitMix32
is a bijection on 32 bits, so at most one of the four words can be zero and the guard would be a
branch no test could enter.

`nextInt` rejects rather than folds: modulo is biased for bounds that do not divide 2^32, and the
value is frozen either way, so there is no reason to freeze the biased one.

Mask to 32 bits at every step. JavaScript numbers only hold 53 bits exactly, so unmasked 64-bit
arithmetic would diverge if a web target is ever added. `test/rng_test.dart` and `test/hash_test.dart`
run under `dart test -p chrome` in CI, which is what checks it.

### 3.2 Puzzle identity

```
id   = "sudoku:9x9:hard:412"
seed = fnv1a32(id)          // hand-rolled hash in the engine, frozen like the PRNG
```

Two ways to reach a puzzle:

- **By date.** `index = daysSince(2026-01-01, UTC)` gives one daily puzzle per size per difficulty.
  UTC, so crossing a timezone does not skip or repeat a day.
- **By index.** An endless numbered list. Puzzle 412 is the same grid on every platform, and next
  year.

### 3.3 Sizes

| Size | Digits | Box shape | Cells |
|---|---|---|---|
| 9x9 | 1–9 | 3 rows x 3 cols | 81 |
| 6x6 | 1–6 | 2 rows x 3 cols | 36 |

The engine is size-generic — one `SudokuSpec` rather than two near-duplicate implementations, so 4x4
and 12x12 cost nothing later. It holds **the box shape only**, `SudokuSpec { boxRows, boxCols }`,
rather than the four fields this section first named: rows and columns are `boxRows * boxCols`, so
storing all four is storing a record that can be built inconsistent. Deriving them removes that state
instead of validating it away.

Only `9x9` and `6x6` are named, because those are the sizes a puzzle ID can spell — an unsupported
size is refused when the ID is parsed rather than reaching a solver that would handle it perfectly
well.

### 3.4 Generation

Three stages. Every ordering decision draws from `Rng`; nothing iterates a `Set` or `Map`, whose
order is not guaranteed.

**Grow.** Backtracking fill, trying digits in `Rng`-shuffled order. A valid complete grid always
exists, so this never fails, it only backtracks.

**Dig.** Shuffle the cell list with `Rng` and walk it, removing one digit at a time. After each
removal, count solutions but **stop counting at 2** — the question is only whether the solution is
still unique, not how many exist. Unique, keep the hole; otherwise restore the digit.

**Judge.** Do not infer difficulty from clue count; it correlates poorly. Judge by which human
techniques a solver needs:

| Tier | Techniques required | Label |
|---|---|---|
| T1 | Naked single, hidden single | Easy |
| T2 | + naked/hidden pair, pointing pair, box-line reduction | Medium |
| T3 | + triples, X-wing, XY-wing | Hard |
| T4 | Needs guessing or deep chains | Expert |

The XY-wing is in T3 because measurement in phase 2 showed T3 is otherwise
almost empty: without it, a grid that singles and pairs cannot finish nearly
always needs guessing as well, and Hard was reachable about once in a hundred
attempts. See `PLAN-phase-2.md` §4.7.

Run the technique solver in tier order; the highest tier it must reach is the puzzle's difficulty. If
the result misses the requested tier, discard it, advance a sub-counter on the seed and regenerate,
**up to 250 attempts** — 40 when this section was written, and raised in phase 2 because the hit rate
is a property of Sudoku rather than of the code: at 40, 6x6 Hard widened 40 times in 50. On the last
failure the generator keeps the closest attempt it saw rather than widening by a fixed notch, and says
so in `widened` on the result. Nothing throws; never surface a generation failure to a child.

Two more things the dig learned in phase 2, both in `PLAN-phase-2.md` §4.7. It refuses a hole that
would push the grid past the tier asked for and carries on with the next cell, because without that
9x9 Hard came out Expert 30 times in 50. And it passes the clue-count floor while the grid is still
too easy, stopping only once the tier is reached, because a grid that is still Medium at 26 clues is
often the Hard puzzle that was wanted three holes later.

Clue counts serve only as guard rails:

| | 9x9 | 6x6 |
|---|---|---|
| Easy | 36–45 | 18–24 |
| Medium | 28–35 | 12–14 |
| Hard | 24–29 | 9–12 |
| Expert | 22–25 | — |

These bands were measured in phase 2 rather than estimated, and several moved: a 9x9 grid reaches T3
at 24 or 25 clues far more often than at 26, and every 6x6 tier lives well below where this table
first put it. The generator digs towards the band floor and stops there once the tier is reached, so
the floor is where puzzles land.

6x6 has too little room for a genuine Expert tier, so it ships Easy, Medium and Hard only rather than
mislabelling a Hard puzzle. It has too little room for a technique-defined Medium either: needing a
pair and nothing more is about one dug 6x6 in three hundred, so **6x6 Medium is defined by sparseness
instead** — the same T1 techniques over 12 clues rather than 18 — and 6x6 Hard is the tier that asks
for anything beyond singles. This is the only place where a label is not purely a statement about
technique, and it is confined to the size that cannot express one.

### 3.5 Performance

Uniqueness checking dominates. Targets:

- 9x9 Easy and Medium: under 100 ms
- 9x9 Hard and Expert: under 400 ms
- 6x6: under 30 ms

**Measured in phase 2, and met at the median on every combination** —
`packages/puzzle_engine/tool/benchmark.dart` prints the table and CI fails at three times a target.
On the development container, medians were 1.0 ms for 9x9 Easy, 28.2 ms Medium, 65.3 ms Hard and
24.0 ms Expert; 0.3 ms for 6x6 Easy, 0.2 ms for Medium and 11.7 ms for 6x6 Hard. The tail is where the
targets are read generously: 9x9 Medium's p95 is 138 ms against a 100 ms target and 6x6 Hard's is
54 ms against 30 ms, because a retry costs a whole attempt and some seeds need several. That is
answered by the cache and the pre-warm below rather than by moving the numbers — a puzzle is
generated once and then read from the save file.

To hit them:

- Bitmask candidates — one integer per row, column and box, using `&`, `|` and popcount rather than
  a `Set<int>` per cell.
- Generate inside an `Isolate` via `compute()`, so the raster thread never blocks.
- Cache generated puzzles in the save file (`puzzleCache`, most recent ~30) for instant revisits.
- Pre-warm: start generating the day's puzzle in the background when the Sudoku menu opens.

### 3.6 Determinism tests

The most important tests in the repository.

```
test/golden/sudoku_9x9_easy.golden     # generatorVersion header + 100 lines
test/golden/sudoku_9x9_medium.golden   # index clueCount tier widened clues
...                                    # one file per size x difficulty
```

For indices 0–99, generate and compare against the golden file. Any change to `Rng`, the hash or
generator ordering turns CI red. When such a change is intentional, bump `generatorVersion` and keep
the old generator reachable behind that switch so existing saves stay valid.

**Each line holds the clue string verbatim, not the sha256 this section first specified.** A hash
would mean a `crypto` dependency in a package that has none, and its failure says "the hash differs"
where a clue string says which puzzles changed. The seven files come to 76 KB, which is the whole of
what that costs. Regeneration is `dart run tool/regen_goldens.dart`, and nothing prevents it being
run to turn a red build green: the control is that the diff names every puzzle that moved, which is a
review control and is written down as one (`PLAN-phase-2.md` §4.8).

Also test:

- Every generated puzzle has exactly one solution (brute-force count == 1).
- The assigned tier matches what the technique solver reports (round trip).
- 6x6 boxes are 2 rows x 3 cols, not 3 x 2.
- The same seed produces byte-identical output across runs. Across *isolates* is not tested and needs
  no test: the engine holds no mutable top-level state, so an isolate is another process's worth of
  the same pure function — the cross-run half is what the goldens already prove.
- Fuzz 2000 puzzles across the seven size-and-difficulty combinations: no crashes, no non-termination,
  and none over 2 s. `FUZZ_SEEDS` sets the count; CI and `tool/verify.sh` both set 2000.

### 3.7 Sudoku UI

- The grid scales to fit, with thick box borders and thin cell borders.
- Tap a cell to select; a large number pad sits below the grid, within thumb reach.
- **Pencil mode** toggle for corner notes.
- **Undo / redo** with a deep stack, capped at 300 moves so that a pencil-mark spree cannot grow the
  save without bound.
- Mistake feedback with two modes: flag immediately (default for children) or only at completion. It
  is `Profile.mistakeFeedback`, per profile rather than per device (§5.2): a younger sibling wants to
  be told at once and an older one may not.
- Highlight the selected digit everywhere, and soft-highlight its row, column and box.
- **Hint** reveals one cell the technique solver can prove, through the engine's `nextPlacement`. The
  exported `nextStep` returns an elimination as readily as a placement, and "4 is ruled out of three
  cells" is not a hint for a six-year-old. Two cases sit either side of it: a board that already holds
  a wrong digit gets that cell pointed at instead, and an Expert board that technique cannot finish
  falls back to the emptiest cell of the stored solution. Hints are counted; the puzzle still counts
  as solved but does not earn a clean-win star. Pointing at a mistake is free, because it gives
  nothing away.
- **Auto-save every move**, so closing the app mid-puzzle and returning later restores the exact
  board. The clock is the exception: it is written when it stops rather than as it moves — on a move,
  on the app leaving the foreground, and on the screen being popped — because a puzzle left open
  would otherwise cost a write a second.
- The timer is visible but small, and can be switched off in settings. It runs either way: a child
  who hid it has not asked to stop being timed.
- Completion shows confetti, honouring the reduced-motion setting. **Playing the sound is phase 5**:
  it needs an audio dependency, and a dependency three phases early is one carried through every
  intervening review (`PLAN-phase-3.md` §2). The fanfare itself is already in the tree — see phase 5
  below, and `app/assets/audio/README.md` for why the placement tick says nothing about whether the
  digit was right.

---

## 4. Arcade

### 4.1 Space Invaders

A Flame `FlameGame` driven on a fixed logic step of 1/120 s, so a 60 Hz phone and a 144 Hz PC play
at the same speed. As built the accumulator keeps a running total of frame time and a count of the
steps already taken from it, rather than subtracting a leftover each frame: the subtractive form
rounds two frame rates to different remainders at exactly the point their totals should agree, which
is the bug `app/test/features/arcade/invaders/invaders_sim_equivalence_test.dart` was written to
catch. A frame that arrives more than eight steps late has its backlog dropped rather than chased,
and resuming from a pause zeroes the accumulator, because the delta across a pause is not game time.

- The player ship moves left and right along the bottom.
- A 5 x 11 alien block marches sideways; on reaching a wall it drops one row, reverses, and speeds up.
- Aliens fire downward at a seeded rate that climbs with the wave.
- Four bunkers erode where shots hit, modelled as a small block grid.
- Three lives, with a bonus life every 10,000 points.
- Scoring: front-row aliens 10, middle 20, back 30. A UFO passes periodically for 50–300.
- Clearing a wave starts the next one lower and faster, without limit.

Settings for younger players:

- **Easy mode:** slower aliens, fewer rows, five lives, slower alien fire.
- **Auto-fire:** the ship fires on its own, so a small player only has to steer.
- No harsh failure screen — "Good try! Play again?" rather than "GAME OVER".

As built, the simulation is plain Dart under `app/lib/features/arcade/invaders/model/` and holds
every position, timer and counter; the `FlameGame` owns the accumulator and one render pass and
nothing else, which is what makes the fixed-step rule above a test rather than a device impression.
Two details are finer than the list: the wall the block bounces off is the bounding box of its
*surviving* columns, so wiping out an edge column widens the field the formation has left to cross
instead of leaving it turning against an alien that is no longer there; likewise, the block reaching
the player's row is judged against its lowest *surviving* row rather than the wave's original row
count, so thinning out the bottom of the formation buys real room before it reaches the player; and
auto-fire is applied
inside the simulation rather than synthesised by the control pad, because a pad that held FIRE down
for the player would make the cooldown depend on the frame rate. Every number in this section is a
field on `InvadersRules` rather than a literal at a call site (`PLAN-phase-4.md` §4.4), so easy mode
is a second row of that table rather than a branch, and tuning is a diff to one file.

### 4.2 On-screen controls

Large **LEFT**, **RIGHT** and **FIRE** buttons.

- Minimum 56 dp touch targets; 72 dp for all three as built, FIRE included — it is held as
  continuously as the other two are.
- LEFT and RIGHT bottom-left, FIRE bottom-right, swapped as a pair by the profile's `padSide`. It is
  a profile option rather than a device setting: siblings sharing a tablet do not share a hand.
- **Hold to move**, not tap-to-nudge. As built each button is a raw `Listener` — neither
  `GestureDetector` nor Flame's `HudButtonComponent`, because the pad is Flutter widgets beside the
  play field rather than Flame components inside it, which is how the tap-target, safe-area and
  pointer-cancel rules here are enforced by the same code that enforces them on every other screen.
  Three things release a button: pointer-up, pointer-cancel, and a move that leaves its bounds. The
  third is the one Flutter's routing makes easy to miss — a move is delivered to whichever widget
  the pointer went down on, however far it has slid since — and each has a test.
- Support two simultaneous touches, so the player can move and fire at once. Flutter's gesture arena
  can claim the second pointer, which is the reason for the raw `Listener` above; Flame's `MultiTouch`
  detectors are not used, because none of the pad is inside Flame. Each button tracks its own pointer
  id, so a second finger arriving on FIRE cannot release LEFT.
- Respect safe areas. Never place FIRE under the iOS home indicator or the Android gesture bar.
- Never overlap the play field. As built the pad sits in its own band below the field inside a
  `SafeArea` rather than being drawn over it, and is therefore opaque: the semi-transparency this
  section asked for is what an overlay needs, and there is no overlay (`PLAN-phase-4.md` §4.6).

Desktop adds keyboard control: arrows or A/D to move, space to fire, P or Esc to pause. Hide the
on-screen buttons after keyboard input and restore them on the next touch, so a touchscreen PC gets
both. Gamepad support (`gamepads`) comes later, not in the first release.

### 4.3 Score persistence

- Top five scores per game per mode — easy and normal keep separate tables — shown on the game-over
  card and in the menu. The cap is applied at write time within one mode, so a normal-mode score can
  never evict an easy-mode one, and the menu shows the table for whichever mode the toggles currently
  select rather than both: a child playing easy is not shown a table they cannot reach.
- Each entry stores score, wave reached, the date, and which mode it was set in. Not the profile: it
  is the profile that contains the entry, and a second copy is a second thing that can disagree.
- Lifetime counters: games *started*, total aliens destroyed. Started rather than finished, because a
  counter that disagrees with its own name is worse than a slightly generous number.
- A run worth zero points stores nothing. Quitting mid-run stores what the run was worth, because a
  run stopped at 3,000 points is still a run, and the five-cap keeps the junk out.

### 4.4 Later games

Each reuses the same shell and control pad, so the incremental cost is small:

| Game | Controls | Persisted |
|---|---|---|
| Brick Breaker | left / right paddle | High score, level reached |
| Snake | four directions or swipe | High score, longest snake |
| Memory Match | tap a card | Best time per grid size |
| Whack-a-Mole | tap a hole | High score |
| Pong (vs AI) | left / right | Win count |
| 2048 | swipe | Best tile, best score |
| Tic-Tac-Toe | tap | Win / loss / draw counts |

Add one per minor release. Do not build all of them before the first release.

---

## 5. Progress and profiles

### 5.1 Profiles

Several children share one tablet, so profiles are local: a name and an animal avatar, selected from
large buttons at launch. No passwords — nothing here is worth locking. One profile exists by default,
so there is no setup wall.

### 5.2 Save schema

```json
{
  "schemaVersion": 1,
  "generatorVersion": 1,
  "activeProfileId": "p1",
  "settings": {
    "sound": true, "music": false, "haptics": true,
    "showTimer": false, "theme": "day", "reduceMotion": false,
    "allowPhotoImport": true
  },
  "profiles": [{
    "id": "p1", "name": "Ana", "avatar": "fox", "createdAt": "2026-08-11T10:00:00Z",
    "mistakeFeedback": "atCompletion",
    "arcadeEasyMode": true, "arcadeAutoFire": true, "padSide": "left",
    "sudoku": {
      "solved": {
        "sudoku:9x9:easy:0": { "timeMs": 244000, "hints": 0, "mistakes": 2,
                               "solvedAt": "...", "clean": true },
        "sudoku:6x6:easy:3": { "timeMs": 61000, "hints": 1, "mistakes": 0, "clean": false }
      },
      "inProgress": {
        "sudoku:9x9:hard:12": { "grid": "...", "notes": "...", "elapsedMs": 90000,
                                "undoStack": [], "hints": 1 }
      },
      "dailyStreak": { "current": 4, "best": 11, "lastDayIndex": 223 },
      "bestTimeMs": { "9x9:easy": 180000, "9x9:medium": 402000 }
    },
    "arcade": {
      "invaders": { "highScores": [{ "score": 15400, "wave": 7, "at": "...", "easy": false },
                                   { "score": 6200, "wave": 5, "easy": true }],
                    "gamesPlayed": 22, "totalKills": 3110 }
    },
    "draw": { "drawingCount": 7, "lastDrawingId": "d7", "bytesUsed": 4820112 }
  }],
  "puzzleCache": { "sudoku:9x9:hard:12": "…clue string…|…solution…" }
}
```

The save stores puzzle **IDs**, not grids, because ID plus generator reconstructs the puzzle. That
holds the file to a few kilobytes after 500 puzzles, and it is why §3.1 determinism is load-bearing.

`theme` is one of `day`, `night` or `system`, and a new save gets `system` — following the device is
what the rest of a child's tablet already does. The block above shows `day` on purpose: it is copied
verbatim into a decode test, where a value that is not the default proves the field is read rather than
defaulted.

`generatorVersion` is written from the engine's own constant at save time, so a file records which
generator produced the IDs in it instead of being assumed to match the build that opens it. The whole
of `puzzleCache` is dropped when it moves, rather than each entry being keyed by it: a per-entry key
would let a stale entry outlive the generator that made it, and there is nothing in a cache worth a
migration.

`mistakeFeedback` arrived with phase 3 and is one of `immediate` — the default — or `atCompletion`.
It is on the profile rather than in `settings` because it belongs to a child rather than to the
tablet. `PLAN-phase-1.md` §4.2 declared v1 "in full" and missed it, which is recorded here rather than
left as two documents disagreeing: adding an optional field to an existing object is not a shape
change, so `schemaVersion` stays 1 and no migration step exists for it. The block shows
`atCompletion` for the same reason it shows `day`.

`arcadeEasyMode`, `arcadeAutoFire` and `padSide` arrived with phase 4 and sit on the profile for the
same reason `mistakeFeedback` does: they belong to the child playing rather than to the tablet, and
siblings sharing one do not agree about easy mode or about which hand fires. A high-score entry gained
`easy` in the same phase — a flag rather than a second game id (`"invaders:easy"`), so the two lifetime
counters stay single numbers instead of two that would need adding at every read. All four are
optional, defaulting to `false`, `false`, `right` and `false`, so a file written before phase 4 decodes
with nothing lost and `schemaVersion` stays 1; the block above sets the three profile options to
non-defaults for the same reason it shows `day` and `atCompletion`, and carries a second score because
one entry cannot show a per-mode table.

`draw` arrives with phase 8 and holds three numbers, not the drawings. A drawing is one file under
`drawings/<profileId>/` (§6), because §5.2's whole point is a save file of a few kilobytes and one
pencil drawing is tens of them — and because a corrupt file then costs one picture rather than a
child's entire profile. `bytesUsed` is what the 64 MB per-profile budget is checked against when a
drawing is written; keeping the total here rather than measuring the directory means the check costs
no disk read on a cheap tablet. `lastDrawingId` is what the Draw card reopens. Drawing ids are `"d1"`,
`"d2"`, … — a counter, for the same reason profile ids are one: no ambient randomness anywhere in
`lib/`, which `app/test/no_random_test.dart` enforces. All three are optional and default to `0`,
`null` and `0`, so a file written before phase 8 decodes with nothing lost and `schemaVersion` stays
1.

`settings.allowPhotoImport` also arrives with phase 8, defaults to **false**, and gates only the
*import* direction — exporting a drawing to the photo library is always available. It sits in
`settings` rather than on a profile because it is a parental control rather than a child's preference:
the child who would turn it on is the one it exists to gate. The block above shows `true` for the same
reason it shows `day` — a value that is not the default proves the field is read rather than
defaulted.

`settings.music` is the one field in the block above that **nothing reads**, and phase 5 — the phase
that was going to consume it — leaves it that way: there is no music in the app, so a switch for it
would change nothing, and `PLAN-phase-1.md` §4.5's rule against a control that does nothing applies
(`PLAN-phase-5.md` §4.6). It stays in the schema at its `false` default rather than being removed,
because removing it is a shape change to a format whose whole design is that v1 is final, and because
the field is what a later change would need if music is ever wanted. It is still written and read
back, so the decode test over the block above still proves the codec round-trips it.

A `puzzleCache` value is `"<clues>|<solution>"`, not the clue string alone. Immediate mistake feedback
needs the digit that belongs in a cell, and nothing exported from the engine recovers it from the
clues — the solution is already a field on `GeneratedPuzzle`, and caching it costs 81 bytes per puzzle
(`PLAN-phase-3.md` §4.1). The three in-progress strings are opaque to the codec on purpose, so the
board representation can change without changing the save format; §4.4 there is what they mean.

### 5.3 Rules

- Write on every Sudoku move (debounced 500 ms), on game over, and on app pause or close. A finished
  drawing stroke is the same event, debounced the same way (phase 8).
- Read once at startup into memory; every later read is from memory. No disk access inside a game
  loop.
- Never crash on a malformed save. On a parse failure, move the file aside to `save.corrupt.json`,
  start fresh, and tell the child once that the old game could not be found. Losing a high score is
  bad; a boot loop is worse.
- Drawings live outside `save.json`, one file each under `drawings/<profileId>/`, written through the
  same tmp-then-rename helper (§2). `save.json` keeps only the counts — see §5.2's `draw`.
- Export and import the save as a file — the share sheet on mobile, a file picker on desktop. That is
  how a family moves to a new tablet without an account or a server.
- No cloud sync, by design.

---

## 6. Repository layout

```
game-station/
├─ PLAN.md                          # the project plan; PLAN-phase-<n>.md per phase
├─ README.md
├─ LICENSE                          # MIT for code; assets licensed per file
├─ analysis_options.yaml            # strict rules shared by both packages
├─ tool/
│  ├─ check_offline.dart            # the §2 no-network / no-ads / no-tracking guard
│  └─ verify.sh                     # everything CI runs, in the same order
├─ packages/
│  └─ puzzle_engine/                # pure Dart, no Flutter imports
│     ├─ lib/
│     │  ├─ puzzle_engine.dart
│     │  └─ src/
│     │     ├─ generator_version.dart  # the version a save records with its puzzle ids
│     │     ├─ rng.dart             # hand-rolled PRNG, frozen once written
│     │     ├─ hash.dart            # fnv1a
│     │     ├─ sudoku_spec.dart     # 9x9 / 6x6 shape
│     │     ├─ sudoku_board.dart    # bitmask board
│     │     ├─ generator.dart       # grow / dig / judge
│     │     ├─ solver.dart          # solution counting, technique tiers
│     │     ├─ techniques/          # singles, pairs, pointing, x-wing…
│     │     └─ puzzle_id.dart       # id <-> seed, date <-> index
│     └─ test/
│        ├─ generator_test.dart
│        ├─ solver_test.dart
│        ├─ determinism_test.dart
│        └─ golden/*.golden
└─ app/
   ├─ lib/
   │  ├─ main.dart
   │  ├─ app.dart                   # MaterialApp, theme mode, onGenerateRoute table
   │  ├─ routes.dart                # route names, importable without the app root
   │  ├─ core/
   │  │  ├─ storage/                # ProgressRepository, atomic write, migrations
   │  │  ├─ audio/                  # minisound wrapper, mute-aware (PLAN-phase-5.md §4.2)
   │  │  ├─ haptics.dart            # HapticFeedback, mobile-gated, settings-gated
   │  │  └─ ui/                     # BigButton, ScreenScaffold, design tokens, avatars, layout
   │  ├─ features/
   │  │  ├─ home/
   │  │  ├─ profiles/
   │  │  ├─ settings/
   │  │  ├─ sudoku/                 # grid widget, keypad, controller
   │  │  ├─ arcade/
   │  │     ├─ arcade_menu_screen.dart   # the game card, the three toggles, the top five
   │  │     ├─ shared/
   │  │     │  ├─ arcade_controller.dart # what GameShell drives, and the HUD it draws
   │  │     │  ├─ arcade_result.dart     # what one finished run reports to storage
   │  │     │  ├─ game_rng.dart          # the arcade's seeded PRNG, clock-seeded per run
   │  │     │  ├─ game_shell.dart        # HUD, pause, quit confirmation, game-over card
   │  │     │  ├─ on_screen_pad.dart     # LEFT / RIGHT / FIRE over raw Listeners
   │  │     │  └─ pad_input.dart         # one value type for the pad and the keyboard
   │  │     └─ invaders/
   │  │        ├─ invaders_game.dart     # the accumulator and one render pass, no state
   │  │        ├─ invaders_screen.dart   # builds the run, hands it to GameShell
   │  │        └─ model/                 # the simulation, its tuning table, the sprites
   │  │  └─ draw/                   # phase 8 (PLAN-phase-8.md §5)
   │  │     ├─ model/               # Stroke, Drawing, DrawingController — no widgets
   │  │     ├─ data/                # codec, drawings/<id>/, PNG export, the two platform edges
   │  │     └─ ui/                  # canvas painter, tool row, the gallery grid
   ├─ assets/{fonts,images,audio}/  # bundled, never fetched; licensed per file
   ├─ test/                         # widget tests
   ├─ integration_test/             # on-device smoke tests, from phases 3 and 4
   └─ pubspec.yaml
```

`puzzle_engine` is a separate pure-Dart package so its tests run in about a second with no emulator
and no Flutter bindings, which makes ten thousand fuzz seeds cheap. It also keeps generation logic
from entangling with rendering code.

**Decided in phase 0: plain path dependencies, no melos.** Melos earns its keep at five or six
packages with interdependent versioning; two packages and one path dependency do not need a tool to
manage them. `tool/verify.sh` covers the one thing melos would have provided — running the same
commands over both packages in one go. Adding melos later is a small change if a third package
appears.

---

## 7. Phases

Estimates assume one developer working part time.

### Phase 0 — groundwork (1–2 days) — done

- `flutter create` the app, `dart create` the engine package, wire the path dependency.
- Strict `analysis_options.yaml`: `strict-casts`, `strict-raw-types`, no implicit dynamic.
- CI: analyze and test on push. `.gitignore`. License choice (MIT for code, CC0/CC-BY for art).
- Add the no-network CI grep guard from §2.
- **Done when:** an empty app launches on an Android emulator, an iOS simulator and one desktop
  target, with CI green.

The guard grew past a grep into `tool/check_offline.dart`, which also audits the resolved dependency
graph, the release manifest and the macOS entitlements — see §2. Comments are stripped before the URL
scan, so a link in a doc comment passes while the same text in a string literal fails.

### Phase 1 — app skeleton (3–4 days) — done

- Router and a home screen with two large cards: Sudoku and Arcade.
- Design tokens for colour, spacing and type scale. Day and night themes. Large default tap targets.
- `ProgressRepository`: atomic JSON writes, schema v1, migration hook, corrupt-file recovery.
- Profile picker, plus create, rename and delete.
- Settings: sound, haptics, timer visibility, theme, reduced motion.
- **Done when:** killing and reopening the app preserves the profile and settings on all six targets.

Planned as seven pull requests in [`PLAN-phase-1.md`](PLAN-phase-1.md), which stays as the record of
why each piece is shaped the way it is — around thirty comments in `app/lib` and `app/test` cite its
section numbers.

**Verified on Android only.** On a physical Android device, the app runs and progress survives a
force-quit. Offline behaviour needs no manual pass there: the package requests no `INTERNET`
permission, so the OS blocks the network whether or not the device is in airplane mode. iOS, Windows,
macOS and Linux compile in CI but were not run on a device, so the six-target half of the
done-criterion above is *not* met. It is carried into §9 rather than implied by silence — nothing in
phase 1 is platform-specific except the directory `path_provider` returns and the `rename` in the
atomic write, but "probably fine" is not a check. A tablet form factor was not checked separately
either; tablet layout is phase 5 work.

What differed from the plan, decided while building it:

- **The theme choice gained a `system` value**, now the default, and §5.2 above records it. Following
  the device is what the rest of a child's tablet already does.
- **Reduced motion is added into the ambient `MediaQuery` rather than or-ed at each reading site**, so
  a phase-4 animation asks one question and gets both the stored answer and the device's. It also
  switches off the screen-to-screen slide, which is the only animation phase 1 has — otherwise the
  setting would have been a promise until phase 4.
- **`flutter_riverpod` is pinned to `^2.6.1`.** Riverpod 3 declares `package:test` as a runtime
  dependency, which puts `web_socket_channel` in the app's resolved graph, and `tool/check_offline.dart`
  reads the graph rather than trusting that nothing calls it. Narrowing that check to admit a state
  library is the wrong way round.
- **The profile picker is one scrolling column, not a grid.** A `GridView` tile has a fixed aspect
  ratio, so at 200% text scale a wrapped name is clipped in a box that cannot grow.
- **`main` falls back to an in-memory store when `path_provider` cannot resolve a directory.** The app
  then runs and forgets rather than failing to start, which is the §8 boot-loop rule applied to the
  one call that happens before any UI exists.
- Route names live in `app/lib/routes.dart` rather than in `app.dart`, so a screen can name a route
  without importing the app root, which imports every screen.

### Phase 2 — Sudoku engine (5–7 days) — done

The critical path, and planned as seven pull requests in [`PLAN-phase-2.md`](PLAN-phase-2.md) as phase
1 had: the determinism rules in §3.1 and §3.6 are easier to hold to when the order they are built in
is written down first. That file stays as the record of why each piece of the engine is shaped the way
it is — the code cites its section numbers — and §3.1, §3.3, §3.4, §3.5 and §3.6 above now say what
was built rather than what was sketched.

- `Rng`, `fnv1a`, `SudokuSpec`, bitmask `SudokuBoard`.
- Solver: brute-force count-to-2, plus the technique-tier solver.
- Generator: grow, dig, judge, with the retry loop.
- `PuzzleId`: parse and build IDs, date-to-index, ID-to-seed.
- The full test set from §3.6, including golden files.
- A benchmark script meeting the §3.5 targets.
- **Done when:** `dart test` is green, goldens are locked, the 2000-seed fuzz is clean, and the
  benchmark is within target.

**Met in full, and checked rather than asserted.** The engine suite is green; seven golden files hold
indices 0–99 of every size and label and are compared on every run; the 2000-puzzle fuzz is clean with
no generate over 2 s; and the benchmark is inside every §3.5 target at the median, with CI failing at
three times one. The phase ships no user-visible behaviour and touches nothing in `app/`, so there is
nothing to check on a device — the six-target gap carried out of phase 1 is unchanged and still sits
in §9.

What differed from the plan, decided while building it:

- **The XY-wing had to be added to T3**, which §3.4 records. Without it a grid that singles and pairs
  cannot finish nearly always needs guessing too, so Hard was reachable about once in a hundred
  attempts and nearly every "Hard" puzzle was a widened Medium or Expert. It is the one place where
  the technique list decides which puzzles exist rather than only what they are called.
- **6x6 Medium is defined by sparseness, not by technique** (§3.4). A 6x6 that needs a pair and
  nothing more is about one dug grid in three hundred.
- **The retry budget is 250 attempts, not 40**, and the generator settles for its closest attempt
  rather than widening by a notch (§3.4).
- **The clue bands moved to where puzzles actually land** (§3.4), and the dig aims at the tier rather
  than at a clue count.
- **Goldens store the clue string, not a sha256** (§3.6), and **`SudokuSpec` holds the box shape
  only** (§3.3).
- **The engine suite costs about 25 s rather than the 10 s `PLAN-phase-2.md` §1 budgeted**, because
  comparing 700 golden puzzles means generating them. `tool/verify.sh` is about two minutes with the
  benchmark in it, and `AGENTS.md` says so.
- **`Difficulty` is one enum for both the label and the tier**, so no table pairs them and neither can
  fall out of step with the other.
- **Nothing in `app/lib` imports the engine yet.** `nextStep()` exists for phase 3's hints with a test
  and no caller, which is where the phase boundary was drawn.

### Phase 3 — Sudoku UI (5–7 days) — done

- Size and difficulty pickers showing solved state and best times.
- A daily-puzzle card with the current streak.
- The grid widget, driving 9x9 and 6x6 from one implementation; keypad, pencil mode, undo/redo,
  highlighting.
- Hints via the technique solver. Both mistake-feedback modes.
- Mid-puzzle auto-save and resume. Completion screen.
- Generation in an isolate, with a spinner and pre-warming.
- **Done when:** 9x9 and 6x6 can be solved end to end; a force-quit mid-puzzle resumes the exact
  board; solved state persists across a restart.

Planned as nine pull requests in [`PLAN-phase-3.md`](PLAN-phase-3.md), as phases 1 and 2 were. That
file stays as the record of why each piece of `app/lib/features/sudoku` is shaped the way it is — the
code cites its section numbers — and §3.7 and §5.2 above now say what was built rather than what was
sketched. It also holds the two formats this phase froze, the `puzzleCache` value and the in-progress
board encoding, because both become a save migration now that a child's file can hold them.

**Met by the suite that runs on every commit; not yet met on hardware, which is stated rather than
implied.** Each clause of the criterion has a check: a widget test solves a 6x6 end to end by tapping
and asserts the `SolvedPuzzle` it stored; another plays a board, relaunches the app over the encoded
save alone and compares every cell, every note mask, the elapsed time, the hint count and the undo
stack; and the solved state's round trip through `save.json` is the storage suite's. What none of them
involves is a device. `app/integration_test/sudoku_smoke_test.dart` is the run that closes that gap —
a real 9x9 Medium generated on a real isolate, played, backgrounded, and read back out of a real
`save.json` — and CI has no emulator to run it on, so it is a check somebody performs rather than one
a merge waits for. `AGENTS.md` says how; an emulator job stays §9's open question. The three §9 lines
that need hardware are therefore still unticked, along with the six-target gap carried out of phase 1.

**"9x9 and 6x6 can be solved end to end" is checked by tapping at 6x6 and by construction at 9x9.**
Nothing in the grid, the keypad or the session branches on size — the box shape comes from
`SudokuSpec`, and both sizes have widget tests over the same code — so filling eighty-one cells one
tap at a time in the suite would spend most of its budget re-exercising what the 6x6 already covers.
The 9x9 is played through on the device instead, which is where the integration test plays one.

What differed from the plan, decided while building it:

- **`mistakeFeedback` is a field on `Profile`, not on `AppSettings`**, and §5.2 above records it. It
  belongs to a child rather than to the tablet: siblings sharing one do not agree about being told.
  It is additive, so `schemaVersion` stays 1 — `PLAN-phase-1.md` §4.2 declared v1 "in full" and
  missed it, which §5.2 now says rather than leaving two documents disagreeing.
- **A `puzzleCache` value holds the solution as well as the clues** (§5.2). Immediate mistake feedback
  needs the digit that belongs in a cell, and nothing the engine exports recovers it from the clues.
- **The play screen is the one screen that does not use `ScreenScaffold`**, and the exception was
  measured rather than felt: on a 360x640 phone with a notch and a gesture bar, that frame leaves a
  166 dp board against a compact header's 194 dp, and at 200% text scale 14 dp against 170 dp. The
  first of those is a board no child can play.
- **The last save of a puzzle belongs to the pop, not to `dispose`.** A screen is disposed part-way
  through a build and Riverpod refuses a provider mutation made during one, so writing from `dispose`
  turned the back arrow into an assertion failure in debug — on an ordinary tap, mid-puzzle.
- **The continue card offers the board with the most time on its clock**, not the one played last: a
  save cannot say which that was, because `PuzzleInProgress` carries no timestamp, and widening the
  schema for one card was the wrong trade.
- **9x9 Expert is offered, last**, answering `PLAN-phase-2.md` §9. The engine makes it either way, and
  a child who wants something harder than Hard and finds nothing is a worse outcome than one who
  tries Expert and backs out. Removing it later is a line in `difficultiesFor`.
- **The engine gained exactly one function, `nextPlacement`,** taken first and alone so that "no
  golden file changed" was a reviewable claim rather than a line in a large diff. It touches no
  generation path, `generatorVersion` is still 1, and no save migration exists for this phase.
- **The app suite costs about 25 s, not the 15 s `PLAN-phase-3.md` §1 budgeted.** The fake puzzle
  source did its job — nothing generates in a widget test — but the whole-app tests, each launching
  the app over its own store, are the bulk of it, and they are the ones the resume criterion needs.

### Phase 4 — arcade shell and Space Invaders (5–7 days) — done, except on a 144 Hz desktop

- `GameShell`: pause, resume, quit confirmation, lives and score HUD, game-over card with high
  scores.
- `OnScreenPad`: LEFT / RIGHT / FIRE with multi-touch, hold-to-move, pointer-cancel handling, safe
  areas and the keyboard mirror.
- Invaders: player, alien block, projectiles both ways, bunker erosion, UFO, wave ramp, easy mode,
  auto-fire.
- Fixed-step loop verified on both a slow phone and a 144 Hz desktop.
- High scores persisted per profile.
- **Done when:** ten minutes of play on phone and desktop shows no jank and no stuck ship, and scores
  survive a restart.

Planned as eight pull requests in [`PLAN-phase-4.md`](PLAN-phase-4.md), as phases 1, 2 and 3 were.
Two decisions there are worth knowing before reading this section as built: the simulation is pure
Dart holding all the state, with Flame supplying the loop, the viewport and the widget bridge and
owning nothing, which is what makes the fixed-step rule above a test rather than a device
impression; and the on-screen pad is Flutter widgets over raw `Listener`s beside the play field
rather than Flame components inside it, which is how §4.2's safe-area, tap-target and pointer-cancel
rules are enforced by the same code that enforces them everywhere else in the app. §4.1, §4.2, §4.3
and §5.2 above have been reconciled with what shipped, and §6's tree now names the files.

**The done-criterion, quoted with its result:** *"ten minutes of play on phone and desktop shows no
jank and no stuck ship, and scores survive a restart."*

- **Phone and tablet: met.** Ten minutes of play on a Pixel 6 and on a Fire HD tablet showed no jank
  and no stuck ship, and high scores survived a relaunch on both.
- **Desktop: not met, because it was not attempted.** No 144 Hz display has run this build. The
  clause is left standing rather than quietly reworded, and three things stay open with it:
  `PLAN-phase-4.md` §8's 144 Hz line, its §9 question of whether 1/120 s is the right fixed step —
  the device pass was the only thing that was going to answer it — and the frame-budget measurement
  its §7 deferred to this pull request, which a phone and a tablet answer for a phone and a tablet
  and not for a display running at more than twice their rate. What *is* checked on every commit is
  the arithmetic underneath: `invaders_sim_equivalence_test.dart` compares ten seconds of state
  between a 60 Hz and a 144 Hz frame sequence, and it was seen failing against a `dt`-stepped
  simulation before it was trusted. That is evidence about the accumulator, not about a display, and
  the two are not interchangeable.
- **Scores survive a restart: met**, on the device and in the suite — the widget test plays a run to
  game over, relaunches over the same store and finds the score on the card, and the storage suite
  round-trips the entry through `save.json`.

**PR 8's tuning pass produced no diff.** `PLAN-phase-4.md` §6 expected the numbers in
`invaders_rules.dart` to move after ten minutes of play, and on the hardware that was played there
was nothing to move them for. Moving them on the strength of a machine nobody played would be
inventing the evidence the pass exists to collect, so the table still holds its starting values and
`PLAN-phase-4.md` §9's "are the §4.1 starting numbers playable for a six-year-old" is still open —
as is §9's line below about a six-year-old playing unaided.

**`app/integration_test/invaders_smoke_test.dart` has run headless, not on hardware.** It plays a
run through two simultaneous pointers on the pad, backgrounds and foregrounds the app, quits, and
reads the score back out of a real `save.json`; `-d flutter-tester` passes it in about eight seconds.
`AGENTS.md` says how to run it on a device and records that CI still does not — an emulator job stays
§9's open question, unchanged from phase 3 and accepted again.

What differed from the plan, decided while building it:

- **The accumulator keeps a running total, not a subtractive leftover** (§4.1). The form the phase
  plan sketched rounds 60 Hz and 144 Hz to different remainders at exactly the point their totals
  should agree; the equivalence test found it, which is the only reason the difference is a line
  here rather than a bug on a desktop.
- **The renderer is a child `Component` in `world`, not an override of `FlameGame.render`.** The
  camera's `FixedResolutionViewport` transform then applies to it for free, instead of being
  reimplemented by hand around a manually-drawn canvas — and that transform is what §4.1's "a phone
  and a tablet run the same game" actually rests on.
- **The pad is opaque, in a band of its own below the field** (§4.2). §4.2 asked for
  semi-transparent buttons, which is what an overlay drawn over the play field needs; a pad that has
  its own band does not overlap anything to see through.
- **FIRE is 72 dp, like LEFT and RIGHT** (§4.2). It is held as continuously as they are, and the
  56 dp floor is for controls that are tapped.
- **`GameShell` does not resume when the app returns to the foreground.** It pauses on the way out
  the way any screen would, and comes back to the paused card: a shooter that started moving aliens
  again the instant a tablet unlocked would drop a child back into a run before they had looked at
  the screen. *Resume* is then the same explicit tap it is after the pause button.
- **Two defects found by playing landed as their own pull requests rather than waiting for this
  one.** The alien block's wall check used its nominal eleven-column width, so wiping out an edge
  column did not let the formation march any further; and every back control in the app called
  `Navigator.pop()` without rechecking `canPop()` at the moment of the pop, which a confirm dialog
  resolving after the stack had changed underneath it could turn into a blank screen. Both are
  behaviour a reader of this phase would otherwise have to re-derive from the diff.

### Phase 5 — polish (6–8 days)

Planned as eight pull requests in [`PLAN-phase-5.md`](PLAN-phase-5.md), which carries the design, the
rejected alternatives and the verification checklist. The estimate assumes the same one developer
working part time as the phases above, and is wider than the 4–5 days this entry first carried for
three reasons named there: the audio dependency had to be replaced, its two platform hazards need
guards, and the eleven arcade motifs are a synthesiser session rather than a code change.

- Sound effects, all mutable, ducked when the app backgrounds. **The six Sudoku motifs already
  exist**, ahead of this phase: `tool/audio/generate_motifs.py` synthesises them and
  `app/assets/audio/sudoku/` holds the output (`app/assets/audio/README.md`). Only assets and a
  script landed early, which carries no dependency and no code through an intervening review — what
  remains here is the playback package, the mute-aware wrapper in `lib/core/audio/`, the calls from
  the play screen, and the arcade's own set. Sounds are events out of `SudokuSession` and
  `InvadersSim` rather than calls from the widgets, because the model is what knows whether anything
  happened (`PLAN-phase-5.md` §3.3).
- **`minisound`, not `flutter_soloud`** (§2). Every other audio package resolves `http` into the
  shipped graph, and `minisound_ffi`'s `RECORD_AUDIO` is removed from the merged manifest and checked
  on the built APK. This is the phase's load-bearing decision and its first pull request, so it is
  answered on hardware before anything is built on it.
- **No music, and an arcade sound set instead.** §7 asked for "light music"; there is none, on any
  screen — a loop playing in a room with other people in it is the first thing a parent switches off.
  Invaders gets nine generated sounds: shoot, hit, enemy shoot, enemy hit, enemy move, the special
  enemy's warble and its hit, a wave clear and the bonus life (`PLAN-phase-5.md` §4.1). The enemy-move
  sound is one motif fired once per step of the alien block, so the pulse accelerates as the formation
  thins with no tempo state anywhere — `InvadersSim._currentStepInterval()` already computes it, from
  0.70 s to 0.09 s. The arcade original's four descending notes were drafted and cut: four pitched
  notes in rotation is music by another name (§3.4). `settings.music` therefore gets no control and
  stays at its `false` default (§5.2).
- Haptics on mobile only, through `HapticFeedback`'s three permission-free calls. `vibrate()` and
  `heavyImpact` need `android.permission.VIBRATE` and are banned by a scanner test, so the phase adds
  no permission.
- Accessibility: screen-reader labels on every control, a colourblind-safe palette that never uses
  colour as the only signal, text-scale support, and `reduceMotion` suppressing confetti — the last of
  which phase 1 already built and `Confetti` already honours. The three claims that can be mechanised
  become tests: contrast ratios over the palette, tap-target floors per control, and a sweep that
  pumps every route at 200% text scale.
- Portrait and landscape, with a tablet layout that does not stretch the grid — a 560 dp cap on the
  board, a 640 dp cap on a column of content, and one sweep test over every route at three sizes and
  two text scales, since a `RenderFlex` overflow throws in a widget test.
- **No i18n scaffolding.** `.arb` files and English-first localisation are dropped from this phase:
  no translation is planned, and a pipeline with one locale in it is a build step and an indirection
  bought against a need nobody has. The screens already name their strings as public constants because
  the tests read them, which is the list a future `.arb` would be seeded from.
- **Done when:** an accessibility pass on TalkBack and VoiceOver passes, every screen survives
  rotation, and the sound the phase adds can be silenced by two switches with nothing left playing.

### Phase 6 — release (3–5 days)

- Icon, splash, store artwork and per-platform screenshots. The icon landed early, with the rename to
  Zibo Games: `app/assets/images/` holds the master and the two sizes an Amazon listing asks for, and
  `tool/icon/generate_platform_icons.py` derives every launcher size from the master. Android's
  adaptive icon (foreground, background and monochrome layers at every density, plus the
  `mipmap-anydpi-v26` XML and the background colour resource) also landed early, under
  `app/android/app/src/main/res`; those layers came from the design tool rather than the script above,
  so a new icon means re-exporting them by hand, the same as the master.
- Android, and the **Amazon Appstore is the primary target** rather than Play. That suits what is
  already built: Amazon takes the signed APK the `android-apk` and `android-release` workflows
  produce, so the artifact needs no new build path, and its kids programme rules out ads, tracking
  and purchases — three constraints the app is built around and `tool/check_offline.dart` already
  enforces. Play stays viable as a second listing, which is where the AAB, the Data Safety
  declaration and Teacher Approved belong.
- The Android signing config landed early, out of phase: the CI APK was signed with each runner's own
  debug key, so no build could be installed over the last one without uninstalling and losing the
  save. `app/android/app/build.gradle.kts` now reads `android/key.properties`, and the workflows
  write it from repository secrets — see README.md. What is left here is the store listing and the
  upload, not the key.
- iOS: Kids Category, which **bans** third-party ads and analytics — the app has neither, so it
  qualifies without changes. Requires an Apple Developer account (about $99/year) and a Mac to build.
- Windows: MSIX or a plain zip; Microsoft Store or Steam optional later.
- macOS: notarization, which also needs the developer account.
- Linux: tarball plus Flathub. F-Droid is also viable if the app stays fully FOSS, which is strong
  independent evidence for the no-ads, no-tracking claim.
- **Done when:** the app installs from a real store listing on a real device and plays offline.

### Phase 7 — more games (ongoing)

One game per minor release from the §4.4 table, each reusing `GameShell` and `OnScreenPad`.

### Phase 8 — drawing board (5–7 days)

A third card on the home screen: a blank sheet a child draws on with a finger, four pencil sizes,
twelve colours, an eraser, undo and redo, saved to and loaded from the device photo library. Planned
as seven pull requests in [`PLAN-phase-8.md`](PLAN-phase-8.md), which carries the design, the rejected
alternatives and the verification checklist. The estimate assumes the same one developer working part
time as the phases above, and is wide because one of the seven pull requests is Kotlin and Swift that
CI cannot run and another ends in a device pass.

- **Strokes are data, not pixels.** A drawing is a list of `Stroke`s over a fixed 1600 x 1200 virtual
  sheet — the same trick as §4.1's 224 x 256 field, and for the same reason: a phone and a tablet draw
  the same picture. Undo is then dropping a stroke rather than restoring a bitmap, and export
  rasterises at whatever size the file wants. This is the phase's load-bearing decision; a raster
  canvas would change the save format, the undo model and the export path together.
- Four pencil sizes, twelve colours and an eraser, each a 56 dp round target carrying a 3 dp
  `AppBorders.selected` ring when chosen. Colour-blindness cannot be designed out of a paint box — the
  swatches *are* the content — so what §7's phase-5 rule buys here is that every swatch carries a
  spoken name and that *selection* is signalled by the ring and a size change rather than by colour.
  No control needs a word of text.
- Undo and redo at 72 dp, `AppTapTargets.primary`, greyed rather than hidden when their stack is
  empty. The undo horizon is 50 strokes: older strokes are baked into a cached `ui.Image`, which
  bounds the paint cost and what a repeated tap can undo away in one direction.
- There is no destructive clear. **New sheet** keeps the current drawing in the in-app gallery, so
  nothing a child made needs a confirmation dialog to survive.
- Export rasterises through `dart:ui`'s own PNG encoder — no image package — and hands the bytes to
  `gal` on Android and iOS (§2). On desktop, where there is no photo library, the PNG goes to a
  `Zibo Games` folder under `getDownloadsDirectory()`, and that folder is what the import list reads.
- Import comes through an in-repo `zibo/photos` method channel over Android's `PickVisualMedia` and
  iOS's `PHPickerViewController`, so the OS returns one image and asks for no permission. The picked
  photo becomes a locked backdrop the child draws over; it is downscaled to the virtual sheet on the
  way in, because a phone camera's 12 MP original would cost fifty pencil drawings of disk.
- Import is off until a parent turns it on: `settings.allowPhotoImport`, default false (§5.2).
- **Done when:** on an Android phone and one desktop target, a child draws, changes size and colour,
  erases, undoes and redoes, exports to the photo library and re-imports that image as a backdrop; a
  force-quit mid-drawing reopens the same strokes; a 500-stroke drawing paints within one 60 Hz frame,
  asserted by a test rather than by impression; and `tool/check_offline.dart` is still clean with
  `gal` in the resolved graph.

**Numbered after §4.4's games rather than before them**, and not because it depends on them — it
reuses nothing from `GameShell` and can start the day phase 6 ships. Renumbering is what it avoids:
roughly three hundred citations of this file's section and phase numbers live in code comments and in
the four closed phase plans, and phase 7 is open-ended anyway, so a phase after it is a number rather
than a queue position.

**Release at the end of Phase 6.** Sudoku in two sizes and four tiers plus Space Invaders is a
complete app. Phases 7 and 8 are both minor releases after it. The drawing board waits for two
reasons: §8's feature-creep risk is mitigated by a release line that stays where it was written, and a
photo-library permission is easier to negotiate with a store that has already listed the app than with
one seeing it for the first time. Neither reason is about the design — moving it into 1.0 means moving
the phase between 5 and 6 and moving the release date with it. Nothing in `PLAN-phase-8.md` changes.

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Dart `Random` changes and puzzles drift | High | Own `Rng`, golden tests, `generatorVersion` |
| Integer overflow differs if a web target is added | Medium | Mask to 32 bits from the start |
| Hard/Expert generation stalls the UI | High | Bitmasks, isolate, cache, pre-warm |
| Finger slides off LEFT and the ship never stops | Medium | Handle pointer-cancel; test it |
| Gesture arena claims the second pointer | Medium | Raw `Listener` per button, not `GestureDetector` |
| Game speed tied to frame rate | Medium | Fixed logic step, verified at 60 and 144 Hz |
| Corrupt save causes a boot loop | High | Catch, move aside, start fresh, never crash |
| Behaviour is only ever hand-checked on Android, so a platform-specific bug ships | Medium | CI builds all five platforms on `main`, which catches a compile break but not a behaviour one. The save layer's two platform-sensitive parts are the directory `path_provider` returns and the `rename` in the atomic write; both are exercised by the temp-directory suite, which today runs on the Ubuntu job only — see §9. Force-quitting and reopening is a per-target manual check either way |
| iOS needs a Mac, $99/year and review | Medium | Plan early; Android and desktop can ship first |
| Linux audio flakiness | Low | `minisound` over `miniaudio`, which loads ALSA, PulseAudio or PipeWire at runtime, so a missing backend is a failed `init` rather than a failed link. `AppAudio` catches it and latches silent; audio is optional anyway |
| A dependency's manifest puts a permission in the APK — `minisound_ffi` declares `RECORD_AUDIO` | High | Removed with `tools:node="remove"` in the app's manifest, and proved on the artifact rather than the source: `tool/check_apk_permissions.sh` fails on any `android.permission.*` and CI's `build-android` leg runs it on the release APK. A children's app that asks for the microphone is a listing liability, so this is a red build rather than a review note |
| `minisound` is one maintainer's four packages and stops being maintained | Medium | Reached only through the app's own `AppAudio` interface, so swapping it is one file — but the table in `PLAN-phase-5.md` §3.1 leaves no clean alternative, so the real fallback is an in-repo method channel over `SoundPool` and `AVAudioPlayer` with desktop silent. Front-loaded: phase 5's first pull request puts it on hardware before anything depends on it |
| Kids-category store rules | Low | Already met: no ads, no network, no data collection |
| Feature creep — twenty games, none finished | High | Release line fixed at Phase 6, restated in §7's phase-8 entry where the pressure to move it came from |
| `gal` is one maintainer's package and stops being maintained | Low | It is reached only through the app's own `GalleryExport` interface, so replacing it is the eighty-odd lines of `MediaStore` and `PHPhotoLibrary` code it wraps, in one file. Checked before adopting it: it depends on `flutter` and nothing else, so there is no transitive graph to inherit |
| The photo picker is native code CI cannot run | Medium | It is its own pull request (`PLAN-phase-8.md` §6, PR 6) behind a channel that reports itself unavailable, so the phase ships whole without it if a device pass fails. Everything above the channel is Dart and covered by `flutter test` |
| A child imports a photo nobody meant them to | Medium | The system picker returns one image and takes no library permission; import is off until a parent enables it (§5.2); and nothing can leave the device, which `tool/check_offline.dart` enforces rather than the UI |
| The drawings folder fills a cheap tablet's disk | Medium | A 64 MB budget per profile, checked against §5.2's `bytesUsed` when a drawing is written rather than by measuring the directory when it is read. The gallery then offers a deletion instead of silently dropping the oldest picture. The bound is bytes and not a count because one imported photo costs what fifty pencil drawings do |
| A long drawing janks because every stroke repaints every frame | Medium | Strokes below the 50-stroke undo horizon are baked into a `ui.Image`; a test asserts the painter walks at most 51 strokes on a 500-stroke drawing, so the bound is checked on every commit rather than felt on a device |

---

## 9. Release checklist

- [ ] In airplane mode, every screen works with no errors. *(Android, phase 1.)*
- [ ] Profile and settings survive a force-quit on iOS, Windows, macOS and Linux. Android was checked
      when phase 1 closed; the other four were not, so this is the phase-1 done-criterion finishing
      here rather than being dropped.
- [ ] The storage suite runs on a Windows and a macOS runner, not only on Ubuntu. `File.rename` over
      an existing file is the one part of the save path that can behave differently per platform (§8),
      and the CI jobs for those two targets build without testing today.
- [ ] The built Android APK requests no platform permission at all — in particular no `INTERNET` and
      no `RECORD_AUDIO`, which `minisound_ffi` declares and the app's manifest removes
      (`tool/check_apk_permissions.sh` on the artifact, run by CI's `build-android` leg).
- [ ] The release APK is signed with the key from repository secrets, not the fallback debug key —
      the run summary names which, and a store upload can never change key afterwards.
- [ ] The installed build's settings footer names a version and a build time rather than
      "Development build". The stamp comes from the build command rather than from the source
      (`tool/build_defines.sh`), which is what keeps it from going stale — and also the one way this
      can fail, since an unstamped build is a green build.
- [ ] The daily puzzle is byte-identical on Android, iOS, Windows, macOS and Linux.
- [ ] Golden determinism tests pass in CI.
- [ ] A force-quit mid-puzzle restores the exact board, notes and timer.
- [ ] High scores survive 100 restarts.
- [ ] A six-year-old can play Invaders with the on-screen controls unaided.
- [ ] Simultaneous move and fire works on the cheapest test device.
- [ ] The grid is readable at 200% system text scale, and every other screen is too — the sweep test
      of `PLAN-phase-5.md` §4.8 covers all seven routes, and a real phone confirms the two it cannot
      judge: reachability and whether a child can still see the whole board.
- [ ] Every screen survives rotation, and rotating mid-run keeps the run rather than restarting it.
- [ ] No ad, analytics or HTTP package anywhere in the dependency tree (`dart pub deps` audit).
- [ ] Cold start under two seconds on an old low-end Android device.

---

## 10. Starting order

1. Phase 0: scaffold the app and engine package, CI, and the no-network guard. **Done**, and so are
   phases 1, 2 and 3 — steps 2 and 3 below were phase 2's first two and are done with it.
2. Write `Rng` and `fnv1a`, and write the determinism test **before** the generator, so the sequence
   is locked before anything depends on it. **Done:** the sequence is frozen against literals in
   `rng_test.dart` and against 700 golden puzzles.
3. Write the brute-force solver with count-to-2. The rest of the Sudoku work builds on it. **Done.**

The next work is phase 5, and its plan is [`PLAN-phase-5.md`](PLAN-phase-5.md). Phase 4 is done bar
the 144 Hz desktop pass above, and nothing it built is in phase 5's way: sound, haptics, landscape and
the accessibility pass are all additive to screens that exist. The one thing phase 5 inherits rather
than adds is the desktop clause — a rotation and accessibility pass is another reason to have the app
in front of a desktop display, and running the ten minutes then closes phase 4's criterion without a
phase of its own.

**Phase 5 starts with the dependency, not with a sound**, for the reason phase 8's plan was written
early: which package plays audio is settled by resolving a graph, and the answer changed the phase.
`flutter_soloud` — named in §2 from the first draft of this document — declares `http` at every
version, and so do `audioplayers`, `assets_audio_player` and `soundpool`; `flutter_pcm_sound` is clean
and covers three of the six targets. `minisound` is the one that resolves clean on all six, and it
arrives with an Android manifest declaring `RECORD_AUDIO`. So the phase's first pull request adds the
package, removes that permission and proves both on a built APK before a line of the audio wrapper
exists: if either check fails, what changes is the phase's shape rather than its schedule.

**Phase 8's plan is written ahead of its turn**, which none of the others were. The question it had to
answer was which dependency reads the photo library, and that is answered by resolving a graph rather
than by reasoning: `image_picker` and `file_selector` both pull `http` into what ships and would fail
`tool/check_offline.dart`, `photo_manager` is clean but wants the whole album, and `gal` adds one
package and no transitive one. Knowing that now cost an afternoon; finding it at the phase would have
cost the phase's shape.

This section previously said phase 4 starts with `GameShell` rather than with Invaders, on the
grounds that pause, quit and the game-over card are what every later game reuses and that building
them under a real game is how they end up shaped by one. `PLAN-phase-4.md` §10 keeps the second half
and inverts the first: the shell is built at its PR 6, under a game that already runs, because a
shell written before the game it wraps is shaped by a guess rather than by one. The phase starts with
the save fields and the seeded RNG instead — both are what everything above stores and draws through,
and both are answers a child's file will hold.

Space Invaders is the easier and more enjoyable half, so it makes a better reward than a warm-up.
