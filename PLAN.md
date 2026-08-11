# GAME STATION — CAVEMAN PLAN

> Plan talk like caveman. Short word. No fluff. Tech under rock still sharp.

---

## 1. WHAT WE MAKE

Me make game box for small human. Box live on phone. Box live on other phone. Box live on big
flat machine with keyboard.

| Rule | Why |
|---|---|
| No ad | Ad bad. Ad steal child eye. Ad shout. |
| No net | Box work in cave with no fire signal. Plane. Car. Nowhere. |
| No spy | No count, no watch, no send. Nothing leave box. |
| No coin trap | No buy shiny gem. No wait timer. |
| Remember | Box remember what child beat. Box remember big number. |
| Simple | Big button. Fat finger work. No read many word. |

Target rock:

- Android phone + tablet (Android 8 and up)
- iOS phone + tablet (iOS 13 and up)
- PC: Windows 10+, macOS 11+, Linux (GTK)

---

## 2. WHICH TOOL

**Flutter + Flame. Dart. One code, six rock.**

Why me pick:

- One code go all six rock. Real desktop, not fake wrapper.
- Flutter widget good for Sudoku grid. Grid is boring box, widget make boring box fast.
- Flame is game loop on top of Flutter. Same code do sprite, tick, collide, on-screen button.
- Dart do fast math. Sudoku solve need many many loop. Dart fine.
- All free. No license tax. No engine man take share.
- Small ship. No browser inside app.

Tool me not pick, and why:

| Tool | Why no |
|---|---|
| Godot | Good game. Bad app menu. iOS ship path rough. Two mind for grid UI. |
| React Native | Desktop story weak. Windows/macOS port limp. |
| Unity | Big rock. Heavy. License mood swing. Overkill for 6x6 grid. |
| Electron / Tauri web | Desktop fine. Phone weak. Fat ship. |
| Six native app | Six times work. Caveman only two hand. |

### Package rock (pubspec)

| Need | Package | Note |
|---|---|---|
| Engine | `flame` | Game loop, sprite, collide, on-screen joy button |
| State | `flutter_riverpod` | Small. No code-gen. Good for inject save-store |
| Save path | `path_provider` | Find safe folder each rock |
| Sound | `flutter_soloud` | Low delay. Work all six rock incl. Linux |
| Shake | `flutter_vibrate`-like / `HapticFeedback` (built in) | Phone only, guard by platform |
| Test | `flutter_test`, `test`, `integration_test` | Built in |
| Lint | `flutter_lints` + strict analyze | Built in |

**Package me BAN:**

- No `google_mobile_ads`. Obvious.
- No `firebase_*`, no `sentry`, no analytics. Nothing phone home.
- No `google_fonts` — that fetch font over net at run. Instead bundle font file in `assets/fonts/`.
- No `http`, no `dio`. If no net code exist, no net leak possible.

**Hard wall, not soft promise:**

- Android: do NOT add `android.permission.INTERNET` in manifest. Then OS itself block net. Store
  page show "no net permission". Parent trust that more than word.
- iOS/macOS: no network entitlement. macOS sandbox: leave `com.apple.security.network.client` off.
- CI grep step: fail build if `http://`, `https://`, `Socket`, or `HttpClient` show in `lib/`.

### Save rock

Small data. Few kilobyte. So no database need.

- One JSON file, `save.json`, in app support folder (`path_provider`).
- Write safe: write `save.json.tmp`, `flush`, then `rename` over old. Rename is atomic. Child
  yank power cord mid-write, save not turn to mush.
- Keep `schemaVersion` int. Migrate step on load, old to new.
- Wrap in `ProgressRepository` class. If one day data grow big, swap guts to `drift` (SQLite),
  rest of app not care.

---

## 3. SUDOKU — SAME SEED, SAME PUZZLE, FOREVER

Child on phone and child on PC must see SAME puzzle for same day. No server. So puzzle must be
born from number, not from luck.

### 3.1 Own dice

`dart:math` `Random(seed)` **not promised stable** between Dart version. Dart man may change guts.
Then old puzzle change. Child cry, streak break.

So: **write own dice.** `Xoshiro128+` or `PCG32`. Twenty line. Pure int math. Never change.

```dart
// packages/puzzle_engine/lib/src/rng.dart
class Rng {
  int _s0, _s1;
  Rng(int seed) : _s0 = seed ^ 0x9E3779B9, _s1 = (seed * 0x85EBCA6B) & 0xFFFFFFFF {
    if (_s0 == 0 && _s1 == 0) _s0 = 1;      // all-zero state is death
    for (var i = 0; i < 8; i++) nextInt(2); // warm the rock
  }
  int nextInt(int bound) { /* xorshift128, mask to 32 bit, mod bound */ }
  void shuffle<T>(List<T> list) { /* Fisher-Yates using nextInt */ }
}
```

