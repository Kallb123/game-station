# Phase 7 — Snake, with counting

**Closed, with hardware criteria unmet and named. Kept as the record of a finished phase, not as
current plan.** [`PLAN.md`](PLAN.md) is the source of truth for what the project is doing now; §7
there carries the phase-7-snake outcome and everything that differed from this file, and §4.4, §5.2
and §6 have been reconciled with what was built. The unmet criteria are every hardware line in §8
below — no Android phone, tablet or desktop display was available in this or any session that built
this game, the same gap phases 3, 4 and 5 each recorded rather than assumed shut — plus the
ten-minutes-of-play tuning pass PR 7 reserved for `snake_rules.dart`, which made no change because
there was no play on hardware to base one on. Read this file for *why* a piece of
`app/lib/features/arcade/snake` and the shared reshape around it is shaped the way it is — the code
cites these section numbers.

The plan for `app/lib/features/arcade/snake`: the second arcade game, the first reshape of the
shell and pad built around the first one, and a counting mode in which the things the snake eats are
the numbers 1 to 10, then 11 to 20, then 21 to 30, one decade per level.

[`PLAN.md`](PLAN.md) §4.4 is the design this expands — Snake's row there reads *"four directions or
swipe; persisted: high score, longest snake"* — and §7's phase 7 is "one game per minor release,
each reusing `GameShell` and `OnScreenPad`". [`PLAN-phase-4.md`](PLAN-phase-4.md) is the file to read
first: it built the shell, the pad, the fixed step and the save shape this game inherits, and its §2
and §5 name this phase as the moment those get reshaped "with two games in hand rather than one and
a guess". Where this file and `PLAN.md` disagree, the reason is stated here and the closing pull
request updates `PLAN.md`.

**Named `PLAN-phase-7-snake.md`, not `PLAN-phase-7.md`.** Phase 7 is a container for several games
arriving one per minor release, so a single phase file would either grow a section per game or be
rewritten by each one. One file per game keeps a finished game's reasoning frozen where its code
cites it, which is the property `AGENTS.md` asks of a phase plan.

**Release line unchanged:** `PLAN.md` §7 ships at phase 6, and phase 7 is what follows it. Nothing
here blocks or advances that.

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
| The game teaches counting without becoming a worksheet | The reason this game is in this app rather than any snake. Counting mode puts the next number and two later ones on the field at once, so the child chooses rather than follows; the choice is the teaching. It stays a game: the snake still grows, still speeds up, still ends. |
| A wrong choice costs nothing | `AGENTS.md`'s "no scary failure states", applied to the one new way this game can be failed at. Only the next number in the sequence is edible; the others are scenery the snake passes over with a soft cue. There is no wrong-number penalty to tune, and no toggle for one (§3). |
| Game speed is independent of frame rate | `PLAN.md` §4.1, unchanged from phase 4 and enforced the same way. Snake's timers are **integer counts of fixed steps** rather than seconds (§4.2), so the 60 Hz and 144 Hz runs the equivalence test compares are identical by construction rather than by floating-point luck. |
| Controls are on-screen buttons, like Invaders | The user-facing ask, and `PLAN.md` §4.2's rules apply unchanged: 72 dp targets, raw `Listener` per button, release on up, cancel and move-outside, safe areas, never over the play field. Snake needs four directions, which is a `PadInput` and an `OnScreenPad` layout this phase adds (§4.6). |
| A change to `shared/` is an addition, not a rewrite | `PLAN-phase-4.md` §5. Every shared change in §4.7 is a new field with a default or a new enum value; no existing call site changes behaviour, and the Invaders suite stays green untouched except for the import line two of its files change when the fixed step moves (§4.7). |
| Screen size cannot change gameplay | The field is a fixed grid of 14 x 16 cells of 16 virtual units — the same 224 x 256 virtual field Invaders letterboxes into, through the same `CameraComponent.withFixedResolution` (§4.2). A phone and a tablet play the same board. |
| No new package | Everything this game needs — Flame, the shell, the pad, the seeded PRNG, the audio wrapper — is already in the tree. `app/pubspec.yaml` does not change, so `tool/check_offline.dart` has no new graph to audit. |
| No new asset except four sounds | Numerals are drawn from a 3 x 5 bitmask glyph table (§4.5), the same trick as `invaders/model/sprites.dart` and for the same reasons: no binary in a diff, no licence line, exact at any resolution. The four sounds are synthesised by `tool/audio/generate_motifs.py` like the other fifteen (§4.10). |
| No ambient randomness | `PLAN-phase-1.md` §1 and `app/test/no_random_test.dart`. Target placement draws from `GameRng` seeded from the injected clock, so a test replays a run exactly. Free cells are found by a row-major scan of the grid, never by iterating a `Set` or `Map`. |
| Tap targets: 72 dp for every direction button | `PLAN.md` §4.2, `AppTapTargets.primary`. A four-way pad has more buttons in the same band than a three-button one, so this is the constraint most likely to be squeezed; §4.6 places them and a widget test asserts each one's size and that none intersects a 34 dp bottom inset. |
| The save stays a few kilobytes | `PLAN.md` §5.2. Snake adds one profile field, one flag on `HighScore` and one counter on `ArcadeGameProgress` (§4.8). Its top-five tables split two ways over easy mode and two over counting, so a profile that plays all four holds twenty snake entries — a hundred-odd bytes each. |
| `tool/verify.sh` green before every commit | It is what CI runs, in the same order (`AGENTS.md`). `PLAN-phase-5.md` §1 budgeted the app suite at 60 s and its close measured 62 s — at the edge rather than inside it. This phase adds a simulation suite of plain `test()` calls (no widget tree; a ten-second run is 1200 fixed steps and costs single-digit milliseconds), four widget tests, and one more route for `layout_sweep_test.dart`, which is the expensive kind. §8 records the measured time rather than assuming it stayed put. |

---

## 2. Non-goals

