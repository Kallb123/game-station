# Game Station — Implementation Plan

A local, offline, ad-free games app for children. Sudoku (9x9 and 6x6, deterministic from a date or
index) plus retro arcade games driven by on-screen controls, with progress that persists across
sessions.

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
| Audio | `flutter_soloud` | Low latency, works on all six targets including Linux |
| Haptics | `HapticFeedback` | Built in. Guard by platform check; mobile only |
| Test | `flutter_test`, `test`, `integration_test` | Built in |
| Lint | `flutter_lints` plus strict analyzer options | Built in |

Banned dependencies:

- No ad SDKs — no `google_mobile_ads` or equivalent.
- No `firebase_*`, no `sentry`, no analytics or crash reporting.
- No `google_fonts` — it fetches fonts over the network at runtime. Bundle font files in
  `assets/fonts/` instead.
- No `http`, no `dio`. If no networking code exists, no networking can leak.

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

Implement the PRNG in-repo instead — `Xoshiro128+` or `PCG32`, roughly twenty lines of integer
arithmetic, frozen once written.

```dart
// packages/puzzle_engine/lib/src/rng.dart
class Rng {
  int _s0, _s1;
  Rng(int seed) : _s0 = seed ^ 0x9E3779B9, _s1 = (seed * 0x85EBCA6B) & 0xFFFFFFFF {
    if (_s0 == 0 && _s1 == 0) _s0 = 1;      // all-zero state never advances
    for (var i = 0; i < 8; i++) nextInt(2); // discard early low-entropy output
  }
  int nextInt(int bound) { /* xorshift128, mask to 32 bit, mod bound */ }
  void shuffle<T>(List<T> list) { /* Fisher-Yates using nextInt */ }
}
```

Mask to 32 bits at every step. JavaScript numbers only hold 53 bits exactly, so unmasked 64-bit
arithmetic would diverge if a web target is ever added.

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

The engine is size-generic — one `SudokuSpec { rows, cols, boxRows, boxCols }` rather than two
near-duplicate implementations. 4x4 and 12x12 then cost nothing.

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
| T3 | + triples, X-wing | Hard |
| T4 | Needs guessing or deep chains | Expert |

Run the technique solver in tier order; the highest tier it must reach is the puzzle's difficulty. If
the result misses the requested tier, discard it, advance a sub-counter on the seed and regenerate,
up to about 40 attempts. On 40 failures, widen the accepted tier by one notch and log a warning —
never surface a generation failure to a child.

Clue counts serve only as guard rails:

| | 9x9 | 6x6 |
|---|---|---|
| Easy | 36–45 | 18–24 |
| Medium | 30–35 | 15–17 |
| Hard | 26–29 | 12–14 |
| Expert | 22–25 | 10–11 |

6x6 has too little room for a genuine Expert tier, so it ships Easy, Medium and Hard only rather than
mislabelling a Hard puzzle.

### 3.5 Performance

Uniqueness checking dominates. Targets:

- 9x9 Easy and Medium: under 100 ms
- 9x9 Hard and Expert: under 400 ms
- 6x6: under 30 ms

To hit them:

- Bitmask candidates — one integer per row, column and box, using `&`, `|` and popcount rather than
  a `Set<int>` per cell.
- Generate inside an `Isolate` via `compute()`, so the raster thread never blocks.
- Cache generated puzzles in the save file (`puzzleCache`, most recent ~30) for instant revisits.
- Pre-warm: start generating the day's puzzle in the background when the Sudoku menu opens.

### 3.6 Determinism tests

The most important tests in the repository.

```
test/golden/sudoku_9x9_easy.golden     # 100 rows of id -> sha256 of the clue string
test/golden/sudoku_9x9_medium.golden
...                                    # one file per size x difficulty
```

For indices 0–99, generate, hash and compare against the golden file. Any change to `Rng`, the hash
or generator ordering turns CI red. When such a change is intentional, bump `generatorVersion` and
keep the old generator reachable behind that switch so existing saves stay valid.

Also test:

- Every generated puzzle has exactly one solution (brute-force count == 1).
- The assigned tier matches what the technique solver reports (round trip).
- 6x6 boxes are 2 rows x 3 cols, not 3 x 2.
- The same seed produces byte-identical output across runs and across isolates.
- Fuzz 2000 seeds: no crashes, no non-termination, with a hard per-puzzle timeout.

### 3.7 Sudoku UI

- The grid scales to fit, with thick box borders and thin cell borders.
- Tap a cell to select; a large number pad sits below the grid, within thumb reach.
- **Pencil mode** toggle for corner notes.
- **Undo / redo** with a deep stack.
- Mistake feedback with two modes: flag immediately (default for children) or only at completion.
- Highlight the selected digit everywhere, and soft-highlight its row, column and box.
- **Hint** reveals one cell the technique solver can prove. Hints are counted; the puzzle still
  counts as solved but does not earn a clean-win star.
- **Auto-save every move**, so closing the app mid-puzzle and returning later restores the exact
  board.