Mask every step to 32 bit. Why: JS number only hold 53 bit safe. If we ever ship web, unmasked
64-bit int drift and puzzle differ on web. Mask now, sleep good later.

### 3.2 Puzzle name and seed

```
id   = "sudoku:9x9:hard:412"
seed = fnv1a32(id)          // own hash, in engine, never change
```

Two door to same puzzle:

- **Day door.** `index = daysSince(2026-01-01, UTC)`. Day puzzle = one per size per difficulty per
  day. Use UTC so child not jump day when fly over water.
- **Number door.** Endless list. Child pick puzzle 1, 2, 3... forever. Same number, same grid,
  same on every rock, same next year.

### 3.3 Two size

| Size | Digit | Box shape | Grid |
|---|---|---|---|
| 9x9 | 1–9 | 3 row x 3 col | 81 cell |
| 6x6 | 1–6 | 2 row x 3 col | 36 cell |

Engine must be **size-generic**, not two copy-paste file. One `SudokuSpec { rows, cols, boxRows,
boxCols }`. Then 4x4 or 12x12 come free later.

### 3.4 How make puzzle

Three step. Each step must be deterministic — every list order come from own dice, never from
`Set`/`Map` walk order (that order not promised).

**Step 1 — grow full grid.**
Backtrack fill. Try digit in shuffled order from `Rng`. Full valid grid always exist, so this
never fail, just sometimes back up.

**Step 2 — dig hole.**
Make list of all cell. Shuffle with `Rng`. Walk list. Try take digit out. Then count solution
with solver, **stop counting at 2** (no need count all, only need know "more than one?").
If still exactly 1 solution → hole stay. Else → put digit back.

**Step 3 — judge hard.**
Do NOT judge hard by count of clue. Clue count lie. Judge by **which trick human need**:

| Tier | Trick need | Name |
|---|---|---|
| T1 | naked single, hidden single | EASY |
| T2 | + naked/hidden pair, pointing pair, box-line reduce | MEDIUM |
| T3 | + triple, X-wing | HARD |
| T4 | need guess / deep chain | EXPERT |

Solver run human-trick in tier order. Highest tier it must reach = difficulty of puzzle.

Loop: dig, judge, if tier wrong → throw away, bump seed sub-counter, grow again. Cap try at ~40.
If 40 fail, widen tier window one notch and log warn. Never ship "generation failed" to child.

Clue count still useful as *guard rail* only:

| | 9x9 | 6x6 |
|---|---|---|
| Easy | 36–45 | 18–24 |
| Medium | 30–35 | 15–17 |
| Hard | 26–29 | 12–14 |
| Expert | 22–25 | 10–11 |

6x6 have no room for real Expert. So 6x6 ship Easy / Medium / Hard only. Do not fake it.

### 3.5 Speed

Uniqueness check is the slow part. Numbers to beat:

- Easy/Medium 9x9: under 100 ms
- Hard/Expert 9x9: under 400 ms
- 6x6: under 30 ms

Do:

- Bitmask candidate. Row/col/box each one int. `&`, `|`, popcount. No `Set<int>` per cell.
- Generate inside `Isolate` (`compute()`). Never block paint thread. Child see spinner never.
- Cache made puzzle into save file (`puzzleCache`, keep last ~30). Second visit is instant.
- Pre-warm: when child open Sudoku menu, kick isolate for today puzzle in background.

### 3.6 Prove it never drift — golden test

This the most important test in whole repo.

```
test/golden/sudoku_9x9_easy.golden     # id -> sha256 of clue string, 100 row
test/golden/sudoku_9x9_medium.golden
... one file per size x difficulty
```

Test: for index 0..99, build puzzle, hash it, compare to file. Any change to `Rng`, hash, or
generator order → red CI. If change is on purpose, must bump `generatorVersion` and keep old
generator alive behind switch, so old child save not break.

Other engine test:

- Every made puzzle has exactly one solution (brute force count == 1).
- Judged tier match what tier-solver say (round trip).
- 6x6 box shape correct (2x3, not 3x2).
- Same seed, two run, same byte. Also same across isolate.
- Fuzz: 2000 random seed, no crash, no infinite loop (hard timeout per puzzle).

### 3.7 Sudoku screen

