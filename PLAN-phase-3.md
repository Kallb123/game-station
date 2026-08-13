# Phase 3 — Sudoku UI

The plan for the Sudoku half of `app/`: the menu, the board, the keypad, hints, mistakes, auto-save
and the isolate that keeps generation off the raster thread. [`PLAN.md`](PLAN.md) §3.7 is the design
this expands, §7 is the phase order, and §7's phase-3 list names what
[`PLAN-phase-2.md`](PLAN-phase-2.md) handed over. Where this file and `PLAN.md` disagree, the reason
is stated here and the closing PR updates `PLAN.md`.

Phase 3 is the first phase in which a child can play a Sudoku puzzle. It is also the first phase in
which the engine's determinism does visible work: a puzzle id in the save file has to name the same
grid on the next launch, so the resume path is the phase's real done-criterion rather than the grid
widget.

**Release line unchanged:** `PLAN.md` §7 ships at phase 6. Nothing here blocks or advances that.

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
| A force-quit mid-puzzle restores the exact board, notes, timer and undo stack | `PLAN.md` §7's phase-3 done-criterion. Enforced by a widget test that encodes a played board, rebuilds the app from the encoded save alone, and asserts cell-by-cell equality — not by a manual pass, which cannot be run on every commit. The manual pass on a device happens too (§8). |
| No new dependency | Everything here is `flutter`, `flutter_riverpod` and `puzzle_engine`, all already resolved (`app/pubspec.yaml`). `compute()` is in `package:flutter/foundation.dart`. Enforced by `tool/check_offline.dart`, which reads the resolved graph. |
| Generation never blocks a frame | `PLAN.md` §3.5: 9x9 Hard is 65 ms at the median and about half a second at the tail. Every call goes through `compute()`; nothing calls `generateSudoku` on the UI isolate. Enforced by a lint-shaped test: `grep`-style unit test asserting the only `generateSudoku` call site in `app/lib` is the isolate entry point. |
| The picker cannot build an id the engine refuses | `PuzzleId.parse` throws for 6x6 Expert, and `generateSudoku` throws `ArgumentError` for it (`PLAN.md` §7 handover). Enforced by a test that walks every (size, difficulty) the menu can offer and parses the id it would build. |
| Never surface an internal error to a child | `AGENTS.md`. A generation that somehow fails, a cache entry that will not decode, a save write that errors: each degrades to a playable state with at most one plain sentence. `widened` is shown as an ordinary puzzle and never mentioned. |
| The board is readable at 200% system text scale | `PLAN.md` §9. Digit size derives from cell geometry rather than from `MediaQuery.textScaler`, which would overflow a fixed cell; chrome and keypad labels scale normally. Checked by a widget test pumping at `TextScaler.linear(2.0)` and asserting no overflow. |
| The save stays a few kilobytes | `PLAN.md` §5.2. The undo stack is capped at 300 entries and `puzzleCache` at 30 puzzles, both enforced at write time in `ProgressRepository` with tests. |
| `tool/verify.sh` green before every commit | It is what CI runs, in the same order (`AGENTS.md`). App tests are about five seconds of it; this phase should keep them under fifteen, which means widget tests inject a fake puzzle source rather than generating. |

---

## 2. Non-goals

| Not in phase 3 | Where it belongs |
|---|---|
| Sound on completion (`PLAN.md` §3.7) | Phase 5. `flutter_soloud` arrives with the audio layer; adding it three phases early means carrying it through every intervening review (`AGENTS.md`). The confetti ships here because it needs no dependency. |
| Haptics on a correct or wrong digit | Phase 5, with the platform guard. `settings.haptics` is stored and unread until then, as it is today. |
| Screen-reader labels, colourblind-safe palette, i18n | Phase 5. The grid gets `Semantics` labels good enough not to be rebuilt (`row 3, column 7, empty`), but the accessibility pass with TalkBack and VoiceOver is phase 5's done-criterion, not this one. |
| Landscape and tablet layout | Phase 5. Phase 3 lays out portrait-first and lets landscape scroll rather than looking right. |
| Any arcade work, including `GameShell` | Phase 4. `/arcade` keeps its `ComingSoonScreen`. |
| Export and import of the save (`PLAN.md` §5.3) | Unscheduled; it is neither phase 3 nor a blocker for release. Named here because §5.3 lists it and silence would read as an omission. |
| A puzzle-bank asset, or generating more than one puzzle ahead | Pre-warm is one puzzle (`PLAN.md` §3.5). A batch API was left to this phase by `PLAN-phase-2.md` §9 and is not needed: nothing wants two puzzles at once. |
| New techniques, new sizes, or any change to generation output | Any of them means a `generatorVersion` bump, regenerated goldens and a save migration in one commit (`AGENTS.md`). Phase 3 makes exactly one engine change, and it is additive — see §3. |
| Difficulty shown as anything but the requested label | A widened puzzle is drawn like any other (`PLAN.md` §7). "This one came out easier than asked" is information for the repository, not for a child. |