- The timer is visible but small, and can be switched off in settings.
- Completion shows confetti and a subdued sound, honouring the mute and reduced-motion settings.

---

## 4. Arcade

### 4.1 Space Invaders

A Flame `FlameGame` driven on a fixed logic step — a constant `fixedDeltaTime` with leftover delta
accumulated across frames — so a 60 Hz phone and a 144 Hz PC play at the same speed.

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

### 4.2 On-screen controls

Large **LEFT**, **RIGHT** and **FIRE** buttons.

- Minimum 56 dp touch targets; 72 dp for the two movement buttons.
- LEFT and RIGHT bottom-left, FIRE bottom-right, swappable in settings for left-handed players.
- **Hold to move**, not tap-to-nudge, via `onTapDown`/`onTapUp` or Flame's `HudButtonComponent`.
  Handle pointer-cancel: if a finger slides off the button, movement must stop, otherwise the ship
  drifts forever. This is a common bug in on-screen D-pads; cover it with a test.
- Support two simultaneous touches, via Flame's `MultiTouch` detectors, so the player can move and
  fire at once. Flutter's gesture arena can claim the second pointer, so implement each button with a
  raw `Listener` rather than `GestureDetector`.
- Respect safe areas. Never place FIRE under the iOS home indicator or the Android gesture bar.
- Buttons are semi-transparent but never invisible, and never overlap the play field.

Desktop adds keyboard control: arrows or A/D to move, space to fire, P or Esc to pause. Hide the
on-screen buttons after keyboard input and restore them on the next touch, so a touchscreen PC gets
both. Gamepad support (`gamepads`) comes later, not in the first release.

### 4.3 Score persistence

- Top five scores per game per difficulty, shown on the game-over card and in the menu.
- Each entry stores score, wave reached, date and profile.
- Lifetime counters: games played, total aliens destroyed.

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
    "showTimer": false, "theme": "day", "reduceMotion": false
  },
  "profiles": [{
    "id": "p1", "name": "Ana", "avatar": "fox", "createdAt": "2026-08-11T10:00:00Z",
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
      "invaders": { "highScores": [{ "score": 15400, "wave": 7, "at": "..." }],
                    "gamesPlayed": 22, "totalKills": 3110 }
    }
  }],
  "puzzleCache": { "sudoku:9x9:hard:12": "…clue string…" }
}
```

The save stores puzzle **IDs**, not grids, because ID plus generator reconstructs the puzzle. That
holds the file to a few kilobytes after 500 puzzles, and it is why §3.1 determinism is load-bearing.

### 5.3 Rules

- Write on every Sudoku move (debounced 500 ms), on game over, and on app pause or close.
- Read once at startup into memory; every later read is from memory. No disk access inside a game
  loop.
- Never crash on a malformed save. On a parse failure, move the file aside to `save.corrupt.json`,
  start fresh, and tell the child once that the old game could not be found. Losing a high score is
  bad; a boot loop is worse.
- Export and import the save as a file — the share sheet on mobile, a file picker on desktop. That is
  how a family moves to a new tablet without an account or a server.
- No cloud sync, by design.

---

## 6. Repository layout

```
game-station/
├─ PLAN.md
├─ README.md
├─ melos.yaml                       # or plain path deps — decide in phase 0
├─ packages/
│  └─ puzzle_engine/                # pure Dart, no Flutter imports
│     ├─ lib/
│     │  ├─ puzzle_engine.dart
│     │  └─ src/
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
   │  ├─ app.dart                   # router, theme
   │  ├─ core/
   │  │  ├─ storage/                # ProgressRepository, atomic write, migrations
   │  │  ├─ audio/                  # soloud wrapper, mute-aware
   │  │  └─ ui/                     # BigButton, ScreenScaffold, design tokens
   │  ├─ features/
   │  │  ├─ home/
   │  │  ├─ profiles/
   │  │  ├─ settings/
   │  │  ├─ sudoku/                 # grid widget, keypad, controller
   │  │  └─ arcade/
   │  │     ├─ shared/              # OnScreenPad, GameShell, pause, HUD
   │  │     └─ invaders/            # FlameGame and components
   │  └─ assets/{fonts,images,audio}/
   ├─ test/                         # widget tests
   ├─ integration_test/             # on-device smoke tests
   └─ pubspec.yaml