Must feel good for small finger:

- Grid stretch to fit, thick line on box edge, thin inside.
- Tap cell → pick. Number pad big, under grid, in thumb zone.
- **Pencil mode** toggle. Small note digit in corner.
- **Undo / Redo**. Deep stack. Child undo whole game if want.
- Mistake mark: option "show wrong now" (kid default ON) or "show wrong at end" (grown mode).
- Same-digit highlight. Row/col/box soft highlight. Big help for small human.
- **Hint** button: reveal one cell that human-trick can prove. Count hints used. Puzzle solved
  with hint still count as solved, but mark it, and no "clean win" star.
- **Auto-save every move.** Close app mid-puzzle, come back next week, board exactly there.
- Timer: show, but small, and **can turn off** in settings. Clock stress not good for kid.
- Win: confetti, sound, star. Not loud. Not scary.

---

## 4. SPACE INVADERS — AND FRIEND

### 4.1 The game

Flame `FlameGame`. Fixed logic step so PC at 144 Hz and phone at 60 Hz play same speed
(`fixedDeltaTime`, accumulate leftover).

- Player ship at bottom. Move left/right only.
- Alien block 5 row x 11 col. March side. Hit wall → drop down, flip way, go faster.
- Alien shoot down at random-but-seeded rate. Rate climb with wave.
- 4 bunker. Bullet chew hole in bunker (per-pixel-ish, use small block grid).
- Player: 3 life. Bonus life every 10000 point.
- Score: front row alien 10, middle 20, back 30. UFO fly over sometime, worth 50–300.
- Wave clear → next wave, start lower, faster. Endless.

Kid dial in settings:

- **Easy mode**: slower alien, fewer alien row, 5 life, alien bullet slower.
- **Auto-fire**: hold nothing, ship shoot by self. Small human hand only manage move.
- Never say "GAME OVER" mean. Say "Good try! Play again?".

### 4.2 Control — this the part user ask for

**On-screen: big LEFT button, big RIGHT button, big FIRE button.**

Rule for button:

- Touch target **min 56 dp**, aim 72 dp for the two move button.
- Sit in bottom corner, LEFT+RIGHT bottom-left, FIRE bottom-right (swap in settings for left-hand
  child).
- **Hold to keep move**, not tap-to-nudge. Use `onTapDown`/`onTapUp` + pointer-cancel, or Flame
  `HudButtonComponent`. Must handle finger slide off button (pointer cancel) or ship run away
  forever — classic bug, test it.
- Two finger at once must work (`MultiTouch`): move and fire same time. Flutter default gesture
  arena can eat second finger — use `Listener`/raw pointer per button, not `GestureDetector`.
- Respect safe area / notch / gesture bar. Never put FIRE under home swipe strip.
- Buttons semi-transparent, but never invisible, and never on top of play field.

**PC**: keyboard too. Arrow / A-D to move, Space to fire, P/Esc pause. Hide on-screen button when
last input was keyboard, show again on first touch. PC with touch screen get both.

Optional later: gamepad (`gamepads` package). Nice for TV/PC. Not phase 1.

### 4.3 Score remember

- Top 5 score per game, per difficulty. Show on game-over card and in menu.
- Store: score, wave reached, date, which profile.
- Also lifetime: games played, total alien squashed. Small human love big number go up.

### 4.4 Other retro game (later phase)

Same engine, same on-screen button pattern, cheap to add:

| Game | Control | Save |
|---|---|---|
| Brick Breaker | left/right paddle | high score, level reached |
| Snake | 4 arrow or swipe | high score, longest snake |
| Memory Match | tap card | best time per grid size |
| Whack-a-Mole | tap hole | high score |
| Pong (vs machine) | left/right | win count |
| 2048 | swipe | best tile, best score |
| Tic-Tac-Toe | tap | win/lose/draw count |

Add one per small release. Do not build all before ship. Ship Sudoku + Invaders first.

---

## 5. REMEMBER — WHAT BOX KEEP

### 5.1 Profile

Many child, one tablet. So **local profile**. Name + animal picture. No password (kid app, no
secret worth lock). Pick profile on open, big face button. Default one profile, no setup wall.

### 5.2 Shape of save

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

Note: save keep only **puzzle id**, not whole puzzle. Because id + generator = puzzle. That why
determinism matter so much: save file stay tiny (few KB after 500 puzzle) and stay honest.

### 5.3 Rule about save