---

## 3. Approach

Build bottom-up, as phase 2 did, so each layer is testable before anything draws on it:

1. **`nextPlacement` in the engine** — the one additive engine change, taken first so it is not
   buried in a widget diff.
2. **Repository writes** — the save mutations for solved, in-progress, best times, streak and cache.
   Pure storage, no widgets.
3. **The puzzle source** — `compute()`, the cache in front of it, in-flight de-duplication and
   pre-warm. No widgets.
4. **The session model** — entries, notes, undo/redo, mistakes, and the encoding that survives a
   restart. Plain Dart, no widgets.
5. **The grid and keypad** — widgets over the model.
6. **The play screen** — timer, auto-save, resume, spinner.
7. **Hints, mistake modes, completion.**
8. **The menu, daily card and streak.**

**The one engine change.** `PLAN.md` §3.7 says a hint "reveals one cell the technique solver can
prove". The exported `nextStep(board)` returns the cheapest step, which is often an `Elimination`
list rather than a placement — and the app cannot apply eliminations, because `CandidateGrid` is
deliberately not exported (`puzzle_engine.dart`). Showing a six-year-old "4 is ruled out of three
cells" is not a hint. So the engine gains `nextPlacement(SudokuBoard)`: it runs the same technique
loop on its own `CandidateGrid` until a cell is decided, and returns null when technique runs out.
It touches no generation path, so goldens and `generatorVersion` are unaffected — asserted by CI
rather than by argument, since the goldens run on every push.

Alternatives considered:

| Option | Rejected because |
|---|---|
| Reveal a hint straight from the stored solution, no engine change | It is what the fallback does when `nextPlacement` returns null on an Expert board, but as the *only* mechanism it makes "hint" mean "answer": the cell revealed would often be one no technique reaches, so a child following hints learns nothing and the T1–T4 tiers stop meaning anything to the UI. |
| Export `CandidateGrid` and let the app drive the technique loop | Puts the solver's step ordering in the app, where nothing tests it, and makes an internal type part of a package boundary that phase 2 drew narrowly on purpose. |
| Re-derive the solution from the clue string in the app instead of caching it | `countSolutions` is not exported and a second solver in `app/lib` is a second thing to keep correct. The solution is already a field on `GeneratedPuzzle`; caching it costs 81 bytes per puzzle. |
| `Isolate.spawn` with a long-lived worker instead of `compute()` per puzzle | `compute()` spawns an isolate per call, which is a few milliseconds against a 65 ms generate, and it is one line. A pooled worker is worth it when calls are frequent; here a child generates a puzzle every few minutes. |
| Keep the whole board in a Riverpod `Notifier` and rebuild the grid from it | Eighty-one cells rebuilt on every keystroke is the shape that gets slow on a cheap tablet. The session model is a `ChangeNotifier` and each cell subscribes to its own slice — same pattern as `ProgressRepository`, which the app already uses. |
| `go_router` for `/sudoku/play` and its arguments | Phase 1 rejected it (`PLAN-phase-1.md` §3) and nothing changed: two more screens with no deep linking. The existing `onGenerateRoute` table takes a typed arguments object. |
| Store the in-progress board as JSON objects rather than opaque strings | `PLAN-phase-1.md` §4.2 made `grid`, `notes` and `undoStack` opaque to the codec on purpose, so the board representation can change without changing the save format. Widening them now would undo that. |

**Load-bearing decision:** the in-progress encoding in §4.4 — the grid string, the notes string and
the undo entry format. Once a child's `save.json` holds them, changing any of the three means a
schema migration rather than a refactor. They are chosen to be fixed-length and parseable without a
tokenizer for that reason, and they are frozen by a round-trip test in the same PR that introduces
them.

---

## 4. Design

### 4.1 The puzzle record

One format serves both the isolate's return value and the `puzzleCache` entry:

```
"<clues>|<solution>"      // "..3.2...|...", 2 * spec.cells + 1 characters
```

`PuzzleRecord.encode` / `PuzzleRecord.decode` in `app/lib/features/sudoku/data/`. `PLAN.md` §5.2's
`puzzleCache` example holds the clue string alone; the solution is added because immediate mistake
feedback needs the true digit, and nothing exported from the engine can recover it from the clues
(§3). The closing PR updates §5.2.

The cache is dropped wholesale when `SaveData.generatorVersion` differs from
`engine.generatorVersion` at load, which answers `PLAN.md` §7's "keyed by both or dropped on a
bump": a per-entry key would let a stale entry outlive the generator that made it, and there is
nothing in a cache worth a migration.

### 4.2 The puzzle source

```dart
abstract interface class PuzzleSource {
  Future<PuzzleRecord> load(PuzzleId id);   // cache, else isolate
  void prewarm(PuzzleId id);                // fire and forget; result lands in the cache
}
```