```

`puzzle_engine` is a separate pure-Dart package so its tests run in about a second with no emulator
and no Flutter bindings, which makes ten thousand fuzz seeds cheap. It also keeps generation logic
from entangling with rendering code.

---

## 7. Phases

Estimates assume one developer working part time.

### Phase 0 — groundwork (1–2 days)

- `flutter create` the app, `dart create` the engine package, wire the path dependency.
- Strict `analysis_options.yaml`: `strict-casts`, `strict-raw-types`, no implicit dynamic.
- CI: analyze and test on push. `.gitignore`. License choice (MIT for code, CC0/CC-BY for art).
- Add the no-network CI grep guard from §2.
- **Done when:** an empty app launches on an Android emulator, an iOS simulator and one desktop
  target, with CI green.

### Phase 1 — app skeleton (3–4 days)

- Router and a home screen with two large cards: Sudoku and Arcade.
- Design tokens for colour, spacing and type scale. Day and night themes. Large default tap targets.
- `ProgressRepository`: atomic JSON writes, schema v1, migration hook, corrupt-file recovery.
- Profile picker, plus create, rename and delete.
- Settings: sound, haptics, timer visibility, theme, reduced motion.
- **Done when:** killing and reopening the app preserves the profile and settings on all six targets.

### Phase 2 — Sudoku engine (5–7 days)

The critical path.

- `Rng`, `fnv1a`, `SudokuSpec`, bitmask `SudokuBoard`.
- Solver: brute-force count-to-2, plus the technique-tier solver.
- Generator: grow, dig, judge, with the retry loop.
- `PuzzleId`: parse and build IDs, date-to-index, ID-to-seed.
- The full test set from §3.6, including golden files.
- A benchmark script meeting the §3.5 targets.
- **Done when:** `dart test` is green, goldens are locked, the 2000-seed fuzz is clean, and the
  benchmark is within target.

### Phase 3 — Sudoku UI (5–7 days)

- Size and difficulty pickers showing solved state and best times.
- A daily-puzzle card with the current streak.
- The grid widget, driving 9x9 and 6x6 from one implementation; keypad, pencil mode, undo/redo,
  highlighting.
- Hints via the technique solver. Both mistake-feedback modes.
- Mid-puzzle auto-save and resume. Completion screen.
- Generation in an isolate, with a spinner and pre-warming.
- **Done when:** 9x9 and 6x6 can be solved end to end; a force-quit mid-puzzle resumes the exact
  board; solved state persists across a restart.

### Phase 4 — arcade shell and Space Invaders (5–7 days)

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

### Phase 5 — polish (4–5 days)

- Sound effects and light music, all mutable, ducked when the app backgrounds.
- Haptics on mobile only.
- Accessibility: screen-reader labels on every control, a colourblind-safe palette that never uses
  colour as the only signal, text-scale support, and `reduceMotion` suppressing confetti.
- Portrait and landscape, with a tablet layout that does not stretch the grid.
- i18n scaffolding (`.arb`), English first. The largely numeric UI keeps later translation cheap.
- **Done when:** an accessibility pass on TalkBack and VoiceOver passes, and every screen survives
  rotation.

### Phase 6 — release (3–5 days)

- Icon, splash, store artwork and per-platform screenshots.
- Android: signed AAB, latest target API, Play Data Safety declared as no data collected (accurate),
  aiming for Teacher Approved / Designed for Families.
- iOS: Kids Category, which **bans** third-party ads and analytics — the app has neither, so it
  qualifies without changes. Requires an Apple Developer account (about $99/year) and a Mac to build.
- Windows: MSIX or a plain zip; Microsoft Store or Steam optional later.
- macOS: notarization, which also needs the developer account.
- Linux: tarball plus Flathub. F-Droid is also viable if the app stays fully FOSS, which is strong
  independent evidence for the no-ads, no-tracking claim.
- **Done when:** the app installs from a real store listing on a real device and plays offline.

### Phase 7 — more games (ongoing)

One game per minor release from the §4.4 table, each reusing `GameShell` and `OnScreenPad`.

**Release at the end of Phase 6.** Sudoku in two sizes and four tiers plus Space Invaders is a
complete app.

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
| iOS needs a Mac, $99/year and review | Medium | Plan early; Android and desktop can ship first |
| Linux audio flakiness | Low | `flutter_soloud`; audio is optional anyway |
| Kids-category store rules | Low | Already met: no ads, no network, no data collection |
| Feature creep — twenty games, none finished | High | Release line fixed at Phase 6 |

---

## 9. Release checklist

- [ ] In airplane mode, every screen works with no errors.
- [ ] The built Android APK manifest contains no internet permission (verified in the artifact).
- [ ] The daily puzzle is byte-identical on Android, iOS, Windows, macOS and Linux.
- [ ] Golden determinism tests pass in CI.
- [ ] A force-quit mid-puzzle restores the exact board, notes and timer.
- [ ] High scores survive 100 restarts.
- [ ] A six-year-old can play Invaders with the on-screen controls unaided.
- [ ] Simultaneous move and fire works on the cheapest test device.
- [ ] The grid is readable at 200% system text scale.
- [ ] No ad, analytics or HTTP package anywhere in the dependency tree (`dart pub deps` audit).
- [ ] Cold start under two seconds on an old low-end Android device.

---

## 10. Starting order

1. Phase 0: scaffold the app and engine package, CI, and the no-network guard.
2. Write `Rng` and `fnv1a`, and write the determinism test **before** the generator, so the sequence
   is locked before anything depends on it.
3. Write the brute-force solver with count-to-2. The rest of the Sudoku work builds on it.

Space Invaders is the easier and more enjoyable half, so it makes a better reward than a warm-up.