- Write on: every Sudoku move (debounce 500 ms), game over, app pause, app close.
- Read once at boot into memory. All read after that from memory. No disk in game loop.
- Never crash on bad save. Try parse → fail → back up broken file to `save.corrupt.json`, start
  fresh, tell child "could not find old game, sorry" once. Losing high score bad. Boot loop worse.
- Export / import save as file (share sheet on phone, file picker on PC). That how family move to
  new tablet, with no cloud, no account, no server.
- No cloud sync. Ever. That the deal.

---

## 6. HOW REPO LOOK

```
game-station/
├─ PLAN.md
├─ README.md
├─ melos.yaml                       # or plain path deps, decide at phase 0
├─ packages/
│  └─ puzzle_engine/                # PURE DART. no flutter import at all.
│     ├─ lib/
│     │  ├─ puzzle_engine.dart
│     │  └─ src/
│     │     ├─ rng.dart             # own dice
│     │     ├─ hash.dart            # own fnv1a
│     │     ├─ sudoku_spec.dart     # 9x9 / 6x6 shape
│     │     ├─ sudoku_board.dart    # bitmask board
│     │     ├─ generator.dart       # grow, dig, judge
│     │     ├─ solver.dart          # count solution, tier solve
│     │     ├─ techniques/          # single, pair, pointing, x-wing…
│     │     └─ puzzle_id.dart       # id <-> seed, day <-> index
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
   │  │  ├─ storage/                # ProgressRepository, atomic file, migration
   │  │  ├─ audio/                  # soloud wrapper, mute-aware
   │  │  └─ ui/                     # BigButton, ScreenScaffold, tokens
   │  ├─ features/
   │  │  ├─ home/
   │  │  ├─ profiles/
   │  │  ├─ settings/
   │  │  ├─ sudoku/                 # grid widget, keypad, controller
   │  │  └─ arcade/
   │  │     ├─ shared/              # OnScreenPad, GameShell, pause, HUD
   │  │     └─ invaders/            # FlameGame + component
   │  └─ assets/{fonts,images,audio}/
   ├─ test/                         # widget test
   ├─ integration_test/             # real device smoke
   └─ pubspec.yaml
```

Why split `puzzle_engine` out: pure Dart test run in ~1 second, no emulator, no Flutter bind. Ten
thousand fuzz seed cheap. Engine logic never tangle with paint code.

---

## 7. PHASE — DO IN THIS ORDER

Estimate = one caveman, part time. Adjust for own tribe size.

### Phase 0 — clear ground (1–2 day)

- `flutter create` app, `dart create` engine package, wire path dep.
- Strict `analysis_options.yaml`: `strict-casts`, `strict-raw-types`, no implicit dynamic.
- CI: analyze + test on push. `.gitignore`. Choose license (MIT code, CC0/CC-BY art).
- Add "no net" CI grep guard.
- **Done when:** empty app open on Android emulator, iOS sim, and one desktop rock; CI green.

### Phase 1 — bone of app (3–4 day)

- Router + home screen with two big card: SUDOKU, ARCADE.
- Theme token: colour, spacing, text size. Day + night. Big tap target default.
- `ProgressRepository`: atomic JSON, schema v1, migration hook, corrupt-file recovery.
- Profile pick screen + create/rename/delete.
- Settings screen: sound, haptics, timer, theme, reduce-motion.
- **Done when:** kill app, reopen, profile and setting still there, on all six rock.

### Phase 2 — Sudoku engine (5–7 day) ← the real work

- `Rng`, `fnv1a`, `SudokuSpec`, bitmask `SudokuBoard`.
- Solver: brute-force count-to-2, plus tier technique solver.
- Generator: grow → dig → judge, retry loop.
- `PuzzleId`: id parse/build, day-index, seed.
- Full test set from §3.6 including golden file.
- Bench script; hit speed target in §3.5.
- **Done when:** `dart test` green, golden locked, 2000-seed fuzz clean, bench under target.

### Phase 3 — Sudoku screen (5–7 day)

- Size + difficulty pick screen, showing solved tick and best time.
- Daily puzzle card, with streak count.
- Grid widget (9x9 and 6x6 from same code), keypad, pencil, undo/redo, highlight.
- Hint using tier solver. Mistake mark modes.
- Auto-save mid-puzzle + resume. Win screen.
- Generation in isolate + spinner + pre-warm.
- **Done when:** solve 9x9 and 6x6 end to end; force-quit mid-puzzle and resume exact; solved
  state show in menu after restart.

### Phase 4 — arcade shell + Space Invaders (5–7 day)