| Not in this phase | Where it belongs |
|---|---|
| Swipe control on the field | `PLAN.md` §4.4 says "four directions **or** swipe", and the ask is on-screen buttons like Invaders. A swipe recogniser on the field also enters the gesture arena the pad was built to stay out of (`PLAN-phase-4.md` §3), so it is a design question of its own rather than a second input path added in passing. §9 keeps it as a question. |
| Times tables, addition, subtraction, counting down | The ask is a sequence of numbers to eat in order. Counting up in ones and in twos is that; an arithmetic mode is a different game wearing this one's skin, and would need its own answer to "what does a wrong answer cost". §9 records counting down as the cheapest of them if it is ever wanted. |
| Speaking the number aloud | No text-to-speech package would pass `PLAN.md` §2's dependency rules, and fifty pre-rendered number recordings is an asset library, not a motif. The numeral, the HUD line and its `Semantics` label are what a child gets. |
| Obstacles, mazes, walls inside the field, portals | Classic snake plus counting is the game. Each of these is a new failure mode for a five-year-old to run into. |
| Two-player, or a second snake | No second control scheme, and no second pad. |
| Gamepad support | `PLAN.md` §4.2 defers it past the first release, unchanged here. |
| A per-game easy mode | `Profile.arcadeEasyMode` is one arcade-wide flag (`PLAN.md` §5.2), and it stays one. A child who wants an easier arcade wants an easier arcade; splitting it per game doubles the toggles on the menu to say something nobody asked. |
| Reshaping `ArcadeGameController` | Its eight members carry Snake as they carry Invaders. The two shell-level things Snake needs — a word for what "wave" is called and a line for "Next 7" — are §4.7's two additions, not a ninth member. |
| Any change to `packages/puzzle_engine` | This phase does not touch it. `generatorVersion` stays 1, no golden moves, `tool/check_determinism.dart` has nothing new to scan. |
| A new schema version | Every save change in §4.8 is an additive optional field, so `schemaVersion` stays 1 — the same reasoning phases 3, 4 and 8 recorded (`PLAN.md` §5.2). |

---

## 3. Approach

Build bottom-up, as phases 2, 3 and 4 did, and settle the two questions that reach a child's save
file before anything can write one:

1. **The save fields** — where the counting choice lives, how the top-five tables split, where
   "longest snake" is kept.
2. **The shared reshape** — four-way `PadInput`, the D-pad layout, the HUD's extra line, the shell's
   word for "wave", and the fixed-step accumulator moved where two games can share it.
3. **`SnakeSim`** — the whole game as plain Dart: the grid, the turn queue, growth, collisions,
   lives, levels, scoring, and the counting sequence with its decoys.
4. **The Flame layer** — `SnakeGame` drives the sim on the shared accumulator and draws it in one
   pass, including the numerals.
5. **The arcade menu** — two game cards, each with its own options and its own top five.
6. **Sound and haptics** — four motifs, and a buzz on the two moments worth feeling.
7. **The device pass, the smoke test and the close.**

**The load-bearing decision, inherited rather than re-made: the simulation is pure Dart and holds
all the state; Flame renders it and owns nothing** (`PLAN-phase-4.md` §3). Everything that made that
worth doing for Invaders holds here — a ten-second run is 1200 `step()` calls with no widget tree, a
run is replayable from its seed, and the renderer cannot drift from the state because it has none.

**The decision this phase does make: counting is a property of the run, fixed when it starts, and
the only thing a wrong choice costs is time.** Both halves matter. A run whose counting mode could
change mid-play would produce a score that means nothing and a high-score entry that cannot be
labelled; the mode is read from the profile when the run is built, exactly as easy mode and
auto-fire already are (`PLAN-phase-4.md` §4.10). And a wrong number that cost a life would turn a
counting game into a test — the child who most needs to practise is the one who would lose fastest.
Making only the next number edible removes the punishment *and* the toggle that would otherwise be
needed to switch it off.

Alternatives considered:

| Option | Rejected because |
|---|---|
| Steer with LEFT and RIGHT as relative turns, so `PadInput` and `OnScreenPad` need no change at all | The strongest possible reuse, and wrong for the audience. Relative steering means the button that turns the snake down is a different button depending on which way it is already going, which is the thing a five-year-old cannot hold in their head while also looking for the number 7. It also makes a mis-tap unrecoverable at speed. Absolute four-way control is what `PLAN.md` §4.4 names, and the shared cost is two fields and a layout (§4.7). |
| A 2 x 2 block of arrow buttons rather than a plus | A diamond puts each arrow where its direction points, which is the only arrangement a child does not have to read. §4.6 has the geometry. |
| Eat any number, and score only when it is the right one | Keeps classic snake's "food is food" rule, and teaches nothing: a child who eats every number in reach still finishes the level, so the ordering is decoration. Only the next number being edible is what makes finding it the game. |
| Eating out of order costs a life, switched off by a "gentle" toggle | A third mode axis on the score table, a fourth toggle on the menu, and a punishment for exactly the mistake the game exists to practise (§1). |
| Show only the next number, with nothing else on the field | Simpler to build and it is the easy-mode row of the rules table (§4.4), so it exists — but as the normal game it is a treasure hunt rather than a counting game: with one target on screen there is no ordering decision to make. |
| Show all ten of the level's numbers at once | The most number-line-like, and it fills a 224-cell board with scenery a growing snake then has to thread. Three targets is the number that fits a decision on a small screen; it is `visibleTargets` in the rules table, so the device pass can move it. |
| Counting in twos as its own high-score table | Counting in twos changes which numerals are drawn and nothing else: the same ten targets per level, the same growth, the same score. Splitting the table would divide a child's five best runs across two lists that mean the same thing. §4.8 splits on counting on/off only, and says so where the flag is declared. |
| Two booleans on the profile — "numbers" and "count in twos" | Two booleans can encode "count in twos while numbers are off", a state with no meaning that the decoder would then have to have an opinion about. One three-valued enum cannot (§4.8), and the menu still draws it as the two toggles the ask names (§4.9). |
| Timers in seconds, like `InvadersRules` | Invaders' march interval is a duration a designer thinks in, and its accumulation across steps is exact enough at the scales it uses. Snake's move interval *is* the game's clock — every position derives from how many steps have passed — so it is an integer count of fixed steps (§4.2). That makes 60 Hz and 144 Hz identical by construction, and makes a speed-up a subtraction of whole ticks rather than a float that lands differently on two machines. |
| A `TextPaint`/`TextComponent` for the numerals | It draws with the app's real font, and it either lays out text every frame or caches components in the renderer — state, which §3's inherited decision exists to keep out. A 3 x 5 grid glyph is also more legible than a UI font shrunk into a 16-unit cell, which is the size that actually has to be read (§4.5). |
| A separate game id per counting mode (`"snake-numbers"`) | Rejected for the reason `PLAN-phase-4.md` §3 rejected `"invaders:easy"`: it splits `gamesPlayed`, `totalKills` and `bestLength` across entries that then need adding up at every read. |
| Leaving `maxStepsPerFrame` and the accumulator in `invaders_game.dart` and writing a second copy for Snake | Two copies of the one piece of arithmetic the whole fixed-step guarantee rests on, one of which has an equivalence test and one of which does not. §4.7 moves it to `shared/fixed_step.dart` with no behaviour change. |

---

## 4. Design

### 4.1 The simulation

`SnakeSim`, in `features/arcade/snake/model/`, importing nothing but
`package:flutter/foundation.dart` for `@immutable` — no Flame, no widgets, no clock:

```dart
class SnakeSim {
  SnakeSim({
    required SnakeRules rules,
    required SnakeCounting counting,
    required int seed,
  });

  void step(PadInput input);      // advances exactly one fixed step; nothing else advances it

  int  get score;
  int  get lives;
  int  get level;                 // 1, 2, 3 … — the HUD's "Level", ArcadeResult.wave
  int  get eaten;                 // targets eaten this run, for ArcadeGameProgress.totalKills
  int  get longest;               // longest body this run, for ArcadeGameProgress.bestLength
  bool get isOver;

  List<Cell>       get body;      // head first
  SnakeDirection   get heading;
  List<SnakeTarget> get targets;  // one in classic mode, up to `visibleTargets` in counting
  int  get nextValue;             // the number to eat next; 0 in classic mode
  bool get isRespawning;          // the short pause after a crash

  List<SnakeEvent> drainEvents(); // ate, notYet, crashed, levelCleared
}
```

The rules, all in cells and fixed steps over the 14 x 16 grid (§4.2):

- **The snake** starts `startLength` cells long in the middle of the field, heading right, and moves
  one cell every `moveTicks` fixed steps (§4.2).
- **A turn** is requested by a direction that is newly held — an edge, not a level. `step()` compares
  this input with the previous one, so a button held down for twenty steps queues one turn, and a
  child resting a finger on UP does not consume the queue. A 180-degree reversal is refused, because
  it is always instant death and never what was meant.
- **The turn queue holds two entries.** Rounding a corner means pressing UP then RIGHT inside one
  move interval, and a queue of one would drop the second; a queue of two applies one per move.
  Deeper is worse: three buffered turns played out over three moves is a snake that no longer obeys
  the button being pressed now.
- **Eating** the next target grows the snake by `growPerTarget` cells, scores `pointsPerTarget`, and
  spawns a replacement (§4.3). Growth is applied by not removing the tail for that many moves, so
  the body never teleports.
- **Crossing a target that is not next** — only possible in counting mode — does nothing except emit
  `SnakeEvent.notYet` and set that target flashing for `flashTicks`. It fires on entering the cell,
  not on every step inside it, so a snake parked on a decoy makes one sound.
- **A crash** is the head entering its own body, or a wall when `wrapWalls` is false. It costs a
  life, emits `SnakeEvent.crashed`, and starts a `respawnTicks` pause after which the snake is put
  back at `startLength` in the middle of the field heading right. **Score, level, the counting
  position and the targets on the field all survive a crash**: a child who has counted to 7 and hit
  a wall has not stopped knowing what comes after 7, and making them start the decade again is the
  punishment §1 exists to avoid.
- **Wrapping**, when `wrapWalls` is true, moves the head to the opposite edge instead of crashing.
- **A level clears** when the last of its `targetsPerLevel` targets is eaten: `levelBonus` is scored,
  `SnakeEvent.levelCleared` is emitted, the level number goes up, the counting sequence advances a
  decade (§4.3), and the snake keeps its length. The next level is faster (§4.4).
- **The run ends** when the last life is lost. There is no bonus life: Invaders' 10,000-point rule
  belongs to a game where points arrive in hundreds.

Collisions are cell equality, evaluated once per **move**, in a fixed order: wall or wrap, then the
snake's own body, then the target under the head. The order is part of the behaviour, so it is
stated here and asserted by the equivalence test rather than left to whichever loop was written
first.

**Nothing in the simulation reads a clock.** `step()` advances one fixed step; the accumulator that
decides how many times to call it lives in the shared driver (§4.7), which is the only place a
wall-clock delta exists at all.

### 4.2 The field, the grid and the tick

```dart
const int columns = 14;
const int rows = 16;
const double cellSize = 16;
const double fieldWidth = columns * cellSize;   // 224
const double fieldHeight = rows * cellSize;     // 256
```

The same 224 x 256 virtual field Invaders uses, for the same reason and through the same
`CameraComponent.withFixedResolution` — a phone and a tablet run the same game (`PLAN.md` §4.1). 224
cells is enough board for a snake that has eaten thirty things and still leaves room to turn; 16
units is enough cell for a three-digit numeral drawn from a 3 x 5 glyph (§4.5).

Timing is counted in fixed steps, not seconds:

```dart
int moveTicksAt(int level, int eatenThisLevel) =>
    (startMoveTicks - levelRampTicks * (level - 1) - perTargetTicks * eatenThisLevel)
        .clamp(minMoveTicks, startMoveTicks);
```

At the shared `fixedStep` of 1/120 s (§4.7), 20 ticks is one cell every 167 ms and 8 ticks is one
every 67 ms. Both ramps subtract whole ticks, so every speed the game can reach is exact on every
machine, and the equivalence test compares integers rather than floats that were accumulated in a
different order.

### 4.3 Counting mode

```dart
/// What a run counts, fixed when the run starts (§3).
enum SnakeCounting { off, ones, twos }
```

| Mode | Level 1 | Level 2 | Level n |
|---|---|---|---|
| `off` | one target, no numeral | the same | the same |
| `ones` | 1, 2, 3 … 10 | 11, 12 … 20 | 10(n−1)+1 … 10n |
| `twos` | 2, 4, 6 … 20 | 22, 24 … 40 | 20(n−1)+2 … 20n |

Every mode is `targetsPerLevel` targets per level, so a level is the same amount of play and the
same score in all three — which is why §4.8 splits the score table on counting on/off and not on
which step it counted in.

On the field in counting mode: the next number, plus up to `visibleTargets - 1` **decoys** drawn by
`GameRng` from the values still to come in this level. Decoys are drawn rather than taken in order,
so the field shows 4 alongside 8 and 9 rather than always 4, 5, 6 — the choice is a real one. Only
the next number is edible; a decoy is scenery until the sequence reaches it, at which point it is
already on the field and simply becomes the next. When fewer values remain than slots, fewer targets
show, so the last target of a level is alone on the board.

Placement is uniform over free cells: the grid is scanned row-major into a list of cells holding
neither snake nor target, and `GameRng.nextInt` picks an index. A scan rather than rejection
sampling, because a nearly full board makes rejection unbounded; a list rather than a `Set`, because
`PLAN.md` §3.1's determinism rule is a habit this repository keeps everywhere, not only in the
engine.

The HUD carries `Next 7` as text (§4.7), which is what a child who cannot yet read a 16-unit numeral
at arm's length has, and what a screen reader says.

### 4.4 Tuning constants

```dart
@immutable
class SnakeRules {
  const SnakeRules({required this.lives, required this.startLength,
                    required this.growPerTarget, required this.startMoveTicks,
                    required this.levelRampTicks, required this.perTargetTicks,
                    required this.minMoveTicks, required this.wrapWalls,
                    required this.targetsPerLevel, required this.visibleTargets,
                    required this.pointsPerTarget, required this.levelBonus,
                    required this.respawnTicks, required this.flashTicks});

  static const SnakeRules normal = SnakeRules(...);
  static const SnakeRules easy   = SnakeRules(...);
}
```