- `IsolatePuzzleSource` is the real one. `load` reads `puzzleCache` first; on a miss it calls
  `compute(_generateRecord, id.value)`, where `_generateRecord` is a top-level function taking a
  `String` and returning a `String` — primitives across the boundary, and the same string the cache
  stores, so one format has one parser and one test.
- **One flight per id.** A `Map<String, Future<PuzzleRecord>>` of in-flight loads, so the pre-warm
  and the child tapping *Play* two seconds later do not generate the same puzzle twice.
- `prewarm` is not cancellable, because `compute()` is not. An abandoned pre-warm finishes and its
  result is cached, which is the outcome the cache wanted anyway.
- `FakePuzzleSource` returns fixtures synchronously. Every widget test uses it: generating a 9x9
  Hard in each of thirty widget tests would put two seconds on `flutter test` for no coverage of
  anything the engine's own suite does not already cover.

The source is behind `puzzleSourceProvider` so the fake is an override, matching how
`saveStoreProvider` is overridden today (`core/storage/providers.dart`).

**Spinner delay 150 ms.** A 9x9 Easy is 1 ms at the median (`PLAN.md` §3.5); showing a spinner for
it is a flash that reads as a glitch. The delay is a constant in one place with a test, not a
`Future.delayed` sprinkled at call sites.

### 4.3 The session model

`SudokuSession extends ChangeNotifier`, in `features/sudoku/model/`, with no Flutter import beyond
`foundation.dart`:

```dart
SudokuSession.start({required PuzzleId id, required PuzzleRecord record});
SudokuSession.resume({required PuzzleId id, required PuzzleRecord record,
                      required PuzzleInProgress saved});

int  digitAt(int index);          // 0 for empty
bool isGiven(int index);          // from the clue string, never editable
int  notesAt(int index);          // candidate bitmask, bit 0 = digit 1
bool isWrong(int index);          // entered and != solution

void select(int? index);
void enter(int digit);            // respects pencilMode
void erase();
void undo();  void redo();
void hint();                      // §4.6

bool get isSolved;                // every cell equals the solution
int  get mistakes;                // count of wrong digits ever entered
int  get hints;
Duration get elapsed;
PuzzleInProgress toSaved();
```

The session holds its own `List<int>` of digits rather than a `SudokuBoard`. **`SudokuBoard.place`
refuses a digit that repeats one in its row, column or box, and `SudokuBoard.fromClues` throws a
`FormatException` when it hits one** (`sudoku_board.dart`) — so a board holding a child's wrong
digit cannot be built at all. A `SudokuBoard` is constructed only where one is needed, for hints,
and only from the clues plus the entries that match the solution.

`isWrong` is computed against the stored solution rather than against peers, so a digit that is
wrong but not yet contradictory is caught. Whether it is *drawn* wrong depends on the mistake mode
(§4.6).

### 4.4 The in-progress encoding

Three opaque strings in `PuzzleInProgress`, which the codec already stores as strings
(`save_data.dart`):

| Field | Encoding | Size at 9x9 |
|---|---|---|
| `grid` | The engine's clue-string format: one char per cell, `.` for empty. Clues and entries alike, so `grid` is the board a child sees. | 81 chars |
| `notes` | Two base-36 digits per cell, zero-padded, row-major — a 9-digit candidate mask is 0–511, which is two base-36 characters. Empty string when no cell has notes, which is the common case. | 162 chars or 0 |
| `undoStack` | One entry per move, `"<index>.<digit>.<mask>"`, holding the cell's state **before** the move. Undo is therefore a restore rather than an inverse operation, so a move type added later needs no new opcode. | ~10 bytes each |

Fixed-width and delimiter-free within a cell, so decoding is arithmetic rather than parsing, and a
truncated string fails a length check instead of decoding into a plausible wrong board.

**Redo is not persisted.** The schema field is `undoStack` (`PLAN.md` §5.2), a redo stack after a
restart is not something a child reaches for, and persisting it would double the field's size for
that. Resuming clears redo, and the code says so.

**The undo stack is capped at 300 entries**, oldest dropped. Toggling pencil marks can produce
thousands of moves in one puzzle, and the save is meant to be a few kilobytes after 500 puzzles
(`PLAN.md` §5.2). 300 moves back is deeper than any child will walk.

### 4.5 The grid and keypad

`SudokuGridView` takes a `SudokuSpec` and a session, and draws both sizes from `spec.boxRows`,
`spec.boxCols` and `spec.digits`. No `if (size == 9)` anywhere: a 6x6 whose boxes come out 3x2
instead of 2x3 is the bug `PLAN.md` §3.6 already tests for in the engine, and the widget has its own
test: for 9x9 the thick lines fall after columns 3 and 6 and after rows 3 and 6; for 6x6 after
column 3 and after rows 2 and 4. A grid that transposed the box shape would pass the first case and
fail the second.

