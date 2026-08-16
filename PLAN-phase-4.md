# Phase 4 — arcade shell and Space Invaders

The plan for `app/lib/features/arcade`: the shell every later game reuses, the on-screen control
pad, and Space Invaders under both. [`PLAN.md`](PLAN.md) §4 is the design this expands, §7 is the
phase order, and §7's phase-4 list names what phase 3 handed over. Where this file and `PLAN.md`
disagree, the reason is stated here and the closing pull request updates `PLAN.md`.

Phase 4 is the first phase with a real-time loop in it. Everything before it was a pure function of
input — a puzzle from an id, a board from a save — and could be checked by comparing values. A game
runs on a clock, on hardware that varies by a factor of two in frame rate, and takes two fingers at
once. The phase's real done-criterion is therefore not "Invaders plays" but the two properties that
cannot be seen by looking at it: the same run behaves identically at 60 Hz and 144 Hz, and a finger
that slides off a button stops the ship.

**Release line unchanged:** `PLAN.md` §7 ships at phase 6. Nothing here blocks or advances that, and
the seven other games in `PLAN.md` §4.4 are phase 7.

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
| Game speed is independent of frame rate | `PLAN.md` §4.1 and §8's risk table. Enforced by a test rather than by a device: the simulation advances only in fixed steps, and `invaders_sim_test.dart` runs the same seed for ten simulated seconds as 600 frames of 16.67 ms and as 1440 frames of 6.94 ms, then compares the entire state. A loop that read wall-clock delta directly would fail it. The 144 Hz device pass stays as well (§8) — the test proves the arithmetic, not the renderer. |
| A finger sliding off a button stops the ship | `PLAN.md` §4.2 and §8. Each button is a raw `Listener` that releases on `onPointerUp`, `onPointerCancel` **and** on an `onPointerMove` whose local position leaves the button's bounds; Flutter routes moves to the widget the pointer went down on, so without the third case the ship drifts forever. Tested with `tester.startGesture` and a `moveTo` outside the button. |
| Move and fire at the same time | `PLAN.md` §4.2. Raw `Listener` per button rather than `GestureDetector`: a `Listener` does not enter the gesture arena, so no recogniser can claim the second pointer. Tested with two concurrent `TestGesture`s asserting both intents are live in the same frame. |
| Exactly one new dependency, and it reaches no network | `PLAN.md` §2 assigns `flame` to this phase, and `app/pubspec.yaml`'s header comment already says so. Resolution was checked before this plan was written: `flame 1.38.0` adds **two** packages to the graph, itself and `ordered_set 8.0.1` — `vector_math` and `meta` are already there through Flutter. Neither is in `tool/check_offline.dart`'s network or forbidden lists, and that check reads the resolved graph rather than the pubspec, so a transitive arrival is caught too. |
| No ambient randomness anywhere in `lib/` | PLAN-phase-1.md §1. A run's alien fire, UFO timing and score are drawn from a seeded `GameRng` in `app/lib/features/arcade/shared/`, and the seed comes from the injected clock provider, so a test replays a run exactly. Enforced the way phase 3 enforced its isolate rule: a scanner test asserting `Random(` appears nowhere in `app/lib`, with its own tests for the scanner (`AGENTS.md`). |
| No new asset file, no new licence line | `PLAN.md` §6 licenses assets per file, and a sprite sheet is a binary in a diff nobody reviews. The aliens, ship, bunkers and UFO are pixel bitmasks declared as `List<int>` in `sprites.dart` and drawn as rectangles — the same shapes the 1978 cabinet drew, at any resolution, with nothing to license. |
| Tap targets: 72 dp for LEFT, RIGHT and FIRE; 56 dp the floor everywhere else | `PLAN.md` §4.2, `AppTapTargets.primary` and `.min` (`core/ui/tokens.dart`). §4.2 asks for 72 dp on the two movement buttons and 56 dp elsewhere; FIRE gets 72 as well because it is held as continuously as they are, and these are floors rather than sizes. Asserted per button in a widget test, as phase 3's keypad is. |
| FIRE is never under the home indicator or gesture bar | `PLAN.md` §4.2. The pad is a sibling of the play field in a `Column` inside `SafeArea`, not an overlay, so it can neither overlap the field nor sit in the system inset. A widget test pumps with a 34 dp bottom `viewPadding` and asserts every button's rect clears it. |
| Screen size cannot change gameplay | The simulation works in a fixed 224 x 256 virtual field — the original cabinet's resolution — and the renderer scales it with Flame's `FixedResolutionViewport`. A phone and a tablet therefore run the same game, and the dt-equivalence test above does not depend on a layout. |
| Nothing an internal error reaches a child | `AGENTS.md`. There is no failure screen: a lost life is "Good try! Play again?" (`PLAN.md` §4.1), a save that fails is already recorded rather than thrown (`progress_repository.dart`), and the game has no other error state to surface. |
| The save stays a few kilobytes | `PLAN.md` §5.2. Five high scores per game **per mode**, capped when the entry is written rather than when the file is read — `ArcadeGameProgress.highScores`'s own comment says why the cap is a write-time rule. |
| `tool/verify.sh` green before every commit | It is what CI runs, in the same order (`AGENTS.md`). The app suite was 28 s for 386 tests at phase 3's close; this phase budgets **under 40 s**, which is possible only because the simulation tests are plain `test()` calls with no widget tree — a ten-second run of Invaders is about 1200 fixed steps and costs single-digit milliseconds. |

---

## 2. Non-goals