- `GameShell`: pause, resume, quit-confirm, life/score HUD, game-over card with high score.
- `OnScreenPad`: LEFT / RIGHT / FIRE, multi-touch, hold-to-move, safe area, keyboard mirror.
- Invaders: player, alien block march, bullet both way, bunker chew, UFO, wave ramp, easy mode,
  auto-fire.
- Fixed-step loop. Test on slow old phone AND on 144 Hz PC — same speed.
- High score persist per profile.
- **Done when:** 10 minute play on phone + PC, no jank, no stuck ship, score survive restart.

### Phase 5 — polish (4–5 day)

- SFX + tiny music, all mutable, duck on app background.
- Haptics on phone only.
- Accessibility: screen-reader label on every button, colourblind-safe palette (never colour
  alone to mean thing), text scale respect, `reduceMotion` kill confetti.
- Landscape + portrait both. Tablet layout (grid not stretch ugly wide).
- i18n scaffold (`.arb`), English first. Number-and-picture UI means translation cheap later.
- **Done when:** a11y pass on TalkBack + VoiceOver, and rotate every screen with no break.

### Phase 6 — ship (3–5 day)

- Icon, splash, store art, screenshot per rock.
- Android: signed AAB, target latest API, Play Data-Safety form = "no data collected" (true!),
  aim Teacher-Approved / Designed-for-Families.
- iOS: Kids Category. Kids Category **bans** third-party ad and analytics — we have none, so we
  pass clean. Need Apple dev account (~$99/yr) and a Mac to build.
- Windows: MSIX or plain zip. Optional Steam/MS Store later.
- macOS: notarize (need dev account).
- Linux: tarball + Flathub. Also F-Droid if we keep it fully FOSS — strong "no ad, no spy" proof.
- **Done when:** install from real store listing on real device, offline, and play.

### Phase 7 — more game (ongoing)

One game per small release, from §4.4 table. Each reuse `GameShell` + `OnScreenPad`.

**Ship line: end of Phase 6.** Sudoku (both size, 4 tier) + Space Invaders is a real, whole app.
Do not hold ship for game number seven.

---

## 8. THINGS THAT WILL BITE

| Bite | How bad | Rock to stand on |
|---|---|---|
| Dart `Random` change → puzzle drift | high | Own `Rng`, golden test, `generatorVersion` |
| Int overflow differ if we ever add web | med | Mask 32-bit everywhere from day one |
| Hard/Expert generation slow, UI freeze | high | Bitmask + isolate + cache + pre-warm |
| Finger slide off LEFT, ship run forever | med | Handle pointer-cancel; write a test for it |
| Second finger eaten by gesture arena | med | Raw `Listener` per button, not `GestureDetector` |
| Game speed tied to frame rate | med | Fixed logic step, test 60 vs 144 Hz |
| Bad save file → boot loop | high | Try/catch, back up corrupt, start fresh, never crash |
| iOS needs Mac + $99 + review | med | Plan early; Android + PC can ship first |
| Linux audio flaky | low | `flutter_soloud`; sound is optional anyway |
| Store think "kids app" = strict rules | low | We already meet them: no ad, no net, no data |
| Feature creep (20 games, none done) | high | Ship line at Phase 6. Written down. Obey. |

---

## 9. WHEN IS IT GOOD

Ship only when all true:

- [ ] Airplane mode: whole app work, every screen, zero error.
- [ ] Android build has NO internet permission. Verified in built APK manifest.
- [ ] Same day-puzzle byte-identical on Android, iOS, Windows, macOS, Linux.
- [ ] Golden determinism test green in CI.
- [ ] Force-quit mid-Sudoku → resume exact board, notes, timer.
- [ ] High score survive reinstall-less restart; survive 100 restarts.
- [ ] 6-year-old play Invaders with on-screen button, no grown-up help, no rage.
- [ ] Two-finger move+fire work on cheapest test phone.
- [ ] Grid readable at 200% system text scale.
- [ ] Zero ad SDK, zero analytics SDK, zero `http` call in dependency tree (`dart pub deps` audit).
- [ ] Cold start under 2 seconds on old cheap Android.

---

## 10. FIRST THREE THING TO DO TOMORROW

1. Phase 0: scaffold app + engine package + CI + no-net grep guard.
2. Write `Rng` and `fnv1a`. Write determinism test FIRST, before generator. Lock the dice.
3. Write brute-force solver with count-to-2. Everything else in Sudoku stand on that.

Sudoku engine is the hard rock. Break it first, while arm strong. Invaders is fun and easy —
save it as reward.

Ugh. Plan done. Go make.