- One square `AspectRatio`, sized by `LayoutBuilder`, so the grid fits the shorter dimension.
- Digit size is `cellSize * 0.6`, clamped, and **not** multiplied by `MediaQuery.textScaler`: an
  80%-larger digit in an unchanged cell is a clipped digit. The keypad, timer and chrome scale
  normally, which is what §1's 200% row is checked against.
- Highlighting, in one paint pass: the selected cell; every cell holding the selected digit; and a
  softer wash over the selected cell's row, column and box (`PLAN.md` §3.7). Colours come from
  `AppPalette` (`core/ui/tokens.dart`); none of them is the only signal for anything, so phase 5's
  colourblind pass has nothing to undo.
- Each cell is its own widget listening to its own slice of the session, so entering a digit
  repaints the cells that changed rather than eighty-one.

`SudokuKeypad` draws `spec.digits` buttons in `spec.boxCols` columns — 3 columns for both sizes, so
9x9 gets the 3x3 phone-keypad shape and 6x6 gets 2x3, derived rather than hardcoded. Every button is
at least `AppTapTargets.min` (56 dp). Beside the digits: erase, pencil toggle, undo, redo, hint.

### 4.6 Hints, mistakes and completion

**Hint**, in order:

1. If any entered digit is wrong, select and flag that cell instead of revealing a new one. A child
   whose grid already contradicts itself needs the contradiction pointed at, not another digit. This
   also sidesteps §4.3's trap: no `SudokuBoard` is built from a grid that cannot hold one.
2. Otherwise `nextPlacement(board)` over the clues plus correct entries. If it returns a step, that
   cell is filled and the technique name is available for a later phase to explain.