| Not in phase 4 | Where it belongs |
|---|---|
| Sound and music (`PLAN.md` §5's polish list) | Phase 5. `flutter_soloud` is a dependency carried through every intervening review if it arrives now (`AGENTS.md`), and phase 3 already deferred the completion sound for the same reason (`PLAN-phase-3.md` §2). An arcade game with no sound is worse than a Sudoku with no sound, and it is still the right trade for one phase. |
| Haptics on a hit or a lost life | Phase 5, with the platform guard. `settings.haptics` stays stored and unread. |
| Screen-reader labels beyond the obvious, colourblind-safe palette, i18n | Phase 5. The pad's buttons get `Semantics` labels because a button with an arrow glyph and no label is unusable, but the accessibility pass on TalkBack and VoiceOver is phase 5's done-criterion. A real-time shooter is the one screen in the app a screen-reader user cannot play, and saying so is phase 5's job, not this one's. |
| Landscape and tablet layout | Phase 5, as it was for the Sudoku board. Portrait-first; landscape draws the same `Column` and lets the field take what is left. |
| Gamepad support (`gamepads`) | `PLAN.md` §4.2 already defers it past the first release. Desktop gets the keyboard mirror here. |
| The other seven games (`PLAN.md` §4.4) | Phase 7, one per minor release. `GameShell` is built with one game under it and gets no parameter that only a second game would use — a shell shaped by two hypothetical games fits neither. |
| Sprite art, animation frames, particle effects | The bitmask sprites of §4.7 are what ships. Swapping in drawn art later touches one file and no save. |
| Any change to `packages/puzzle_engine` | Phase 4 does not touch it. `generatorVersion` stays 1, no golden moves, and `tool/check_determinism.dart` has nothing new to scan — the engine is not in this phase's dependency chain at all. |
| A second difficulty axis beyond easy mode | `PLAN.md` §4.1 names easy mode and nothing else. "Per difficulty" in §4.3's score rule therefore means two tables, not five. |
| Online or cross-device high scores | The project has no network by construction (`PLAN.md` §2). |

---

## 3. Approach

Build bottom-up, as phases 2 and 3 did, so each layer is testable before anything draws it:

1. **Repository writes and the save fields** — arcade results, the per-mode score cap, the three
   per-profile options. Pure storage, no game.
2. **`GameRng` and the clock** — the seeded source, and the scanner test that keeps `Random` out.
3. **`InvadersSim`** — the whole game, as plain Dart with no Flutter and no Flame. This is where the
   fixed step, the alien block, collisions, bunkers, waves and scoring live.
4. **The Flame layer** — `flame` arrives, `InvadersGame` drives the sim on an accumulator and draws
   it in one pass.
5. **`OnScreenPad`** — the buttons, multi-touch, the keyboard mirror.
6. **`GameShell`** — HUD, pause, quit, the game-over card, and the write.
7. **The arcade menu** — `/arcade` stops being a placeholder.
8. **The device pass, the integration test and the phase close.**

**The load-bearing decision: the simulation is pure Dart and holds all the state; Flame renders it
and owns nothing.** `InvadersSim.step()` takes a `PadInput` and advances one fixed tick. Flame
components store no positions, no timers and no counters — `InvadersGame.update(dt)` feeds the
accumulator and `render(Canvas)` draws the sim's current state in a single pass.

Everything else in this plan leans on it. The dt-equivalence test is possible because a test can
call `step()` 1440 times without a widget tree or a ticker. A run is replayable because the only
entropy is a seed the test provides. The frame budget is knowable because the render pass is a loop
over about 150 rectangles rather than 150 components in a tree. If this split were abandoned, all
three of those go with it, and the phase's done-criterion would fall back to somebody watching the
screen.

The honest consequence, stated here rather than left for a reviewer to find: with the simulation
pure, Flame supplies the frame loop, `pauseEngine`/`resumeEngine`, `FixedResolutionViewport`
letterboxing and the `GameWidget` bridge, and nothing else. That is a real but small part of what
the package does. It is still taken, for the reasons in the table below, and if by phase 7 no game
has used more of it than this one, dropping it is a small change precisely because the simulation
never knew it was there.

Alternatives considered:

| Option | Rejected because |
|---|---|
| Flame components own the game state — one `PositionComponent` per alien, `RectangleHitbox` and `HasCollisionDetection` for hits | It is the idiomatic use of the package and it forfeits the phase's main check. Component lifecycle needs a mounted game to exercise, so every rule — the block reversing at a wall, the speed-up as aliens die — would need a pumped widget and a real ticker to test, and the 60 Hz-versus-144 Hz comparison would be a screenshot rather than an assertion. Collision for this game is axis-aligned rectangles against axis-aligned rectangles, which is one line of arithmetic and needs no broadphase for 150 shapes. |
| No `flame` at all: a `Ticker` and a `CustomPainter` | It would work, and with the split above it is a genuinely close call. Rejected because `PLAN.md` §2 and §4.1 chose the stack, and re-litigating a stack decision inside a phase is how a phase stops finishing (`AGENTS.md`); because the loop, the pause and the letterbox viewport are the fiddly parts and are already written here; and because phase 7's games are the ones that will want sprites, text components and particles. Two packages with no network surface, verified in §1, is a small price for not making that decision twice. |
| Flame's `HudButtonComponent` and `MultiTouchTapDetector` for the pad | `PLAN.md` §4.2 names both and also requires a raw `Listener` per button; this resolves that. Buttons inside the game canvas would need their own safe-area arithmetic, their own tap-target floor and their own theming, all of which `SafeArea`, `AppTapTargets` and the app's palette already do for widgets — and a widget test can press a widget, while pressing a component means synthesising a pointer into the game. |
| Fixed step of 1/60 s | At 144 Hz most frames would advance nothing and every third would advance one step, which is judder on the machine most likely to notice it. 1/120 s divides 60 Hz exactly (two steps per frame) and leaves 144 Hz alternating between one and two, which at 8.3 ms of movement is below what the eye separates. §4.2 has the numbers. |
| Interpolating render position between steps | It is the standard fix for a step slower than the frame rate, and at 1/120 s there is nothing left to fix. It would also give the renderer state of its own, which §3's decision exists to avoid. |
| `dart:math`'s `Random(seed)` for alien fire | PLAN-phase-1.md §1 keeps `Random` out of `lib/` so the engine's determinism rule stays easy to hold, and a sequence that is not stable across Dart versions would make a recorded run unreplayable — which is how the dt-equivalence test would go quietly green while comparing two different games. `GameRng` is twenty lines (§4.3). |
| Reusing the engine's `Rng` | It is deliberately not exported (`puzzle_engine.dart`), and exporting it would undo the reason: freezing a sequence is only meaningful when nothing outside the package can start a different one. A game's PRNG also has no reason to be frozen — nothing saves a run. |
| High scores split by mode through a second game id (`"invaders:easy"`) | Zero schema change, but it splits `gamesPlayed` and `totalKills`, which `PLAN.md` §4.3 calls *lifetime* counters, across two entries that then need adding up at every read. An optional `easy` flag on `HighScore` is equally additive and keeps one table and one pair of counters (§4.8). |
| Easy mode and auto-fire as `AppSettings` fields | They belong to a child, not to the tablet — a five-year-old and a nine-year-old share the device, which is the same argument that put `mistakeFeedback` on `Profile` in phase 3 (`PLAN.md` §5.2). |
| An `if (easyMode)` branch at each rule | Every tuning value lives in one `InvadersRules` object with a `normal` and an `easy` instance (§4.4). A branch per rule is a set of behaviours no test enumerates; one object means the easy game is testable as data. |

---

## 4. Design

### 4.1 The simulation

`InvadersSim`, in `features/arcade/invaders/model/`, importing nothing but `dart:typed_data` and
`package:flutter/foundation.dart` for `@immutable` — no Flame, no widgets, no clock:

```dart
class InvadersSim {
  InvadersSim({required InvadersRules rules, required int seed});

  void step(PadInput input);        // advances exactly `fixedStep`; nothing else advances it

  int  get score;
  int  get lives;
  int  get wave;
  int  get kills;                   // this run, for ArcadeGameProgress.totalKills
  bool get isOver;

  Player      get player;           // position, alive, respawn timer
  AlienBlock  get aliens;           // origin, step phase, alive bitmask over 5 x 11
  List<Shot>  get shots;            // both directions; `Shot.fromPlayer` says which
  List<Bunker> get bunkers;         // each a 22 x 16 block grid as a bitmask
  Ufo?        get ufo;
}
```

Rules, all in virtual units per second over the 224 x 256 field (§1):

- **The block** is 5 rows x 11 columns and steps sideways on a timer rather than moving smoothly, as
  the original does. The interval is `(rules.baseStep * alive / 55).clamp(rules.minStep,
  rules.baseStep)`, so the last alien is the fastest — the speed-up players remember is a
  consequence of the formula, not a special case. `baseStep` is 0.70 s at wave 1 and shrinks 12% per
  wave with a 0.09 s floor.
- **Reaching a wall** drops the block one row and reverses it, and the drop is what ends a run when
  it reaches the player's row.
- **Alien fire** starts a shot from the lowest live alien in a column chosen by `GameRng`, on a
  cadence of `1.2 s - 0.08 s per wave`, floored at 0.35 s, with at most three alien shots in flight.
- **The player** moves at 60 units/s, and fires one shot at a time with a 0.35 s cooldown. Auto-fire
  (`PLAN.md` §4.1) fires whenever the cooldown allows, so a small player only steers.
- **Bunkers** are four 22 x 16 block grids. A shot that overlaps a set block clears a disc of radius
  3 blocks around the impact and stops. Erosion is therefore the same code for shots from either
  side.
- **The UFO** crosses every 25 s ± 5 s of jitter from `GameRng`, and is worth 50, 100, 150, 200, 250
  or 300, also drawn from `GameRng` (`PLAN.md` §4.1).
- **Scoring** is 10 for the front row, 20 for the middle two, 30 for the back two, and a bonus life
  at every 10,000 points.
- **A wave clears** when the last alien dies; the next starts one row lower with the shrunken
  `baseStep`, without limit.

Easy mode is the same object with different numbers (`PLAN.md` §4.1): three alien rows rather than
five, `baseStep` 1.1 s with a 0.20 s floor and a 6% ramp, alien fire at 2.2 s floored at 0.9 s with
one shot in flight, and five lives.

Collision is axis-aligned rectangle overlap, evaluated once per fixed step in a fixed order — shots
against aliens, shots against bunkers, shots against the player, block against the player's row. The
order is part of the behaviour, so it is stated here and asserted by the equivalence test rather
than left to whichever loop was written first.

**Nothing in the simulation reads a clock.** `step()` advances by exactly `fixedStep`; the
accumulator that decides how many times to call it lives in the Flame layer (§4.2), which is the
only place a wall-clock delta exists at all.

### 4.2 The fixed step

`InvadersGame.update(double dt)`:

```dart
_accumulator += dt;
var steps = 0;
while (_accumulator >= fixedStep && steps < maxStepsPerFrame) {
  _sim.step(_input.value);
  _accumulator -= fixedStep;
  steps++;
}
if (steps == maxStepsPerFrame) _accumulator = 0;   // drop the backlog, never chase it
```

- `fixedStep` is **1/120 s**. It divides 60 Hz exactly and halves the judder at 144 Hz that 1/60 s
  would produce (§3).
- `maxStepsPerFrame` is **8**, and hitting it discards the remainder rather than carrying it. A
  frame that arrives 500 ms late — a garbage collection pause, a resumed app, a debugger breakpoint
  — would otherwise ask for 60 steps, which takes longer than a frame, which makes the next backlog
  larger. That is the spiral this clamp exists to prevent, and its cost is that a stalled app loses
  game time rather than fast-forwarding through it. Losing time is the better outcome:
  fast-forwarding kills the player with a shot they never saw.
- The clamp is also why the equivalence test uses 6.94 ms and 16.67 ms frames rather than one 10 s
  frame: at eight steps a frame the clamp is unreachable at any real frame rate, and a test that
  crossed it would be testing the clamp instead.

### 4.3 `GameRng`

```dart
// features/arcade/shared/game_rng.dart
class GameRng {
  GameRng(int seed);
  int nextInt(int bound);          // 1 <= bound <= 2^32, unbiased by rejection
  double nextDouble();             // [0, 1)
  int pick(List<int> candidates);  // convenience for "which column fires"
}
```

Xorshift32 with a SplitMix32-expanded seed, masked to 32 bits at every step — the same shape as the
engine's `Rng` (`packages/puzzle_engine/lib/src/rng.dart`) and for one of the same reasons: a web
target added later must not change behaviour. It is **not** frozen, because nothing persists a run.

The run's seed is `now().millisecondsSinceEpoch & 0xFFFFFFFF`, where `now` is the injected clock
provider, so a test fixes the clock and replays a run exactly while a child gets a different game
each time. `nowProvider` currently lives in `features/sudoku/data/providers.dart`; PR 2 moves it to
`core/clock.dart`, because a provider two features read should not be imported out of one of them.

The mechanism that keeps `Random` out is a scanner test in `app/test/`, modelled on
`generation_call_site_test.dart` and with the same self-tests: it strips comments, then asserts
`Random(` appears in no file under `app/lib`. The existing rule was a sentence in PLAN-phase-1.md
§1; after this phase it fails a build.

### 4.4 Tuning constants

```dart
@immutable
class InvadersRules {
  const InvadersRules({required this.alienRows, required this.lives,
                       required this.baseStep, required this.minStep,
                       required this.waveRamp, required this.fireInterval,
                       required this.minFireInterval, required this.maxAlienShots, ...});

  static const InvadersRules normal = InvadersRules(alienRows: 5, lives: 3, ...);
  static const InvadersRules easy   = InvadersRules(alienRows: 3, lives: 5, ...);
}
```

Every number in §4.1 is a field here. Two consequences worth the class: easy mode is data rather
than a branch, so a test asserts the easy game by constructing it rather than by enumerating
behaviours; and the tuning pass on a device (§6, PR 8) edits one file, which is a reviewable diff
rather than a scatter of magic numbers moving by 10%.

The numbers in §4.1 are starting values, chosen to match the original cabinet's feel. They are
expected to move after the device pass, and moving them is not a plan change.

### 4.5 The Flame layer

```dart
class InvadersGame extends FlameGame {
  InvadersGame({required InvadersSim sim, required ValueListenable<PadInput> input});
  @override void update(double dt);      // §4.2, and nothing else
  @override void render(Canvas canvas);  // one pass over the sim
}
```

- The camera uses `FixedResolutionViewport(resolution: Vector2(224, 256))`, so the field letterboxes
  on any aspect ratio and the simulation's units are the only coordinates anywhere.
- `render` walks the sim: the alien bitmask, the shots, the bunker grids, the player and the UFO,
  drawing each sprite's set pixels as rectangles in one loop with no allocation per frame. Colours
  come from the theme's `AppPalette` (`arcade` is already declared, `core/ui/tokens.dart`), passed
  in at construction rather than read from a `BuildContext` the game does not have.
- Pause is `pauseEngine()` / `resumeEngine()`, which stops `update` being called at all. The
  accumulator is zeroed on resume, because the delta across a pause is not game time.
- The game holds no state of its own beyond the accumulator, per §3.

### 4.6 `OnScreenPad` and the keyboard

One value type carries intent from every input source:

```dart
@immutable
class PadInput {
  const PadInput({this.left = false, this.right = false, this.fire = false});
}
```

`OnScreenPad` is a Flutter widget below the field, exposing a `ValueNotifier<PadInput>`:

- Three buttons, each a raw `Listener` (§1, §3). A press sets its flag; `onPointerUp`,
  `onPointerCancel` and an `onPointerMove` leaving the button's bounds all clear it. Pointer ids are
  tracked per button, so a second finger arriving on FIRE cannot release LEFT.
- LEFT and RIGHT are `AppTapTargets.primary` (72 dp) at the bottom-left, FIRE is 72 dp at the
  bottom-right, and the two groups swap when `Profile.padSide` is `left` — one `Row` whose children
  are reversed, not two layouts.
- The pad is a sibling of the field in a `Column` inside `SafeArea`, so it cannot overlap the play
  field or sit under a gesture bar (§1). `PLAN.md` §4.2's "semi-transparent but never invisible"
  applies to a pad drawn over the field; a pad that has its own band does not need transparency, and
  the closing PR records that.
- Buttons carry `Semantics(label: 'Left' | 'Right' | 'Fire', button: true)`. Glyphs alone are not a
  label, and this much costs nothing to do now.

The keyboard mirror is a `Focus` node on the game screen writing the same `ValueNotifier`: arrows or
A/D to move, space to fire, P or Escape to pause (`PLAN.md` §4.2). The first key event sets
`_keyboardSeen`, which hides the pad; the next pointer-down on the screen shows it again, so a
touchscreen PC gets both. One flag, two lines, and a widget test for each direction.

Auto-fire is applied in the simulation rather than in the pad: a pad that synthesised a held FIRE
would make the cooldown depend on the frame rate, which is the bug §1's first row exists to prevent.

### 4.7 Sprites

`sprites.dart` holds each shape as a list of row bitmasks, most significant bit leftmost:

```dart
const List<int> alienFront = [0x0C30, 0x1E78, 0x3FFC, ...];   // 16 wide, 8 tall
```

Drawn as one rectangle per set bit at the current scale. This is what the original hardware did, it
needs no asset file and no licence line (§1), it is exact at any resolution, and a diff to a sprite
is a diff to numbers a reviewer can read. Swapping in drawn art later replaces this file and nothing
else.

### 4.8 `GameShell` and the game screen

`GameShell` is the widget every later game reuses (`PLAN.md` §7, §4.4). It drives one interface:

```dart
abstract interface class ArcadeGameController {
  ValueListenable<ArcadeHud> get hud;        // score, lives, wave
  ValueListenable<bool> get isOver;
  Widget buildView(BuildContext context);    // the GameWidget
  ValueNotifier<PadInput> get input;
  void pause(); void resume(); void restart();
  ArcadeResult get result;                   // score, wave, kills — what is stored
}
```

Eight members, each because `GameShell` calls it. Nothing is added for a game that does not exist
yet (§2).

The shell owns:

- **The HUD** — score, lives and wave as Flutter text above the field, so text scale and theme come
  from the app rather than from a canvas. Lives are drawn as glyphs *and* a number: a count that is
  only a row of icons is unreadable at a glance past four.
- **Pause**, from the pause button, from `P`/`Escape`, and from `AppLifecycleListener` on `inactive`
  and `paused`. A tablet taken away mid-wave comes back where it was rather than dead, and the shell
  is where that is decided so no later game re-decides it.
- **Quit confirmation** — "Stop playing?" with *Keep playing* and *Stop*. A quit that skipped
  confirmation would lose a run to a mis-tap on a 72 dp target next to the pause button.
- **The game-over card** — "Good try! Play again?" (`PLAN.md` §4.1), the run's score and wave, the
  top five for the current mode, and *Play again* and *Back*. A `ModalBarrier` sits under it for the
  reason phase 3's completion card has one (`PLAN-phase-3.md` §4.6): a tap reaching the pad behind
  it would drive a finished game. Any celebration honours `MediaQuery.disableAnimationsOf(context)`,
  which `app.dart` already or-s with the stored setting.
- **The write**, on game over and on quit alike: a run stopped at 3,000 points is still a run, and a
  score that vanished because the child pressed *Stop* is a bug they cannot report. A run worth 0 is
  not stored, because there is nothing to show.

**The game screen does not use `ScreenScaffold`**, the same exception the play screen took and for a
measured version of the same reason (`PLAN-phase-3.md` §4.5): a 40 dp display heading plus 24 dp of
padding comes off a field that also has a 72 dp control pad below it. It keeps the same `SafeArea`,
the same back control and the same tooltip, and puts the game's name in the HUD row. PR 6 measures
the field at 360 x 640 with a notch and a gesture bar and asserts a floor, as
`sudoku_play_screen_test.dart` does for the board.

### 4.9 Repository writes and the save

`ProgressRepository` gains, on the active profile, through the existing `_apply` so the 500 ms
debounce and the one-write-at-a-time queue apply unchanged:

```dart
void startArcadeGame(String gameId);                        // gamesPlayed += 1
void recordArcadeResult(String gameId, ArcadeResult result); // high scores, totalKills
void setArcadeOptions({bool? easyMode, bool? autoFire, PadSide? padSide});
```

`gamesPlayed` increments at the start because `ArcadeGameProgress.gamesPlayed` is documented as
lifetime games *started* (`save_data.dart`), and a counter that only counted finished runs would
disagree with its own name.

Three additive save changes, none of them a shape change, so **`schemaVersion` stays 1** — the same
reasoning phase 3 recorded for `mistakeFeedback` (`PLAN.md` §5.2), and `save_codec.dart` already
defaults missing keys and ignores unknown ones:

| Change | Where | Why there |
|---|---|---|
| `HighScore.easy` (bool, default false) | `save_data.dart`, read by `_readHighScore` and written inline in `_writeArcadeGame` | `PLAN.md` §4.3 wants five scores per game per difficulty. A flag keeps one table and one pair of lifetime counters; §3's table has the rejected alternative. |
| `Profile.arcadeEasyMode`, `Profile.arcadeAutoFire` | `Profile` | They belong to a child, not the tablet (§3). |
| `Profile.padSide` (`right` default, `left`) | `Profile` | Handedness is a property of the player. |

The five-entry cap applies per mode at write time, so a profile can hold ten entries: five normal
and five easy. `PLAN.md` §5.2's example block is updated at the phase close, as phase 3 updated it.

### 4.10 The arcade menu

`/arcade` replaces `ComingSoonScreen` (`app.dart`):

- An **Invaders card**, opening `/arcade/invaders`, showing this profile's best score and the wave
  it reached in the currently selected mode.
- **Three toggles**, each a `BigButton` row like the settings screen's theme choices so the
  tap-target floor and the selected drawing are one implementation: *Easy mode*, *Auto-fire*, and
  *Buttons on the left*. They sit here rather than on the settings screen because they change
  between two runs of the same game, and a child who wants an easier game should not have to leave
  the arcade to ask for one. They carry the active profile's name for the reason phase 3's mistake
  control does.
- A **top-five table** for the selected mode, empty-stated as "No scores yet — have a go!".

The route `/arcade/invaders` takes no arguments: the options are read from the profile when the run
starts, so there is no second copy to disagree with the stored one.

---

## 5. Repository layout

```
app/
├─ lib/
│  ├─ core/
│  │  └─ clock.dart                        # nowProvider, moved out of features/sudoku (§4.3)
│  ├─ routes.dart                          # + arcadeInvaders
│  └─ features/arcade/
│     ├─ arcade_menu_screen.dart           # /arcade (§4.10)
│     ├─ shared/
│     │  ├─ arcade_controller.dart         # ArcadeGameController, ArcadeHud, ArcadeResult
│     │  ├─ game_shell.dart                # HUD, pause, quit, game-over card (§4.8)
│     │  ├─ on_screen_pad.dart             # LEFT / RIGHT / FIRE (§4.6)
│     │  ├─ pad_input.dart                 # PadInput, the keyboard mirror
│     │  └─ game_rng.dart                  # seeded PRNG for one run (§4.3)
│     └─ invaders/
│        ├─ model/
│        │  ├─ invaders_sim.dart           # the whole game, pure Dart (§4.1)
│        │  ├─ invaders_rules.dart         # tuning, normal and easy (§4.4)
│        │  └─ sprites.dart                # bitmask pixel art (§4.7)
│        ├─ invaders_game.dart             # FlameGame: accumulator + one render pass (§4.5)
│        └─ invaders_screen.dart           # /arcade/invaders
├─ test/features/arcade/…                  # one file per unit above
├─ test/no_random_test.dart                # the scanner guard (§4.3)
└─ integration_test/
   └─ invaders_smoke_test.dart             # on a device, not in CI (§7)
```

Boundaries:

- **`invaders/model/` imports no Flutter beyond `foundation.dart` and no Flame**, so its tests are
  plain `test()` calls. This is the §3 decision expressed as a directory, and it is checkable by
  reading the imports of three files.
- **`shared/` holds what a second game reuses**, and `invaders/` holds what only Invaders knows.
  Phase 7 adding Brick Breaker should touch `shared/` only to add, not to change; if it has to
  change something, that is the signal `GameShell` was shaped by one game and needs reshaping then,
  with two games in hand.
- **`arcade_menu_screen.dart` sits at the feature root**, belonging to neither half. `PLAN.md` §6's
  tree shows only `shared/` and `invaders/`; the closing PR updates it.
- **`core/clock.dart` is new** because two features now need the injected clock (§4.3).

---

## 6. Pull requests

One PR per row, merged in order; each leaves the repository analysing, testing and green, and each
runs `tool/verify.sh` and a `/caveman-review` pass before it opens (`AGENTS.md`).

Estimates assume one developer working part time, roughly half a working day per unit — the same
basis as `PLAN-phase-1.md` §6, `PLAN-phase-2.md` §6 and `PLAN-phase-3.md` §6. **Total 5.75–8 days
against `PLAN.md` §7's 5–7 for the phase**, so the top of the range is over, and it is named rather
than trimmed to fit. The range is widest at PR 3, where the simulation is the largest single unit in
the phase, and at PR 8, where two criteria need hardware at two frame rates.

| # | PR | Estimate |
|---|---|---|
| 1 | [Arcade progress in the save](#pr-1--arcade-progress-in-the-save-05075-day) | 0.5–0.75 day |
| 2 | [`GameRng`, the clock, and the `Random` guard](#pr-2--gamerng-the-clock-and-the-random-guard-05-day) | 0.5 day |
| 3 | [The Invaders simulation](#pr-3--the-invaders-simulation-15175-day) | 1.5–1.75 day |
| 4 | [Flame arrives: the render layer](#pr-4--flame-arrives-the-render-layer-0751-day) | 0.75–1 day |
| 5 | [`OnScreenPad` and the keyboard mirror](#pr-5--onscreenpad-and-the-keyboard-mirror-0751-day) | 0.75–1 day |
| 6 | [`GameShell`: HUD, pause, quit, game over](#pr-6--gameshell-hud-pause-quit-game-over-0751-day) | 0.75–1 day |
| 7 | [The arcade menu](#pr-7--the-arcade-menu-05-day) | 0.5 day |
| 8 | [Device pass, smoke test and phase close](#pr-8--device-pass-smoke-test-and-phase-close-05075-day) | 0.5–0.75 day |

### PR 1 — Arcade progress in the save (0.5–0.75 day)

Commits:
1. `HighScore.easy`, `Profile.arcadeEasyMode`, `Profile.arcadeAutoFire`, `Profile.padSide` with
   codec reads that default and writes that emit them (§4.9).
2. `ArcadeResult` in `features/arcade/shared/`, and `startArcadeGame`, `recordArcadeResult`,
   `setArcadeOptions` on `ProgressRepository`.
3. Tests: five scores per mode kept and the sixth dropped only when it is worse; a normal-mode score
   never evicts an easy-mode one; `gamesPlayed` counts starts and `totalKills` accumulates; a v1
   file written before this PR decodes with every new field at its default; a zero score is not
   stored.

**Done when:** `flutter test test/core/storage` is green, and a test round-trips a save holding two
easy scores, three normal ones and all three profile options through `save_codec.dart` with
`schemaVersion` still 1.

### PR 2 — `GameRng`, the clock, and the `Random` guard (0.5 day)

Commits:
1. `game_rng.dart` (§4.3) with its sequence tested against literals, `nextInt` shown unbiased at a
   bound that does not divide 2^32, and every value masked to 32 bits.
2. `core/clock.dart`, with `nowProvider` moved off `features/sudoku/data/providers.dart` and the
   Sudoku imports updated.
3. `test/no_random_test.dart`: the scanner, its own self-tests for comments and longer identifiers,
   and the assertion over `app/lib`.

**Done when:** the same seed replays the same sequence in a test, the scanner is shown to fail
against a source containing `Random(` and to pass against `app/lib`, and no Sudoku test changed
except its import.

### PR 3 — The Invaders simulation (1.5–1.75 day)

No Flutter widgets, no Flame, no dependency added yet.

Commits:
1. `invaders_rules.dart` and `sprites.dart`.
2. `invaders_sim.dart`: player, alien block with the march, drop, reverse and speed-up, shots both
   ways, bunker erosion, UFO, lives, waves, scoring.
3. Tests: the block reverses and drops at a wall; the step interval shrinks as aliens die and hits
   its floor; a shot clears a disc from a bunker and stops; the front row scores 10 and the back 30;
   a bonus life lands at exactly 10,000; the wave after a clear starts one row lower and faster;
   easy mode has three rows and five lives by construction rather than by branch; auto-fire respects
   the cooldown.
4. **The equivalence test**: one seed, ten simulated seconds, stepped as 600 frames of 16.67 ms and
   as 1440 frames of 6.94 ms through the §4.2 accumulator, comparing score, lives, wave, every alien
   bit, every bunker bit, every shot and the player's position.

**Done when:** `flutter test test/features/arcade/invaders` is green in under two seconds, and the
equivalence test is shown to fail against a simulation stepped by raw `dt` — a determinism test that
was never seen red proves nothing (`AGENTS.md`).

### PR 4 — Flame arrives: the render layer (0.75–1 day)

Commits:
1. `flame: ^1.38.0` in `app/pubspec.yaml`, with the lock file, and a comment naming the two packages
   it adds.
2. `invaders_game.dart`: the accumulator with its 8-step clamp, `FixedResolutionViewport`, and the
   single render pass over the sim.
3. `invaders_screen.dart` with `AppRoutes.arcadeInvaders`, reachable from a temporary button on
   `/arcade` that PR 7 deletes — and this PR says so in the code, as `PLAN-phase-3.md` §6's PR 6
   did.
4. Tests: a pumped `GameWidget` advances the sim by the expected number of steps for a given frame
   sequence; the clamp discards a backlog rather than running 60 steps; `pauseEngine` stops the sim
   and resuming does not replay the paused interval.

**Done when:** `dart tool/check_offline.dart` reports no violations with `flame` and `ordered_set`
in the graph, and the game renders a playable field on the host — a run that can be driven only by
the keyboard at this point, which is what PR 5 is for.

### PR 5 — `OnScreenPad` and the keyboard mirror (0.75–1 day)

Commits:
1. `pad_input.dart` and `on_screen_pad.dart` (§4.6), with the handedness swap.
2. The keyboard mirror and the hide-on-keyboard, show-on-touch flag.
3. Tests: two simultaneous pointers move and fire in the same frame; a pointer that slides off LEFT
   clears it; `onPointerCancel` clears it; a second finger on FIRE does not release LEFT; every
   button is at least 72 dp; with a 34 dp bottom `viewPadding` no button intersects the inset; the
   pad hides after a key event and returns after a touch; the screen pumps at
   `TextScaler.linear(2.0)` with no overflow.

**Done when:** those tests pass, and on the Android device a child can hold LEFT and tap FIRE at
once, and sliding a thumb off LEFT stops the ship — the two `PLAN.md` §8 risks this PR exists to
close.

### PR 6 — `GameShell`: HUD, pause, quit, game over (0.75–1 day)

Commits:
1. `arcade_controller.dart` and `game_shell.dart` (§4.8), with `InvadersGame` implementing the
   interface.
2. Pause from the button, from `P`/`Escape` and from `AppLifecycleListener`; the quit confirmation.
3. The game-over card, and the write through `recordArcadeResult` on game over and on quit.
4. Tests: a run driven to game over stores a `HighScore` with the right score, wave and `easy` flag,
   and increments `totalKills`; quitting mid-run stores the score too; a 0-point run stores nothing;
   backgrounding the app pauses the sim and foregrounding does not skip time; the modal barrier
   stops a tap reaching the pad; the field keeps a floor at 360 x 640 with a notch and a gesture
   bar.

**Done when:** a widget test plays a run to game over by driving the pad and asserts the stored
`ArcadeGameProgress`, and a second launch over the same store shows that score on the card.

### PR 7 — The arcade menu (0.5 day)

Commits:
1. `arcade_menu_screen.dart` on `/arcade`, replacing `ComingSoonScreen` and PR 4's temporary button:
   the Invaders card with the best score, the three toggles, and the top-five table.
2. Tests: switching profile changes the scores and the toggles shown; a toggle survives a relaunch
   over the same store; the easy table and the normal table hold different entries; the empty state
   appears for a new profile.

**Done when:** every toggle persists across a relaunch, and the score shown on the card is the one
`recordArcadeResult` wrote in PR 6's test.

### PR 8 — Device pass, smoke test and phase close (0.5–0.75 day)

Commits:
1. `app/integration_test/invaders_smoke_test.dart`: launch, open the arcade, play a run through the
   pad, background and foreground the app, quit, and read the score back out of a real `save.json`.
2. The tuning pass from §4.4 after ten minutes of play on a phone and on a 144 Hz desktop, as a diff
   to `invaders_rules.dart` alone.
3. `AGENTS.md`: how to run the new integration test, and that CI still does not.
4. `PLAN.md`: phase 4 marked done; §4.1, §4.2 and §4.3 reconciled with what shipped; §5.2's schema
   block carrying `easy` and the three profile options; §6's tree carrying the arcade files; §7's
   phase-4 entry with the outcome and everything that differed. `PLAN-phase-4.md` gets the closed
   banner.

**Done when:** ten minutes of play on the Android device and on a 144 Hz desktop shows no jank and
no stuck ship, scores survive a restart on both, and `PLAN.md` §7's phase-4 done-criterion is quoted
with its result — including any clause that was not met.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| The ship keeps moving after a finger leaves LEFT | Medium | `PLAN.md` §8 already names it. Three release paths — up, cancel, and move-outside — with a test for each (§1, PR 5), because the third is the one Flutter's routing makes easy to miss. |
| Flutter's gesture arena claims the second pointer, so move-and-fire fails on a cheap device | Medium | Raw `Listener` per button, which never enters the arena (§3), and a two-pointer widget test. The device pass in PR 5 is what confirms it on hardware, since the arena is not what a widget test simulates most faithfully. |
| Game speed differs between a 60 Hz phone and a 144 Hz desktop | Medium | The fixed step (§4.2) and the equivalence test (PR 3), which is required to be seen failing against a `dt`-stepped simulation. The device pass covers the renderer, which the test does not. |
| A long stall makes the accumulator chase itself into a spiral | Medium | The 8-step clamp discards the backlog (§4.2), with a test that a 500 ms frame advances 8 steps and not 60. |
| Frame budget: ~150 rectangles a frame on a cheap tablet | Medium | One render pass with no component tree (§3) is the mitigation that is designed in; the measurement is the device pass in PR 8. Unmeasured until then, and said so rather than given a number now. If it does not hold, the bunkers are the obvious thing to cache as a picture — they change rarely and are the largest share of the rectangles. |
| `flame` drags in something the offline check refuses | Low | Already checked before this plan was written: `flame 1.38.0` adds itself and `ordered_set 8.0.1`, neither in any of `check_offline.dart`'s lists, which are denylists with no allowlist to maintain (§1). PR 4 runs the check as its done-criterion anyway. |
| The simulation and the renderer drift into two copies of the state | Medium | The renderer holds no state by construction (§3, §4.5), which is a boundary a reviewer can check by reading `invaders_game.dart`'s fields: an accumulator, a sim and an input listenable. A position cached there is the finding. |
| A run is unreproducible, so a reported bug cannot be chased | Low | The seed is the only entropy, and it comes from the injected clock (§4.3), so fixing the clock replays the run exactly. Nothing writes the seed to the save; reproducing a child's run is not a goal. |
| Easy mode is really a second game nobody plays, or too close to normal to matter | Low | Both modes are the same `InvadersRules` shape (§4.4), so the difference is a table a reviewer reads. Whether the numbers are right is a device question, answered in PR 8. |
| High scores grow the save | Low | Five per mode, capped at write time (§4.9), with a test. Ten entries per game per profile is well inside `PLAN.md` §5.2's few kilobytes. |
| No emulator in CI, so `integration_test/` never runs on a merge | Medium | Unchanged from phase 3 and accepted again: the widget-level run in PR 6 covers the same path on every commit, `AGENTS.md` says how to run the device test, and an emulator job stays `PLAN.md` §9's open question. |
| Scope creep from phase 5 — sound, haptics, landscape — or from phase 7's games | Medium | §2 lists each with its phase. A `flutter_soloud` line in this phase's `pubspec.yaml` diff, or a second game directory under `features/arcade/`, is the tell. The release line is fixed at phase 6 (`PLAN.md` §7). |
| `GameShell` is shaped by one game and fits no other | Medium | Accepted deliberately (§2): six members, each because the shell calls it. Phase 7's first game is when it gets reshaped, with two games in hand rather than one and a guess. |

---

## 8. Verification checklist

Ticked at PR 8, against a run rather than a memory of one. Anything needing hardware stays open
until it has been done on hardware, as phase 3's did.

- [ ] `tool/verify.sh` passes from a clean checkout.
- [ ] `cd app && flutter test` passes in under 40 s.
- [ ] `dart tool/check_offline.dart` reports no violations with `flame` in the graph, and names no
  package beyond `flame` and `ordered_set` as new.
- [ ] `dart tool/check_determinism.dart` still passes — phase 4 touches no engine file.
- [ ] `test/no_random_test.dart` passes, and is shown to fail against a source containing `Random(`.
- [ ] The equivalence test compares a full ten seconds of state between 60 Hz and 144 Hz frame
  sequences, and is shown to fail against a `dt`-stepped simulation.
- [ ] A widget test drives two simultaneous pointers and asserts move and fire in one frame.
- [ ] A widget test slides a pointer off LEFT and asserts the ship stops.
- [ ] A widget test pumps the game screen with a 34 dp bottom `viewPadding` and asserts no button
  intersects the inset.
- [ ] A widget test plays a run to game over and asserts the stored `HighScore`, `gamesPlayed` and
  `totalKills`, then relaunches over the same store and finds the score on the card.
- [ ] A save written before this phase decodes with `easy`, `arcadeEasyMode`, `arcadeAutoFire` and
  `padSide` at their defaults, with `schemaVersion` still 1.
- [ ] On the Android device: ten minutes of play with no jank and no stuck ship.
- [ ] On a 144 Hz desktop: ten minutes of play at the same speed as the phone, judged against the
  wave the run reaches at the same elapsed time rather than by eye.
- [ ] On the Android device: high scores and the three options survive a force-quit and relaunch.
- [ ] On the Android device: a six-year-old plays a run unaided with the on-screen controls
  (`PLAN.md` §9).
- [ ] `app/integration_test/invaders_smoke_test.dart` passes on the device; `-d flutter-tester` is
  evidence, not a substitute (`AGENTS.md`).
- [ ] `PLAN.md` §4, §5.2, §6 and §7 match what was built, and this file carries its closed banner.

---

## 9. Open questions

| Question | Current assumption | What resolves it |
|---|---|---|
| Is 1/120 s the right fixed step? | Assumed yes (§3): it divides 60 Hz exactly and halves 144 Hz judder against 1/60 s. | The 144 Hz device pass in PR 8. Changing it is one constant, and the equivalence test does not depend on its value. |
| Are the §4.1 starting numbers playable for a six-year-old? | Assumed roughly right, copied from the original cabinet's feel, with easy mode as the real answer for a small player. | PR 8's tuning pass, and `PLAN.md` §9's "a six-year-old can play Invaders unaided". Moving them is a diff to `invaders_rules.dart` alone (§4.4). |
| Should easy-mode scores appear beside normal ones, or only when easy mode is on? | Assumed the menu shows the selected mode's table only, so a child who plays easy is not shown a table they cannot reach. | PR 7's review; it is a query in the menu, not a schema question — both tables are stored either way (§4.9). |
| Should the pad start visible on desktop? | Assumed yes, hidden after the first key event and restored on the next touch (`PLAN.md` §4.2), so a touchscreen PC gets both. | PR 5's desktop pass. |
| Does quitting mid-run deserve a high-score entry? | Assumed yes (§4.8): a run stopped at 3,000 points is still a run, and the five-cap keeps junk out. | PR 6's review. Reversing it is one branch. |
| Should `gamesPlayed` count a run the child quits in the first second? | Assumed yes — the field is documented as games *started* (`save_data.dart`), and a counter that disagrees with its own name is worse than a slightly generous number. | Decided unless PR 1's review objects. |
| Does CI gain an Android emulator job so `integration_test/` runs on merges? | Assumed no again, as in phase 3. | A phase-6 decision, when release checks need device evidence anyway (`PLAN.md` §9). |

---

## 10. Starting order

1. **PR 1 — the save fields and the repository writes.** Everything above stores through them, and
   the two schema-shaped questions — where the mode flag lives and where the three options live —
   have to be answered before a child's file can hold either.
2. **PR 2 — `GameRng`, the clock and the `Random` guard.** Small, and it is what makes PR 3's tests
   deterministic; writing it after the simulation would mean rewriting the simulation's entropy.
3. **PR 3 — the simulation.** The largest unit in the phase, and the one every later PR draws,
   pauses or stores. It lands before `flame` is added on purpose: a simulation written after the
   dependency arrives is a simulation that quietly grows a dependency on it.