| Field | `normal` | `easy` | What it is |
|---|---|---|---|
| `lives` | 3 | 5 | Matching `InvadersRules` |
| `startLength` | 3 | 3 | Cells, at the start and after a crash |
| `growPerTarget` | 2 | 1 | Cells added per target eaten |
| `startMoveTicks` | 20 | 32 | Fixed steps per cell at level 1 with nothing eaten — 167 ms and 267 ms |
| `levelRampTicks` | 2 | 1 | Ticks faster per level |
| `perTargetTicks` | 1 | 0 | Ticks faster per target eaten within a level; easy mode holds one speed for the whole level |
| `minMoveTicks` | 8 | 16 | The floor — 67 ms and 133 ms |
| `wrapWalls` | false | true | Easy mode's snake reappears on the far side instead of crashing |
| `targetsPerLevel` | 10 | 10 | A decade, in both modes (§9) |
| `visibleTargets` | 3 | 2 | Targets on the field in counting mode: the next, plus decoys |
| `pointsPerTarget` | 10 | 10 | |
| `levelBonus` | 50 | 50 | |
| `respawnTicks` | 60 | 60 | Half a second of stillness after a crash, so the child sees what happened |
| `flashTicks` | 24 | 24 | How long a "not yet" target stays highlighted |

Every number in §4.1 and §4.3 is a field here rather than a literal at its call site, for the two
reasons `PLAN-phase-4.md` §4.4 gives: easy mode is data a test constructs rather than a branch a test
enumerates, and the device-pass tuning is a diff to one file. These are starting values, chosen to
be slow — a game a five-year-old finds too slow is a game they can still play, and the ramp is what
the device pass moves (§9).

### 4.5 The Flame layer and the numerals

```dart
class SnakeGame extends FlameGame implements ArcadeGameController {
  SnakeGame({required SnakeSim sim, required this.seed, required this.input,
             required Color color, required this.audio, required this.haptics});
}
```

The same shape as `InvadersGame`, and for the same reasons (`PLAN-phase-4.md` §4.5): the accumulator
and one child `Component` in `world`, so the fixed-resolution viewport's transform applies for free;
every colour taken at construction, because a `FlameGame` has no `BuildContext`; `pauseEngine` /
`resumeEngine` for pause, with the accumulator zeroed on resume.

`render` walks the sim once per frame: the body cells, the head (drawn with eyes, so which way it is
going is visible without inferring it from movement), each target as a filled cell, and each target's
numeral as rectangles from a glyph table:

```dart
// snake/model/digits.dart — 3 wide, 5 tall, most significant bit leftmost
const List<List<int>> digitGlyphs = [
  [0x7, 0x5, 0x5, 0x5, 0x7],   // 0
  ...
];
```

A three-digit number is 11 glyph pixels wide including gaps, which fits a 16-unit cell at 1.4 units
per pixel. Values reach three digits at level 10 counting in ones and level 5 counting in twos, so
this is a case the game reaches in ordinary play rather than a theoretical one, and §8 has a test
that renders 100 and 200 and asserts the drawn extent stays inside the cell.