3. Otherwise — an Expert board where technique has run out (`PLAN.md` §3.4's T4) — reveal the empty
   cell with the fewest candidates, from the stored solution. Deterministic, lowest index wins a
   tie.

Every path through 2 and 3 increments `hints`, which clears `clean` on the `SolvedPuzzle` (`PLAN.md`
§3.7). Path 1 does not: pointing at a mistake gives nothing away.

**Mistake feedback** is a new setting, `Profile.mistakeFeedback`, one of `immediate` (the default, per
`PLAN.md` §3.7) and `atCompletion`. §9 left this open for the owner to decide before PR 2; the answer
is per profile, not device-wide — a younger sibling wants to know at once, an older one may not want
to be told before the grid is full — so it is a field on `Profile` rather than on `AppSettings`. It is
still additive: `save_codec.dart` ignores unknown keys and defaults missing ones, so a v1 file written
by phase 1 reads back with the default and no migration step is needed. `schemaVersion` stays 1, which
is what it is for — it marks a shape change that needs a migration, and adding an optional field to an
existing object is not one. `PLAN-phase-1.md` §4.2 declared v1 "in full" and missed this field; the
closing PR records that in `PLAN.md` §5.2 rather than leaving the two disagreeing.

`mistakes` counts every wrong digit entered, in both modes, because it is what
`SolvedPuzzle.mistakes` stores and what decides `clean`.

**Completion** is an overlay card on the board, not a route: the board stays visible behind it, and
*Back* has one meaning. It shows time, hints, mistakes and the clean star, and offers *Next puzzle*
(the same size and difficulty, index + 1) and *Back to Sudoku*. Confetti is a `CustomPainter` with
no dependency, suppressed when `MediaQuery.disableAnimationsOf(context)` is true — which phase 1
already or-ed with the stored setting (`app.dart`). Sound is phase 5 (§2).

### 4.7 The menu, the daily puzzle and the streak

`/sudoku` replaces `ComingSoonScreen`:

- A **continue** card when the active profile has an `inProgress` entry, first, because a child who
  left a puzzle half-done wants that one.
- A **daily** card: `dayIndexFor(DateTime.now())` gives the index, and the size and difficulty are
  whichever the child last played, defaulting to 9x9 Easy. It shows the current streak, and its
  puzzle is pre-warmed the moment the screen opens (`PLAN.md` §3.5).
- A **size toggle** (9x9 / 6x6) and a **difficulty list** built from `difficultiesFor(spec)`, which
  returns `Difficulty.values` for 9x9 and all but `expert` for 6x6 — the engine refuses 6x6 Expert
  in two places (§1), and one function that both the menu and its test read is the mechanism that
  keeps the picker inside what the engine will build. 9x9 Expert **is** offered, last, answering
  `PLAN-phase-2.md` §9's open question: the engine makes it either way, and a child who wants a
  harder puzzle finding nothing above Hard is a worse outcome than one who tries Expert and backs
  out. Removing it later is a one-line change to `difficultiesFor`.
- Each difficulty row shows solved count and best time from `SudokuProgress.bestTimeMs`, keyed
  `"9x9:easy"` as §5.2 specifies.

**Streak arithmetic** lives in `ProgressRepository`, next to the data it changes: on solving a
puzzle whose index equals today's day index, `lastDayIndex == today` changes nothing; `today - 1`
increments `current`; anything else resets `current` to 1. `best` is the max of the two. Any size
and any difficulty counts, so one child's streak is one number rather than seven — `PLAN.md` §3.2
gives one daily puzzle *per size per difficulty*, and seven parallel streaks is a scoreboard, not
encouragement.

### 4.8 Repository writes

`ProgressRepository` gains, all on the active profile and all going through the existing `_apply`,
so the 500 ms debounce and the one-write-at-a-time queue apply unchanged
(`progress_repository.dart`):

```dart
void saveInProgress(PuzzleId id, PuzzleInProgress state);
void clearInProgress(PuzzleId id);
void recordSolved(PuzzleId id, SolvedPuzzle result);   // also bestTimeMs and the streak
void cachePuzzle(PuzzleId id, String record);          // 30-entry cap
```

`cachePuzzle` takes the encoded record rather than the `PuzzleRecord` of §4.1, which is what PR
2 built and PR 3 kept: `PuzzleRecord` lives in `features/sudoku/data`, and a `core/storage` method
that named it would make the storage layer depend on a feature. The repository stores an opaque
string for the same reason the codec does (§3), and the one parser is on the feature side.

`recordSolved` clears the matching `inProgress` entry in the same mutation, so a save cannot hold a
puzzle that is both finished and in progress.

**Cache eviction** is least-recently-used over an in-memory recency list, seeded on load in whatever
order the file gives — the codec sorts keys on write, so recency is not recoverable from disk, and
inventing a timestamp field to recover it would cost more than the occasional wrong eviction. **An
id with an `inProgress` entry is pinned**, in any profile: evicting the puzzle a child is halfway
through would make resume regenerate it behind a spinner.

Writes happen on every move through the debounce (`PLAN.md` §5.3), and `flush()` on pause and detach
is already wired in `app.dart`.

---

## 5. Repository layout

```
app/
├─ lib/
│  ├─ routes.dart                       # + sudokuPlay
│  └─ features/sudoku/
│     ├─ data/
│     │  ├─ puzzle_record.dart          # the "<clues>|<solution>" codec
│     │  ├─ puzzle_source.dart          # PuzzleSource, IsolatePuzzleSource, the compute entry
│     │  └─ providers.dart              # puzzleSourceProvider, sudokuMenuProvider
│     ├─ model/
│     │  ├─ sudoku_session.dart         # entries, notes, undo/redo, mistakes, hints
│     │  ├─ session_codec.dart          # grid / notes / undoStack strings (§4.4)
│     │  └─ difficulties.dart           # difficultiesFor(spec)
│     └─ ui/
│        ├─ sudoku_menu_screen.dart     # /sudoku
│        ├─ sudoku_play_screen.dart     # /sudoku/play
│        ├─ sudoku_grid_view.dart
│        ├─ sudoku_cell.dart
│        ├─ sudoku_keypad.dart
│        ├─ completion_card.dart
│        └─ confetti.dart
├─ test/features/sudoku/…               # one file per unit above
└─ integration_test/
   └─ sudoku_smoke_test.dart            # on a device, not in CI (§7)
packages/puzzle_engine/
└─ lib/src/technique_solver.dart        # + nextPlacement
```

Boundaries:

- **`data/`, `model/` and `ui/` split by what a test needs.** `model/` imports only
  `foundation.dart`, so its tests are plain `test()` calls with no `pumpWidget`; `data/` needs the
  engine and `compute`; `ui/` needs bindings. Phase 1 kept `core/storage` Flutter-light for the same
  reason and it is why that suite runs in a second.
- **`session_codec.dart` is separate from `sudoku_session.dart`** because it is the frozen half
  (§3). A format with its own file and its own round-trip test is harder to change by accident than
  three methods on a class that changes every PR.
- **`difficulties.dart` is one function**, imported by the menu and by its test, so "the picker
  offers what the engine builds" is a shared fact rather than two lists.
- **Nothing under `features/sudoku/ui/` imports `puzzle_engine` except for `SudokuSpec` and
  `Difficulty`.** The board a widget draws comes from the session, so a widget test needs no
  generation.
- **`integration_test/` is new**, as `PLAN.md` §6's tree anticipated.

---

## 6. Pull requests

One PR per row, merged in order; each leaves the repository analysing, testing and green, and each
runs `tool/verify.sh` and a `/caveman-review` pass before it opens (`AGENTS.md`).

Estimates assume one developer working part time, roughly half a working day per unit — the same
basis as `PLAN-phase-1.md` §6 and `PLAN-phase-2.md` §6. **Total 6–7.75 days against `PLAN.md` §7's
5–7 for the phase**, so the top of this range is over. Named rather than trimmed to fit: nine PR
cycles cost more than seven, and the resume path needs a device check that no test replaces. The
ranges are widest where a layout has to be tried at two sizes and two text scales (PR 5) and where a
criterion needs hardware (PR 9).

| # | PR | Estimate |
|---|---|---|
| 1 | [`nextPlacement` in the engine](#pr-1--nextplacement-in-the-engine-02505-day) | 0.25–0.5 day |
| 2 | [Repository writes for Sudoku](#pr-2--repository-writes-for-sudoku-05075-day) | 0.5–0.75 day |
| 3 | [The puzzle source: isolate, cache, pre-warm](#pr-3--the-puzzle-source-isolate-cache-pre-warm-075-day) | 0.75 day |
| 4 | [The session model and its encoding](#pr-4--the-session-model-and-its-encoding-0751-day) | 0.75–1 day |
| 5 | [The grid and the keypad](#pr-5--the-grid-and-the-keypad-1125-day) | 1–1.25 day |
| 6 | [The play screen: timer, auto-save, resume](#pr-6--the-play-screen-timer-auto-save-resume-0751-day) | 0.75–1 day |
| 7 | [Hints, mistake modes and completion](#pr-7--hints-mistake-modes-and-completion-0751-day) | 0.75–1 day |
| 8 | [The Sudoku menu, daily card and streak](#pr-8--the-sudoku-menu-daily-card-and-streak-075-day) | 0.75 day |
| 9 | [Integration smoke test and phase close](#pr-9--integration-smoke-test-and-phase-close-05075-day) | 0.5–0.75 day |

### PR 1 — `nextPlacement` in the engine (0.25–0.5 day)

Commits:
1. `nextPlacement(SudokuBoard)` in `technique_solver.dart`, exported: apply steps to an internal
   `CandidateGrid` until one decides a cell; return that `SolveStep`, or null when no technique
   makes progress.
2. `technique_test.dart` cases: a board where the cheapest step is an elimination still yields a
   placement; a T4 board yields null; the placed digit always matches the puzzle's solution.

**Done when:** `nextPlacement` is exported, the three cases pass, and CI is green with **no golden
file changed** — the diff touches no generation path, and the goldens are the check that says so.

### PR 2 — Repository writes for Sudoku (0.5–0.75 day)

Commits:
1. `saveInProgress`, `clearInProgress`, `recordSolved`, `cachePuzzle` on `ProgressRepository`, with
   `bestTimeMs` and the streak updated inside `recordSolved`.
2. The 30-entry LRU with in-progress ids pinned; the generator-version cache drop at load.
3. `Profile.mistakeFeedback` with its codec default (§4.6).
4. Tests: streak arithmetic across same-day, next-day and gap cases; `recordSolved` clearing
   `inProgress` atomically; eviction never dropping a pinned id; a v1 file with no `mistakeFeedback`
   decoding to `immediate`; one debounced write per burst of mutations.

**Done when:** `flutter test test/core/storage` is green, and a test asserts that a save encoded by
this build and decoded by `save_codec.dart` round-trips `mistakeFeedback`, a cached record and a
streak — with `schemaVersion` still 1.

### PR 3 — The puzzle source: isolate, cache, pre-warm (0.75 day)

Commits:
1. `puzzle_record.dart` and its round-trip test, including a rejection test for a malformed value.
2. `puzzle_source.dart`: `PuzzleSource`, `IsolatePuzzleSource` over `compute`, in-flight
   de-duplication, `prewarm`.
3. `FakePuzzleSource` in `test/`, and `puzzleSourceProvider`.
4. The test asserting `generateSudoku` appears exactly once in `app/lib`, at the isolate entry
   point.

**Done when:** a cache hit resolves without calling the engine (asserted with a counting fake), two
concurrent `load`s of one id produce one generation, a record whose `generatorVersion` no longer
matches is dropped rather than served, and a real `IsolatePuzzleSource.load` of `sudoku:6x6:easy:0`
returns a decodable record in a test that is not marked slow.

### PR 4 — The session model and its encoding (0.75–1 day)

Commits:
1. `sudoku_session.dart`: entries, pencil notes, selection, undo/redo, `isWrong`, `isSolved`,
   counters.
2. `session_codec.dart` (§4.4) and the 300-entry cap.
3. Tests: a given cannot be overwritten; undo walks back through digits and notes alike; redo clears
   on a new move; a played board round-trips through `toSaved()` and `SudokuSession.resume` to an
   identical model; a truncated grid string is rejected rather than decoded.

**Done when:** `flutter test test/features/sudoku/model` is green in under a second, and the
round-trip test compares all 81 cells, all 81 note masks, `elapsedMs`, `hints` and the undo stack —
not a summary.

### PR 5 — The grid and the keypad (1–1.25 day)

Commits:
1. `sudoku_grid_view.dart` and `sudoku_cell.dart`: both sizes from `SudokuSpec`, borders, selection,
   digit and peer highlighting, pencil marks.
2. `sudoku_keypad.dart`: digits in `spec.boxCols` columns, erase, pencil, undo, redo, hint (the hint
   button is wired in PR 7 and disabled here rather than absent, so the layout does not move).
3. Tests: box borders land at the right rows and columns for both sizes; tapping a cell then a
   digit shows it; pencil mode writes a note instead; every button is at least 56 dp; the whole
   screen pumps at `TextScaler.linear(2.0)` with no overflow.

**Done when:** those tests pass, and the screen has been looked at on the Android device at both
sizes — a border test proves geometry, not legibility.

### PR 6 — The play screen: timer, auto-save, resume (0.75–1 day)

Commits:
1. `sudoku_play_screen.dart`, `AppRoutes.sudokuPlay` and its typed arguments; the loading state with
   the 150 ms spinner delay.
2. The timer, shown per `settings.showTimer`, stopped when the app is not resumed.
3. Auto-save on every move through `saveInProgress`, and resume from an `inProgress` entry.
4. A temporary launcher on `/sudoku` — one *Play 6x6 Easy* button — so the screen is reachable
   before PR 8 exists. PR 8 deletes it, and this PR says so in the code.
5. Tests: a played board, encoded, then a fresh `ProviderScope` built from that save alone,
   asserting an identical board; the timer not advancing while paused; no spinner for a source that
   resolves inside 150 ms.

**Done when:** the resume test rebuilds from the encoded save rather than from a shared object, and
a force-quit and relaunch on the Android device restores the exact board, notes and timer.

### PR 7 — Hints, mistake modes and completion (0.75–1 day)

Commits:
1. The three-step hint of §4.6, with the hint counter.
2. `immediate` and `atCompletion` mistake feedback, and the settings control for it.
3. `completion_card.dart` and `confetti.dart`, `recordSolved` on completion, *Next puzzle* and
   *Back*.
4. Tests: a wrong digit is flagged at once in `immediate` and only at completion in `atCompletion`;
   a hint on a board with a wrong digit points at it and does not count; a hint on a clean board
   fills a cell the solution agrees with; a clean solve stores `clean: true` and one with a hint
   does not; confetti does not animate when `disableAnimations` is set.

**Done when:** a widget test solves a 6x6 end to end by tapping, and the resulting save holds a
`SolvedPuzzle` with the right time, hints, mistakes and `clean`, and no `inProgress` entry.

### PR 8 — The Sudoku menu, daily card and streak (0.75 day)

Commits:
1. `sudoku_menu_screen.dart` on `/sudoku`, replacing PR 6's launcher and the `ComingSoonScreen`:
   continue card, daily card with the streak, size toggle, difficulty list with solved counts and
   best times.
2. `difficulties.dart` and the pre-warm call on open.
3. Tests: every (size, difficulty) the menu can offer parses as a `PuzzleId`; 6x6 Expert is not
   offered; the continue card appears only with an `inProgress` entry; the streak reads from the
   active profile and changes when the profile does; opening the menu pre-warms exactly one id.

**Done when:** the daily card, both sizes and every offered difficulty launch a playable board, and
switching profile changes the solved counts, best times and streak on screen.

### PR 9 — Integration smoke test and phase close (0.5–0.75 day)

Commits:
1. `app/integration_test/sudoku_smoke_test.dart`: launch, open Sudoku, generate a real 9x9 Medium
   through the isolate, enter digits, background and foreground the app, assert the board survived.
2. `AGENTS.md`: how to run it and that CI does not (§7).
3. `PLAN.md`: phase 3 marked done; §5.2's `puzzleCache` value and the `mistakeFeedback` setting
   updated; §3.7 reconciled with what shipped; §7's phase-3 entry carrying the outcome and
   everything that differed. `PLAN-phase-3.md` gets the closed banner.

**Done when:** the integration test passes on the Android device with a real generated puzzle, the
`PLAN.md` §7 phase-3 done-criterion is quoted with its result, and anything that differed from this
file is recorded in both files rather than in a commit message.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| The in-progress encoding changes after a save ships, so resume breaks or needs a migration | High | Nothing has shipped yet, so it is free to change until phase 6. It is frozen inside phase 3 by the PR 4 round-trip test, and it is fixed-width so a wrong-length string is rejected rather than decoded into a plausible board. |
| A board holding a wrong digit is fed to `SudokuBoard.fromClues`, which throws in front of a child | Medium | §4.3: the session never builds a board from raw entries. The hint path filters to entries matching the solution, and PR 7 has a test that hints on a board with a wrong digit. |
| `compute()` is called on the UI isolate by accident later | Medium | PR 3's test asserts `generateSudoku` appears exactly once in `app/lib`. Textual, so it can be evaded — but the same shape of check has caught the same shape of mistake in `check_offline.dart`. |
| Widget tests generate real puzzles and `flutter test` grows from 5 s to minutes | Medium | `FakePuzzleSource` is the default in the test harness, and exactly one test (PR 3) uses the real source. If the suite passes 15 s, the cause is visible in `--reporter expanded` per-file timings. |
| A cheap tablet drops frames repainting 81 cells per keystroke | Medium | Per-cell subscriptions (§4.5). Unmeasured until hardware is in hand — there is no frame benchmark in this phase, and the honest mitigation is the device pass in PR 5 rather than a number. |
| The 150 ms spinner delay hides a 500 ms tail generate and the screen looks frozen | Low | The spinner appears at 150 ms; the tail case is exactly when it does appear. The pre-warm means the daily puzzle is usually cached before it is tapped. |
| Cache eviction drops a puzzle a child is resuming | Medium | In-progress ids are pinned across all profiles (§4.8), with a test. |
| Solving does not update the streak because the puzzle was not the daily one | Low | The streak updates when the solved index equals today's day index, at any size or difficulty (§4.7), tested at same-day, next-day and gap boundaries. |
| No emulator in CI, so `integration_test/` never runs on a merge | Medium | Accepted for this phase and written down rather than implied: the test runs on demand on a device, `AGENTS.md` says how, and adding an emulator job is §9's open question. The widget-level resume test is the check that runs on every commit. |
| Scope creep from phase 5 — sound, haptics, landscape, screen-reader polish | Medium | §2 lists each with its phase. A `flutter_soloud` line in `pubspec.yaml` in this phase's diff is the tell. |
| 9x9 Expert frustrates a child and there is no way back | Low | It is last in the list, `atCompletion` mistake mode is not the default, and hints always produce a digit — path 3 of §4.6 exists for exactly the board where technique stalls. |

---

## 8. Verification checklist

- [ ] `tool/verify.sh` passes from a clean checkout.
- [ ] `cd app && flutter test` passes in under 15 s.
- [ ] `cd packages/puzzle_engine && dart test` passes with no golden file changed by PR 1.
- [ ] `dart tool/check_offline.dart` reports no violations, with no new dependency in
      `app/pubspec.lock`.
- [ ] `dart tool/check_determinism.dart` still passes; PR 1 added no clock, `dart:math` or map-order
      iteration to the engine.
- [ ] A widget test solves a 6x6 end to end by tapping and asserts the stored `SolvedPuzzle`.
- [ ] A widget test rebuilds a played board from the encoded save alone and compares all cells, all
      note masks, the elapsed time, the hint count and the undo stack.
- [ ] A widget test pumps the play screen at `TextScaler.linear(2.0)` with no overflow.
- [ ] Every (size, difficulty) the menu can offer parses as a `PuzzleId`, and 6x6 Expert is not
      offered.
- [ ] `grep -rn "generateSudoku" app/lib` returns exactly one hit, in the isolate entry point.
- [ ] On the Android device: play a 9x9 to completion, force-quit mid-puzzle and relaunch, and the
      board, notes and timer come back exactly.
- [ ] On the Android device: solved state and best time survive a restart, and the daily streak
      increments the following day (or with the device clock moved forward one day).
- [ ] `app/integration_test/sudoku_smoke_test.dart` passes on the device against a real generated
      puzzle.
- [ ] `PLAN.md` §3.7, §5.2 and §7 match what was built, and this file carries its closed banner.

---

## 9. Open questions

| Question | Current assumption | What resolves it |
|---|---|---|
| Should the daily card offer one fixed size and difficulty rather than the last played? | Assumed last played, defaulting to 9x9 Easy (§4.7): a child who plays 6x6 should not be handed a 9x9 every morning. | PR 8's review, on the device. Changing it is a line in the menu's provider. |
| ~~Is one streak across all sizes and difficulties right, or should it be per size?~~ | **Resolved before PR 2: one streak.** `DailyStreak` stays the single object §4.7 already assumed; `ProgressRepository.recordSolved` counts any size and difficulty against it. | Decided; PR 2 built it this way. |
| Should CI gain an Android emulator job so `integration_test/` runs on merges? | Assumed no for phase 3: an emulator job is several minutes per run and the widget-level resume test covers the same path. | A phase-6 decision, when release checks need device evidence anyway (`PLAN.md` §9). |
| Does the completion card need a *Next puzzle* that respects the difficulty the puzzle actually came out as, when `widened` is set? | Assumed no: *Next puzzle* is index + 1 at the requested difficulty, and `widened` stays invisible (§2). | PR 7. Nothing stored depends on it. |
| ~~Should `mistakeFeedback` be per profile rather than device-wide?~~ | **Resolved before PR 2: per profile.** The field lives on `Profile`, not `AppSettings`; §4.6 is updated to match. | Decided; PR 2 built it this way. |

---

## 10. Starting order

1. **PR 1 — `nextPlacement`.** It is the only change to `packages/puzzle_engine` in this phase, and
   landing it alone is what makes "no golden file changed" a reviewable claim rather than a line in
   a large diff.
2. **PR 2 — the repository writes.** Everything above stores through it, and the two schema-shaped
   questions in §9 — one streak or seven, and where `mistakeFeedback` lives — have to be answered
   before it merges rather than after a save file exists.
3. **PR 3 — the puzzle source.** It unblocks every widget PR by giving them a fake, and it is where
   the `PLAN.md` §3.5 spinner and pre-warm decisions get made once instead of at each screen.