Colour comes from `AppPalette.arcade`, as Invaders' does, with the head, the body, the next target
and a decoy distinguished by **fill and outline as well as hue** — a decoy is outlined and dim, the
next target is filled and carries the numeral at full contrast. Colour-blindness cannot be the only
signal (`PLAN-phase-5.md`'s accessibility pass), and here it need not be: the numeral itself is the
content.

### 4.6 The D-pad

`OnScreenPad` gains a layout rather than a second widget (§4.7):

- `PadLayout.lateral` — LEFT, RIGHT and FIRE, exactly what phase 4 built and what Invaders keeps.
- `PadLayout.dPad` — UP, DOWN, LEFT and RIGHT in a diamond; no FIRE, because Snake has nothing to
  fire.

The diamond puts each arrow where its direction points: UP above, DOWN below, LEFT and RIGHT either
side, each `AppTapTargets.primary` (72 dp) with `AppSpacing.sm` between them, giving a 232 dp square
before padding. In portrait it sits in the pad's band below the field, on the side `Profile.padSide`
chooses. In landscape it takes the `padSide` rail and the opposite rail becomes a spacer of equal
width, so the field stays centred rather than sliding off to one side (`PLAN-phase-5.md` §4.8 built
the two-rail landscape pad; this is that layout with one rail empty).

Each button is the same `_PadButton` phase 4 wrote — the same raw `Listener`, the same per-pointer
id, the same three release paths, the same `Semantics` label. Nothing about the pad's input handling
changes; only which buttons exist and where they sit.

The keyboard mirror gains up and down: arrows or W/S alongside the existing arrows and A/D, and P or
Escape still pauses through `GameShell`. The pad still hides on the first key event and returns on
the next pointer-down over the field.

### 4.7 What changes in `shared/`

`PLAN-phase-4.md` §5 said a second game should touch `shared/` "only to add", and that a change
means the shell was shaped by one game and gets reshaped now, with two in hand. Five changes, each
additive, none altering an existing call site's behaviour:

| Change | Why | What it costs Invaders |
|---|---|---|
| `PadInput` gains `up` and `down`, defaulting false | Four-way control (§4.6) | Nothing; `PadInput.none` and every existing construction are unchanged |
| `OnScreenPad` gains `layout`, defaulting `PadLayout.lateral` | The D-pad (§4.6) | Nothing; the default is today's pad, and its tests are untouched |
| `PadKeyboardMirror` gains up and down keys | The keyboard half of the same | Nothing; Invaders never holds them |
| `ArcadeHud` gains `note`, a string defaulting `''`, drawn after the wave and included in the `Semantics` label | Snake's `Next 7`. A game-specific line drawn *inside* the field would not scale with text size and would not be read aloud | Nothing; an empty note draws nothing |
| `GameShell` gains `waveLabel`, defaulting `'Wave'` | Snake counts levels, and a HUD that called them waves would be the shell telling the child the wrong word | Nothing; Invaders passes nothing |

And one move, with no change to any arithmetic: `shared/fixed_step.dart` takes over the three pieces
that are currently split between two files — `maxStepsPerFrame` and the frame-to-step accumulator
from `invaders_game.dart`, and the `fixedStep` constant from `InvadersSim`, where it is a static
const the simulation happens to own. Both games then step on one implementation rather than two
copies of the arithmetic the whole frame-rate guarantee rests on (§3).

The accumulator that moves is the one that shipped, **not** the subtractive form `PLAN-phase-4.md`
§4.2 sketched: it keeps a running total of frame time and a count of the steps already taken from
it, because subtracting a leftover each frame rounds 60 Hz and 144 Hz to different remainders at
exactly the point their totals should agree (`PLAN.md` §4.1). Moving it is a cut and a paste; the
call sites in `invaders_sim.dart` swap `fixedStep` for the imported constant, the two Invaders tests
that name `maxStepsPerFrame` change their import line, and the equivalence test must be seen still
green — and still red against a `dt`-stepped simulation — before the move is trusted.

### 4.8 The save

Three additive changes, no shape change, so **`schemaVersion` stays 1** — the same reasoning phases
3, 4 and 8 recorded (`PLAN.md` §5.2), and `save_codec.dart` already defaults missing keys and
ignores unknown ones:

| Change | Where | Why there |
|---|---|---|
| `Profile.snakeCounting`, a `SnakeCounting` encoded as `off` / `ones` / `twos`, defaulting `ones`, with an unknown string decoding to the default | `Profile` | It belongs to a child, not to the tablet — the same argument that put `mistakeFeedback` and the three arcade options there. One enum rather than two booleans, because two booleans can encode a state with no meaning (§3). The default is `ones` because counting is why this game is in this app; a child who wants plain snake turns it off |
| `HighScore.counting`, a bool defaulting false | `save_data.dart`, beside `easy` | A counting run travels further per point than a classic one, so the two are not comparable and share no table. A flag rather than a second game id, for the reason `PLAN-phase-4.md` §3 gives. Counting in twos sets the same flag as counting in ones (§3) |
| `ArcadeGameProgress.bestLength`, an int defaulting 0 | `save_data.dart`, beside `totalKills` | `PLAN.md` §4.4 persists "longest snake". It is a lifetime best like `totalKills`, updated from every run whether or not the run made the top five — a per-entry length would lose the longest snake of a run that scored badly, and would leave one number with two places to look for it |

`ArcadeResult` gains `counting` and `length` with the same defaults, so one run reports what the
repository needs to write. `ProgressRepository.recordArcadeResult` writes `counting` onto the entry,
caps the top five **within one `(easy, counting)` pair**, and raises `bestLength` by `max`.
`startArcadeGame('snake')` counts a start exactly as it does for Invaders.

`ArcadeGameProgress.totalKills` counts targets eaten for Snake. The field's own comment already reads
"aliens (or the equivalent) destroyed"; renaming a key in a shipped save format to say "things eaten"
would be a migration bought for a word.

### 4.9 The arcade menu

`arcade_menu_screen.dart` is where a second game is first visible, and where phase 4's one-game shape
has to give:

- **Two cards, one per game**, each carrying its own name, its own best score *for the mode the
  toggles currently select*, its own Play button, its own options, and its own top five. The
  top-five table moves onto the cards from the section it had to itself, because with two games a
  table with no game on it cannot be read.
- **The Snake card also shows the longest snake**, `ArcadeGameProgress.bestLength` (§4.8), beside the
  best score. `PLAN.md` §4.4 asks for it to be persisted, and a number written to a child's save that
  no screen ever shows is the kind of control-that-does-nothing `PLAN-phase-1.md` §4.5 rules out. It
  is a lifetime figure rather than a per-mode one, and the card says so: *Longest 24*.
- **Per-game options live on the game's card**: *Auto-fire* moves onto the Invaders card, and
  *Numbers* and *Count in 2s* arrive on the Snake card. A child playing Snake is not asked about
  auto-fire.
- **Arcade-wide options stay in the Options section below**: *Easy mode* and *Buttons on the left*
  are one choice for the whole arcade (§2).
- *Count in 2s* is drawn only while *Numbers* is on, and the two write one field: off ↔ ones for the
  first, ones ↔ twos for the second (§4.8).
- Every toggle stays a `BigButton` with `selected`, so the tap-target floor and the selected drawing
  are one implementation, as phase 4 made them.

The route `/arcade/snake` takes no arguments: the options are read from the profile when the run
starts, so there is no second copy to disagree with the stored one.

### 4.10 Sound and haptics

Four new motifs under `assets/audio/snake/`, synthesised by `tool/audio/generate_motifs.py` like the
other fifteen and committed as its output, with `app/assets/audio/README.md` gaining their row of the
table:

| File | Plays when |
|---|---|
| `snake/eat.wav` | The next number is eaten — a rising blip, and the one sound of this game a child hears most |
| `snake/not_yet.wav` | The snake crosses a number that is not next. Soft and low, and deliberately not a buzzer: nothing went wrong |
| `snake/crash.wav` | A life is lost |
| `snake/level_clear.wav` | A decade is finished |

`Motif.snakeSet` is what `SnakeScreen` preloads on entry, for the reason `InvadersScreen` preloads
the arcade set: the decode cost of a sound's first play lands during the screen transition rather
than audibly late on the event that introduces it.

Haptics buzz on `crashed` and `levelCleared` only, through `AppHaptics` — the two moments in a run
worth feeling, and `app/test/haptics_call_site_test.dart` requires the wrapper anyway.

---

## 5. Repository layout

```
app/
├─ lib/
│  ├─ routes.dart                          # + arcadeSnake
│  └─ features/arcade/
│     ├─ arcade_menu_screen.dart           # two cards, per-game options (§4.9)
│     ├─ shared/
│     │  ├─ fixed_step.dart                # fixedStep, maxStepsPerFrame, the accumulator (§4.7)
│     │  │                                 #   moved from invaders_game.dart and InvadersSim
│     │  ├─ arcade_controller.dart         # + ArcadeHud.note
│     │  ├─ arcade_result.dart             # + counting, length
│     │  ├─ game_shell.dart                # + waveLabel
│     │  ├─ on_screen_pad.dart             # + PadLayout.dPad
│     │  └─ pad_input.dart                 # + up, down, and their keys
│     └─ snake/
│        ├─ model/
│        │  ├─ snake_sim.dart              # the whole game, pure Dart (§4.1)
│        │  ├─ snake_rules.dart            # tuning, normal and easy (§4.4)
│        │  ├─ counting.dart               # SnakeCounting and its sequences (§4.3)
│        │  └─ digits.dart                 # 3 x 5 numeral glyphs (§4.5)
│        ├─ snake_game.dart                # FlameGame: accumulator + one render pass (§4.5)
│        └─ snake_screen.dart              # /arcade/snake
├─ assets/audio/snake/                     # four motifs (§4.10)
├─ test/features/arcade/snake/…            # one file per unit above
└─ integration_test/
   └─ snake_smoke_test.dart                # on a device, not in CI (§7)
```

Boundaries, unchanged in kind from phase 4:

- **`snake/model/` imports no Flutter beyond `foundation.dart` and no Flame**, so its tests are plain
  `test()` calls. Checkable by reading four files' imports.
- **`shared/` holds what both games use.** After this phase that claim is testable rather than
  hopeful: every file in `shared/` is imported by both `invaders/` and `snake/`, except
  `on_screen_pad.dart`'s two layouts, which are one file precisely so the pointer handling is not
  written twice.
- **`counting.dart` is separate from `snake_rules.dart`** because the counting sequence is what the
  profile stores and the menu toggles, while the rules are what easy mode chooses. They change for
  different reasons.

---

## 6. Pull requests

One PR per row, merged in order; each leaves the repository analysing, testing and green, and each
runs `tool/verify.sh` and a `/caveman-review` pass before it opens (`AGENTS.md`).

Estimates assume one developer working part time, roughly half a working day per unit — the same
basis as the earlier phase plans. **Total 5.25–6.75 days.**

| # | PR | Estimate |
|---|---|---|
| 1 | [Snake's fields in the save](#pr-1--snakes-fields-in-the-save-0507-day) | 0.5–0.75 day |
| 2 | [The shared reshape: four-way input, the D-pad, the HUD line](#pr-2--the-shared-reshape-1-day) | 1 day |
| 3 | [The Snake simulation](#pr-3--the-snake-simulation-1517-day) | 1.5–1.75 day |
| 4 | [The render layer and the screen](#pr-4--the-render-layer-and-the-screen-07510-day) | 0.75–1 day |
| 5 | [The arcade menu, with two games on it](#pr-5--the-arcade-menu-with-two-games-on-it-075-day) | 0.75 day |
| 6 | [Four sounds and two buzzes](#pr-6--four-sounds-and-two-buzzes-05-day) | 0.5 day |
| 7 | [Device pass, smoke test and close](#pr-7--device-pass-smoke-test-and-close-0507-day) | 0.5–0.75 day |

### PR 1 — Snake's fields in the save (0.5–0.75 day)

Commits:
1. `SnakeCounting`, `Profile.snakeCounting`, `HighScore.counting` and
   `ArcadeGameProgress.bestLength`, with codec reads that default and writes that emit them (§4.8).
2. `ArcadeResult.counting` and `.length`; `recordArcadeResult` capping the top five within one
   `(easy, counting)` pair and raising `bestLength` by `max`.
3. Tests: five scores kept per pair and a sixth dropped only when it is worse; a counting score never
   evicts a classic one and neither evicts an easy-mode one; `bestLength` rises from a run that
   scored nothing and never falls; a v1 file written before this PR decodes with every new field at
   its default; an unknown `snakeCounting` string decodes to `ones`.

**Done when:** `flutter test test/core/storage` is green, and a test round-trips a save holding four
snake tables, a `bestLength` and a non-default `snakeCounting` through `save_codec.dart` with
`schemaVersion` still 1.

### PR 2 — The shared reshape (1 day)

No Snake yet: this PR is finished when Invaders still plays exactly as it did.

Commits:
1. `shared/fixed_step.dart`: `maxStepsPerFrame` and the running-total accumulator moved out of
   `invaders_game.dart`, and `fixedStep` off `InvadersSim`, with both files importing them (§4.7).
2. `PadInput.up` / `.down`, the mirror's up and down keys, `ArcadeHud.note`, `GameShell.waveLabel`.
3. `PadLayout.dPad` in `on_screen_pad.dart` (§4.6), portrait and landscape.
4. Tests: the D-pad draws four 72 dp buttons and no FIRE; each releases on up, on cancel and on a
   move outside its bounds; two simultaneous pointers hold two directions at once; no button
   intersects a 34 dp bottom inset; the lateral layout is unchanged; a note renders after the wave
   and appears in the HUD's `Semantics` label; `waveLabel` changes the word.

**Done when:** the whole Invaders suite passes untouched except for one moved import, the
equivalence test is seen still failing against a `dt`-stepped simulation, and `flutter analyze` is
clean.

### PR 3 — The Snake simulation (1.5–1.75 day)

No Flutter widgets and no Flame; `PadInput` is the only import from outside `model/`.

Commits:
1. `snake_rules.dart`, `counting.dart`, `digits.dart`.
2. `snake_sim.dart`: the grid, the turn queue, movement, growth, wrap and wall, self-collision,
   lives and the respawn pause, targets and decoys, levels, scoring, events.
3. Tests: a held button queues one turn and not twenty; a reversal is refused; two turns inside one
   move interval both land; growth adds exactly `growPerTarget` cells and the tail follows;
   `wrapWalls` decides whether an edge crashes or wraps; a crash keeps the score, the level and the
   counting position; a decoy crossed emits `notYet` once per entry and nothing else; the sequence
   runs 1..10 then 11..20 in `ones` and 2..20 then 22..40 in `twos`; a level clear scores the bonus
   and speeds the game up; `moveTicksAt` hits its floor and never goes under; easy mode is three
   fewer numbers on the field and a wrapping wall by construction rather than by branch; `longest`
   is the longest body reached and not the final one.
4. **The equivalence test**: one seed, ten simulated seconds, stepped as 600 frames of 16.67 ms and
   as 1440 frames of 6.94 ms through the shared accumulator, comparing score, lives, level, every
   body cell, every target cell and value, and the heading.

**Done when:** `flutter test test/features/arcade/snake` is green in under two seconds, and the
equivalence test is shown to fail against a simulation stepped by raw `dt` — a determinism test that
was never seen red proves nothing (`AGENTS.md`).

### PR 4 — The render layer and the screen (0.75–1 day)

Commits:
1. `snake_game.dart`: the shared accumulator, the fixed-resolution camera, one render pass, and
   `ArcadeGameController` including the HUD's note and `ArcadeResult`.
2. `snake_screen.dart`, `AppRoutes.arcadeSnake` and the route table, building the run from the
   profile's easy mode and counting choice, and passing `waveLabel: 'Level'`; reachable from a
   temporary button on `/arcade` that PR 5 deletes, and the code says so.
3. Tests: a pumped `GameWidget` advances the sim by the expected number of steps for a frame
   sequence; pause stops it and resuming does not replay the paused interval; the numerals 7, 42 and
   200 draw inside their cell; the HUD shows `Next 7` and the run's level; a run played to game over
   stores a `HighScore` with `counting` set and raises `bestLength`.

**Done when:** `/arcade/snake` plays end to end in a widget test, `layout_sweep_test.dart` passes with
the new route added to it, and `dart tool/check_offline.dart` still reports no violations.

### PR 5 — The arcade menu, with two games on it (0.75 day)

Commits:
1. The card, extracted from `_InvadersCard` and given a game's name, best, options and table (§4.9).
2. The Snake card with its two toggles, the Invaders card with auto-fire moved onto it, and the
   Options section reduced to the two arcade-wide toggles.
3. Tests: each card shows the best for the mode the toggles select and the empty state otherwise;
   the Snake card shows the lifetime longest snake and keeps showing it when the mode changes;
   toggling *Numbers* off hides *Count in 2s* and writes `off`; toggling it back writes `ones`;
   *Count in 2s* moves between `ones` and `twos`; a relaunch over the same store shows the stored
   choice.

**Done when:** `flutter test test/features/arcade` is green, and a test plays a snake run, returns to
the menu and finds the score on the Snake card and not on the Invaders one.

### PR 6 — Four sounds and two buzzes (0.5 day)

Commits:
1. `tool/audio/generate_motifs.py` gains the four motifs; the `.wav` files are committed as its
   output; `app/assets/audio/README.md` gains their rows; `Motif` gains the four values and
   `snakeSet`.
2. `SnakeGame` drains its events into `AppAudio` and `AppHaptics` (§4.10).
3. Tests: each event plays its motif once through the recording audio double; `notYet` does not
   repeat while the snake sits on a decoy; a muted profile plays nothing;
   `python3 tool/audio/generate_motifs.py --check` passes.

**Done when:** the four sounds have been **listened to** on a device, not only generated — the
README's rule, and the reason this is its own pull request.

### PR 7 — Device pass, smoke test and close (0.5–0.75 day)

Commits:
1. `integration_test/snake_smoke_test.dart`: a run played through the D-pad with real pointers,
   backgrounded and foregrounded, quit, and the score read back out of a real `save.json`.
2. The tuning pass on `snake_rules.dart` from ten minutes of play, if it moves anything.
3. `PLAN.md` §4.4, §5.2, §6 and §7 reconciled with what shipped; this file's §8 ticked against runs
   rather than memories, and its closed banner added.

**Done when:** §8's checklist is ticked or explicitly left open with the reason, as
`PLAN-phase-4.md` §8 did.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| The D-pad reshape breaks Invaders' pad | Medium | Every change in §4.7 is additive with a default, and PR 2's done-criterion is the whole Invaders suite passing untouched. The pointer handling itself is not rewritten — the same `_PadButton` is laid out differently. |
| Four 72 dp buttons plus the field do not fit a small phone in portrait | Medium | A 232 dp diamond in a band that today holds a 72 dp row is the tightest layout in the app. PR 2's widget test pumps it at 360 x 640 with a notch and a gesture bar and asserts a floor on the field, as `sudoku_play_screen_test.dart` does for the board. If it fails, the fallback is a compact diamond with the buttons overlapping their corners — still 72 dp targets, less bounding box — and that is a layout change, not a design one. |
| A turn is dropped, so the snake hits a wall the child steered away from | High | It is the defect players notice first. The edge-detected queue of depth two (§4.1) is the design, with three tests: a held button turns once, two turns inside one interval both land, a reversal is refused. |
| Two-digit and three-digit numerals are unreadable on a phone | High | The whole educational point rests on being able to read them. The glyph table is drawn at cell scale with a test asserting the extent (§4.5); the HUD carries the number as scalable text as well; and the device pass is where a person reads them at arm's length. If three digits do not read, `targetsPerLevel` and the sequence are unchanged — the numeral shrinks to two digits by counting decades within a level, which §9 keeps as the fallback. |
| A child cannot find the next number among the decoys, and the game stalls | Medium | `visibleTargets` is a rules field (§4.4): easy mode already shows two, and the device pass can move either row. The HUD's `Next 7` is always there. |
| The speed ramp makes level 3 unplayable | Medium | Two ramps, both in whole ticks with a floor (§4.2), both tunable in one file. The device pass in PR 7 is what moves them, and moving them is not a plan change. |
| Counting mode makes a run so long a child never sees a game-over card | Low | A snake growing 2 cells per target on a 224-cell board fills the field; the speed floor is 67 ms per cell. Both are bounded and both are in the rules table. |
| The score tables fragment into four per game | Low | Twenty snake entries per profile, a hundred-odd bytes each, capped at write time (§4.8) with a test. Well inside `PLAN.md` §5.2's few kilobytes. |
| The renderer grows state — a cached numeral, an interpolated head | Medium | The same boundary phase 4 drew (`PLAN-phase-4.md` §7): `snake_game.dart`'s fields are an accumulator, a sim and an input listenable. A position or a glyph cached there is the review finding. |
| `shared/` becomes a place where each game's needs accumulate | Medium | §4.7 is a table of five additions and one move, each with a stated reason and a default that leaves Invaders alone. A sixth game-specific field on `ArcadeHud` is the signal that the HUD wants a game-supplied widget instead, and that is a decision to make then, with three games in hand. |
| Scope creep — arithmetic modes, mazes, swipe | Medium | §2 lists each with where it belongs, and §9 keeps the three worth revisiting as questions rather than as work. |
| No emulator in CI, so `integration_test/` never runs on a merge | Medium | Unchanged from phases 3 and 4 and accepted again: the widget-level run in PR 4 covers the same path on every commit, `AGENTS.md` says how to run the device test, and an emulator job stays `PLAN.md` §9's open question. |
| The sounds are generated but never listened to | Low | PR 6's done-criterion is a person hearing them, which is why it is a pull request of its own rather than three lines inside PR 4. |

---

## 8. Verification checklist

Ticked at PR 7, against a run rather than a memory of one. Anything needing hardware stays open until
it has been done on hardware, as phases 3 and 4 did.

- [x] `tool/verify.sh` passes from a clean checkout. **3m11s** in this session (`real`, from `time`) —
      the puzzle_engine suite (goldens plus a 2000-seed fuzz) is 1m05s of it, the app suite the rest.
- [x] `cd app && flutter test` passes. **1101 tests in 1m20s**, recorded here against the 60 s budget
      `PLAN-phase-5.md` §1 set and measured at 62 s when it closed — over budget again, the same
      direction of travel that entry's own number already showed, and a fact rather than a target this
      phase moved: the suite grew by 290 tests (from 811) to cover a second game, and no phase run so
      far has had reason to prune it back toward 60 s.
- [x] `dart tool/check_offline.dart` reports no violations and names no new package — this phase adds
      none. Confirmed clean in this session's run.
- [x] `dart tool/check_determinism.dart` still passes; no engine file is touched. Confirmed clean (20
      files) in this session's run.
- [x] `test/no_random_test.dart` and `test/haptics_call_site_test.dart` pass over the new files. Run
      directly in this session: 9 and 7 cases respectively, both green.
- [x] The snake equivalence test compares ten seconds of state between 60 Hz and 144 Hz frame
      sequences. Green in this session's `flutter test`
      (`test/features/arcade/snake/snake_sim_equivalence_test.dart`); PR 3's own record is that it was
      seen failing against a `dt`-stepped simulation before it was trusted (`AGENTS.md`'s rule), which
      this pull request did not need to re-derive.
- [x] The Invaders equivalence test still passes after the accumulator moved. Green in this session's
      run (`test/features/arcade/invaders/invaders_sim_equivalence_test.dart`); PR 2's own record is
      the fail-then-pass check against the moved accumulator.
- [x] A widget test drives two simultaneous pointers on the D-pad and asserts both directions held.
      Green (`on_screen_pad_test.dart`).
- [x] A widget test slides a pointer off UP and asserts the direction is released; a second asserts a
      pointer-cancel does too. Green (`on_screen_pad_test.dart`).
- [x] A widget test pumps `/arcade/snake` with a 34 dp bottom `viewPadding` and asserts no button
      intersects the inset, at 360 x 640 and in landscape. Green
      (`on_screen_pad_test.dart`: "no button intersects a 34 dp bottom safe-area inset").
- [x] `layout_sweep_test.dart` covers `/arcade/snake` at four window sizes and two text scales. Green
      in this session's run (12 cases per size, all four sizes present in the log).
- [x] A widget test plays a counting run to game over and asserts the stored `HighScore` carries
      `counting`, that `bestLength` rose, and that the menu shows it on the Snake card. Green, split
      across two files: `snake_screen_test.dart` ("a run played to game over stores a HighScore with
      counting set and raises bestLength") plays the run, and `arcade_menu_screen_test.dart` ("a test
      plays a snake run, returns to the menu and finds the score on the Snake card and not on the
      Invaders one") is where the menu is read back.
- [x] A save written before this phase decodes with `snakeCounting`, `counting` and `bestLength` at
      their defaults, with `schemaVersion` still 1. Green (`save_codec_test.dart`).
- [x] The numerals 7, 42 and 200 draw inside their cell, asserted rather than eyeballed. Green
      (`snake_game_test.dart`, `numeralExtent stays inside the cell`).
- [ ] On the Android device: ten minutes of play with no jank, no dropped turn, and no stuck
      direction after a finger slides off a button. **Not done.** No Android phone, tablet or desktop
      display was available in this or any session that built this phase — the same gap phases 3, 4
      and 5 each recorded rather than assumed shut. Carried into `PLAN.md` §9 unticked.
- [ ] On the Android device: the numerals are readable at arm's length on a phone and on a tablet.
      **Not done**, for the same reason as above.
- [ ] On the Android device: a five- or six-year-old counts to 20 unaided with the on-screen
      controls. This is the criterion the game exists for; nothing else stands in for it. **Not
      done**, for the same reason as above — the criterion this phase most needed a device for is the
      one it could least fake, and it stays open rather than inferred from the automated suite.
- [ ] The four sounds have been listened to on a device, and `generate_motifs.py --check` passes. The
      second half is confirmed in this session — `python3 tool/audio/generate_motifs.py --check`
      reports all 19 motifs matching the script — but the first half needs the same device the three
      lines above do, so the item stays open as a whole.
- [ ] `app/integration_test/snake_smoke_test.dart` passes on a device. **Written, analyzes clean, and
      not run on a device or even headless in this session** — narrower than "no device": this
      session's container has no GTK development headers, so `flutter build linux` cannot produce
      `minisound_ffi`'s native library, and without it even `-d flutter-tester` fails before the app
      finishes loading (`ArgumentError: Failed to load dynamic library 'libminisound_ffi.so'`).
      `integration_test/invaders_smoke_test.dart` was run the same way as a control and hit the
      identical failure at the identical point, confirming this is a gap in the container rather than
      something this pull request broke. Two things stood in for the run that could not happen: the
      exact steering sequence the test drives was replayed 5,000 times directly against `SnakeSim`
      (bypassing Flame, the widget tree and audio entirely), reaching its target and scoring on every
      seed with no crash and no dropped turn; and the widget-level navigation the test depends on —
      `Easy mode` and `Play Snake` sitting below the fold on a short window — was found failing on its
      first run and fixed with `tester.ensureVisible` before that replay was trusted. `AGENTS.md` says
      how to run this by hand on hardware, which is what settles the item for real.
- [x] `PLAN.md` §4.4, §5.2, §6 and §7 match what was built, and this file carries its closed banner.

---

## 9. Open questions

| Question | Current assumption | What resolves it |
|---|---|---|
| Should counting be on by default? | Assumed yes, `ones` (§4.8): counting is why this game is in this app, and a child who wants plain snake turns it off in one tap. | PR 1's review, and the device pass. Reversing it is one default. |
| Is a level ten numbers, in both modes? | Assumed yes (§4.4). A decade is the unit a child is being taught, and making easy mode five would make "level 3" mean a different number in each mode. | The device pass: if ten targets is too long a level for a five-year-old, `targetsPerLevel` is a rules field and easy mode is the row to move. |
| Should decoys be the next values in sequence, or drawn from the rest of the level? | Assumed drawn (§4.3), so the ordering decision is real rather than always "the leftmost number". | PR 3's review and the device pass; it is one line in the spawner. |
| Do three-digit numerals read on a phone? | Assumed yes at 1.4 units per glyph pixel in a 16-unit cell (§4.5). | The device pass. The fallback if not is in §7. |
| Should the snake keep its length across a crash? | Assumed no — it resets to `startLength`, while score, level and counting position survive (§4.1). Keeping the length would make a crash free. | PR 3's review and the device pass. |
| Does Snake want swipe control as well as the pad? | Assumed no (§2): the ask is buttons, and a swipe recogniser on the field reopens the gesture-arena question phase 4 closed. | A later minor release, if a device pass finds children swiping at the field anyway. |
| Is counting down (10 to 1) worth a fourth value of `SnakeCounting`? | Assumed not now. It is the cheapest extension the design allows — one sequence function — and it is a different skill. | A later release, on the same evidence as above. |
| Does CI gain an Android emulator job so `integration_test/` runs on merges? | Assumed no again, as in phases 3 and 4. | `PLAN.md` §9's open question, unchanged. |

---

## 10. Starting order

1. **PR 1 — the save fields.** Everything above stores through them, and the two schema-shaped
   questions — where the counting choice lives and how the tables split — have to be answered before
   a child's file can hold either.
2. **PR 2 — the shared reshape.** It lands before any Snake code so that it is judged as what it is:
   a change to Invaders' shell that leaves Invaders identical. Doing it alongside the new game would
   make every regression ambiguous.
3. **PR 3 — the simulation.** The largest unit in the phase, and the one every later PR draws, pauses
   or stores. It depends on PR 2 only for `PadInput`'s two new fields.
4. **PR 4, then PR 5, then PR 6.** The screen before the menu that opens it, and the sound last,
   because it is the only part whose done-criterion is a person listening rather than a test.
5. **PR 7 — the device pass and the close**, which is where §8's hardware lines are ticked or left
   open with their reason.
