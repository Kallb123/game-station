# Phase 2 — Sudoku engine

**Closed. Kept as the record of a finished phase, not as current plan.** [`PLAN.md`](PLAN.md) is the
source of truth for what the project is doing now; §7 there carries the phase-2 outcome and everything
that differed from this file, and §3.1, §3.3, §3.4, §3.5 and §3.6 have been reconciled with what was
built. Read this one for *why* a piece of `packages/puzzle_engine` is shaped the way it is — the
engine and its tests cite these section numbers throughout, which is why it stays here under its
original name rather than being deleted or moved.

Below, "will" and "is" describe the plan as it was written before the phase started, except where a
paragraph says otherwise: the sections that were rebuilt against measurements say so in place, since a
plan that no longer matches the code is worse than none.

The plan for `packages/puzzle_engine`: the PRNG, hash, board, solvers, generator and puzzle IDs, with
the determinism tests that freeze their output. [`PLAN.md`](PLAN.md) §3 is the design this expands and
§7 is the phase order; where the two disagreed, this file stated the reason and PR 7 updated
`PLAN.md`.

Phase 2 ships no user-visible behaviour. It touches nothing in `app/` except the closing
documentation: the engine is a pure-Dart package with its own tests, and schema v1 already declares
the `sudoku` fields phase 3 will fill (`PLAN.md` §5.2), so this phase owes the save file nothing.

**Release line unchanged:** `PLAN.md` §7 ships at phase 6. Nothing here blocks or advances that date on
its own.

---

## 1. Scope and constraints

| Constraint | Rationale and mechanism |
|---|---|
| Identical output for identical input, forever | Saved progress stores puzzle IDs, not grids (`PLAN.md` §5.2), so drift turns a solved puzzle into a different unsolved one. Enforced by golden files covering indices 0–99 for all seven size × difficulty combinations, compared on every CI run. |
| No `dart:math` `Random`, no clock, no `Set`/`Map` iteration order in `lib/` | Any of the three makes output depend on something other than the ID. `Random(seed)` in particular carries no cross-version guarantee. Enforced by a new `tool/check_determinism.dart` with its own `--self-test`, wired into `tool/verify.sh` and CI in PR 1. |
| Every integer operation masked to 32 bits | JavaScript numbers hold 53 bits exactly. Unmasked 32-bit multiplication in `fnv1a32` reaches 2^56 and would diverge the moment a web target exists. Enforced by running `test/rng_test.dart` and `test/hash_test.dart` under `dart test -p chrome` in CI, not by review. |
| No new runtime dependency | The engine's `pubspec.yaml` has `lints` and `test` as dev dependencies and nothing else. Everything in this phase is integer arithmetic and `dart:typed_data`, which is in the SDK. |
| `packages/puzzle_engine/lib` imports no `dart:io`, `dart:isolate`, `dart:ui` or `package:flutter` | Already enforced by `checkEnginePurity()` in `tool/check_offline.dart`. Generation runs in an isolate in phase 3, spawned by the app through `compute()`; the engine stays a plain function so its tests need no bindings. |
| Generation never fails visibly | A child cannot act on "could not generate a puzzle" (`AGENTS.md`). After 250 attempts — 40 when this row was written, raised in PR 5 against measurements in §4.7 — the generator settles for the closest attempt it saw and reports the widening in its result rather than throwing. |
| `tool/verify.sh` green before every commit | It is what CI runs, in the same order. |
| Test suites stay affordable | Narrowing is what keeps iteration fast: `dart test test/<file>` runs one file, and every file but the goldens' is about a second. **The whole suite is about 25 s at the default `FUZZ_SEEDS`, not the "under 10 s" this row first claimed** — comparing the goldens means generating all 700 puzzles, which PR 6 measured at 19 s and which is the price of the row above. The fuzz scales by `FUZZ_SEEDS`, and both CI and `verify.sh` set it to 2000 so the two remain the same list of checks; that run is about a minute. |

---

## 2. Non-goals

| Not in phase 2 | Where it belongs |
|---|---|
| Any widget, screen or route | Phase 3. This phase adds no file under `app/lib`. |
| Isolate or `compute()` wiring, spinners, pre-warming (`PLAN.md` §3.5) | Phase 3, in the app. The engine cannot import `dart:isolate` and must not know it is being run in one. |
| Populating or evicting `puzzleCache` | Phase 3. Schema v1 carries the field and nothing writes it. |
| Hint UI, mistake modes, pencil marks, undo | Phase 3 (`PLAN.md` §3.7). The solver exposes `nextStep()` so phase 3 has something to call; nothing in this phase calls it outside tests. |
| Save migration or a `generatorVersion` bump | `generatorVersion` stays 1. It is only bumped when output of a *shipped* generator changes; nothing has shipped, so goldens are simply written once and then frozen. |
| 4x4 and 12x12 sizes | The spec is size-generic, so they cost nothing later, but only `9x9` and `6x6` are constructible IDs — the parser rejects the rest, so an unsupported size fails at the boundary rather than deep in a solver. |
| Chain, colouring, swordfish and other techniques beyond `PLAN.md` §3.4's list | Still out. **This row's reasoning was wrong**, and PR 5 corrected it: "more techniques only refine the T4 label" holds for the label and not for the generator, because a tier is only reachable if the solver can *finish* a puzzle with it. Measured in PR 5, T3 was reached about once in a hundred attempts, so Hard was mostly a widened Medium. Adding the XY-wing — one technique, in T3 — fixed it; the rest stay out because the four tiers now populate. |
| Numeric difficulty scoring, star ratings, ELO | `PLAN.md` §3.4 judges by technique tier. A second scoring scheme would need its own goldens. |
| A puzzle-of-the-day *schedule* — notifications, streak arithmetic | Phase 3. This phase provides `dayIndexFor(DateTime)` and nothing that decides what to do with it. |
| Localised difficulty labels | Phase 5's i18n. The engine returns an enum, never a display string. |

---

## 3. Approach

Build bottom-up, in dependency order, and freeze each layer with tests before anything above it draws
on it:

1. **`Rng` and `fnv1a32`** — the frozen substrate. Their output is asserted against literal constants
   in the test file, so a change is visible as a diff of numbers rather than as a downstream puzzle
   changing.
2. **`SudokuSpec` and `SudokuBoard`** — shape and bitmask state. No search, no randomness.
3. **Brute-force solver** — solution counting, capped at 2. Every later layer calls it.
4. **Technique solver** — the tier judgement and, incidentally, phase 3's hints.
5. **Generator** — grow, dig, judge, retry, on top of 1–4.
6. **`PuzzleId`** — the string and date arithmetic that names a puzzle.
7. **Goldens, fuzz and benchmark** — the tests that make the whole thing a contract.

`PLAN.md` §10 puts steps 1 and 3 first for the same reason: the sequence has to be locked before
anything depends on it.

Alternatives considered:

| Option | Rejected because |
|---|---|
| `dart:math` `Random(seed)` | No guarantee of a stable sequence across Dart versions. This is the single failure that invalidates every saved puzzle ID, and it would be silent. |
| A published PRNG package | Adds a runtime dependency to a package that currently has none, and moves the frozen constant into someone else's release cadence. The algorithm is about twenty lines. |
| `crypto`'s SHA-256 for golden files | A dependency for a hash whose only job is to detect change, and its failure output says "hash differs" rather than which puzzle differs. Goldens store the clue string verbatim instead — 82 bytes a line, diffable, and a change names the puzzles it changed. This differs from `PLAN.md` §3.6, which says sha256; the closing PR updates it. |
| `Set<int>` candidates per cell | `PLAN.md` §3.5's targets. A `Set` per cell allocates 81 objects per node and iterates in insertion order, which is exactly the ordering source the determinism rule bans. |
| Symmetric digging (remove cells in rotational pairs) | Prettier grids, but a pair removal is accepted or rejected as a unit, which coarsens the clue-count control that `PLAN.md` §3.4's guard-rail bands depend on, and roughly doubles uniqueness checks. |
| Dancing Links (DLX) for the uniqueness count | Faster asymptotically on large grids and slower in practice at 9x9, where bitmask + MRV backtracking hits the §3.5 targets. It is also a second data structure to keep deterministic. |
| Shipping a pre-generated puzzle bank as an asset | Removes generation cost, and removes the endless-index property in `PLAN.md` §3.2 along with it. A bank large enough not to repeat is megabytes of assets. |
| Modulo reduction in `nextInt(bound)` | Biased for bounds that do not divide 2^32. The bias is small, but rejection sampling is four lines and the value is frozen either way, so there is no reason to freeze the biased one. |

**Load-bearing decision:** the exact byte sequence `Rng` produces, the rejection algorithm in
`nextInt`, and the order in which the generator draws from it. Every stored puzzle ID depends on all
three. If any changes after release, `generatorVersion` bumps, the goldens are regenerated, the old
generator stays reachable behind the switch and a save migration ships in the same commit
(`AGENTS.md`). Before release, a change costs only regenerating goldens — which is why this phase
front-loads them.

---

## 4. Design

### 4.1 `Rng`

**Xoshiro128+**, four 32-bit words of state, all operations masked to `0xFFFFFFFF`.

```dart
// packages/puzzle_engine/lib/src/rng.dart — not exported from puzzle_engine.dart
class Rng {
  Rng(int seed);                 // seeds s0..s3 by SplitMix32 expansion of seed
  int nextUint32();              // the raw generator step
  int nextInt(int bound);        // 1 <= bound <= 2^32, unbiased by rejection
  void shuffle<T>(List<T> list); // Fisher-Yates, descending
}
```

Decisions:

- **Xoshiro128+ over the two-word sketch in `PLAN.md` §3.1.** Four 32-bit words give a 2^128−1 period
  and pass the usual statistical batteries; the sketch's two-word xorshift is weaker for no saving.
  Its words are natively 32-bit, so nothing needs splitting to stay under 53 bits. `PLAN.md` §3.1 is
  updated in the closing PR.
- **Seeding is SplitMix32 applied four times to `seed`.** `PLAN.md` §3.1's "discard eight early
  outputs" is not needed with a SplitMix-expanded seed, and dropping it keeps the constructor free of
  a loop whose count would itself be frozen.
- **No all-zero-state guard, contrary to what this section first specified.** SplitMix32 is a
  bijection on 32 bits — xor-shift and odd-constant multiply both are — so exactly one input maps to
  zero and at most one of the four words can be zero. The guard would be a branch no test could
  enter, which is worse than its absence; `rng.dart` carries the argument next to the seeding. Built
  in PR 1.
- **`nextInt` rejects rather than folds.** `limit = 2^32 - (2^32 % bound)`; draw until the value is
  below `limit`, then take the remainder. `bound == 1` returns 0 without drawing, so a Fisher-Yates
  pass over a one-element list consumes nothing.
- **`shuffle` iterates `i` from `length - 1` down to 1**, swapping with `nextInt(i + 1)`. Written down
  because the ascending variant consumes the stream differently and produces different puzzles.
- **`Rng` is not exported** from `puzzle_engine.dart`. The app has no business seeding its own; keeping
  it in `src/` means an app-side `Rng(DateTime.now().millisecond)` does not compile. Tests import it by
  path.

Its test asserts the first 20 outputs of `Rng(0)`, `Rng(1)` and `Rng(0xFFFFFFFF)` against literal
constants written into the test file. Any change to the algorithm fails there first, before it reaches
a puzzle.

### 4.2 `fnv1a32`

```dart
int fnv1a32(String input);  // offset basis 0x811C9DC5, prime 0x01000193
```

The multiplication is split — `(h & 0xFFFF) * prime + ((((h >> 16) * prime) & 0xFFFF) << 16)`, masked
to 32 bits — because `h * 0x01000193` reaches 2^56 and loses precision on a JavaScript number. The
split form gives the same answer on both, which is what keeps a hypothetical web build on the same
puzzles.

Input is hashed as UTF-8 bytes. Puzzle IDs are ASCII by construction (§4.6), so `codeUnits` and the
UTF-8 bytes coincide; a test asserts they agree for every ID shape the parser accepts, so the
distinction cannot quietly start mattering.

### 4.3 `SudokuSpec` and `SudokuBoard`

```dart
class SudokuSpec {
  const SudokuSpec({required this.boxRows, required this.boxCols});
  static const s9x9 = SudokuSpec(boxRows: 3, boxCols: 3);
  static const s6x6 = SudokuSpec(boxRows: 2, boxCols: 3);  // 2 rows x 3 cols
  int get digits => boxRows * boxCols;   // 9 and 6
  int get cells  => digits * digits;     // 81 and 36
  String get label;                      // "9x9", "6x6" — the id fragment
}
```

Deriving `digits` from the box shape rather than storing it removes the one inconsistent state a
four-field record allows. `PLAN.md` §3.3 lists rows, cols, boxRows and boxCols; two of the four are
redundant.

```dart
class SudokuBoard {
  SudokuBoard(this.spec);                       // empty
  factory SudokuBoard.fromClues(SudokuSpec, String clues);
  final SudokuSpec spec;
  int digitAt(int index);                       // 0 = empty
  int candidateMask(int index);                 // bitmask, bit d-1 set = d legal
  bool place(int index, int digit);             // false if illegal, board unchanged
  void remove(int index);
  int get filledCount;
  String toClueString();
  SudokuBoard copy();
}
```

State is three `Uint32List`s of used-digit masks (row, column, box) plus a `Uint8List` of digits;
`place` and `remove` are four writes each, and `candidateMask` is `~(row | col | box) & fullMask`. No
per-cell collection is allocated during search, which is what makes `PLAN.md` §3.5's targets reachable.

**The clue string is part of the save format**, not just a test convenience: it is what `puzzleCache`
in `PLAN.md` §5.2 stores. It is fixed length, row-major, one character per cell, `.` for empty and
`1`–`9` (or `1`–`6`) for a digit. `fromClues` rejects a wrong length, an out-of-range character and a
clue set that already contradicts itself, so a corrupted cache entry becomes a caught error in phase 3
rather than a board with two 5s in a row.

### 4.4 Brute-force solver

```dart
int countSolutions(
  SudokuBoard board, {
  int max = 2,
  int maxNodes = 2000000,
  SearchStats? stats,   // added in PR 3
});
```

`stats` is an out-parameter carrying the node count, added because §6's done-criteria ask for a node
counter to show the search stopped at the second solution, and because a returned record would make
the common call — "is it still unique" — read worse for the one caller that does not care. PR 7's
benchmark uses it to compare boards without timing them.

Backtracking with MRV cell selection: pick the empty cell with the fewest candidates, ties broken by
lowest index — never by iteration over a collection whose order is unspecified. Digits are tried low
to high. Returns as soon as `max` solutions are found, because §3.4 only ever asks "is it still
unique".

`maxNodes` is a deterministic cap. Exceeding it returns `-1`, meaning "unknown", and every caller
treats unknown as "not unique" — the dig step restores the digit, the generator retries with the next
sub-seed. It is deterministic, so it cannot make output vary between runs, and it converts the one
non-termination risk into a bounded result.

### 4.5 Technique solver

```dart
enum Difficulty { easy, medium, hard, expert }   // index + 1 == tier T1..T4

class Elimination { final int index, digit; }    // added in PR 4
class SolveStep {
  final Technique technique;
  final int index, digit;                        // -1 and 0 for an elimination step
  final List<Elimination> eliminations;          // empty for a placement
  bool get isPlacement;
}
class SolveReport { final bool solved; final Difficulty tier; final List<SolveStep> steps; }

SolveReport solveWithTechniques(SudokuBoard board);
SolveStep? nextStep(SudokuBoard board);   // phase 3's hint; unused here outside tests
```

One enum carries both the difficulty label and the tier — `Difficulty.hard.index + 1 == 3` — so there
is no label-to-tier table to keep in step with itself.

**A step is a placement or an elimination**, which this section originally left implicit by giving
`SolveStep` an index and a digit. Only the two singles place anything; the other seven narrow other
cells and leave the grid otherwise as it was, so a step type that could only say "this cell is a 5"
had nothing to report for seven of the nine. Phase 3 reads `isPlacement` to decide whether a hint
reveals an answer or explains a reason.

**`Technique` carries its own tier and its own function**, rather than the solver holding a table of
either. The enum's declaration order is the tier order, so `solveWithTechniques` walks
`Technique.values` and the first entry that makes progress is by construction the cheapest available.
A parallel table would be a second list to keep in step, on the value that decides a puzzle's
difficulty; `technique_test.dart` asserts the declaration order is non-decreasing by tier, since
nothing else enforces it.

**Eliminations need state the board cannot hold.** `SudokuBoard.candidateMask` answers what the rules
allow, which is where a solve starts and not where it stays: ruling a 4 out of a cell because of a
naked pair elsewhere places nothing, so the board would forget it. `techniques/candidates.dart` holds
a `CandidateGrid` — the board plus the narrowed masks, plus the unit lists in their fixed scan order —
and it is what lets the techniques compose, a pointing pair setting up the naked single that follows.

Techniques, in the tier order of `PLAN.md` §3.4:

| Tier | Techniques added |
|---|---|
| T1 | naked single, hidden single |
| T2 | naked pair, hidden pair, pointing pair, box-line reduction |
| T3 | naked triple, hidden triple, X-wing, XY-wing (added in PR 5) |
| T4 | none — assigned when no T1–T3 technique makes progress on an unsolved board |

The solver loops: try techniques in tier order, apply the first that makes progress, record the
highest tier it had to reach. Each technique is a function over the board's candidate masks with a
fixed unit iteration order (rows 0..n, then columns, then boxes), so two runs produce the same step
list. `solveWithTechniques` works on a copy and never mutates its argument, since the generator calls
it on a board it is still digging.

`Technique` is an enum, not a string, so phase 3's hint text is a UI concern and this package needs no
translations.

### 4.6 `PuzzleId`

```
sudoku:9x9:hard:412
        │   │    └── index, decimal, no leading zeros
        │   └─────── easy | medium | hard | expert
        └─────────── 9x9 | 6x6
```

```dart
class PuzzleId {
  const PuzzleId(this.spec, this.difficulty, this.index);
  factory PuzzleId.parse(String id);          // throws FormatException
  String get value;                           // the canonical string
  int get seed => fnv1a32(value);
}

const DateTime puzzleEpoch = ...;             // 2026-01-01T00:00:00Z
int dayIndexFor(DateTime when);               // UTC, clamped at 0
```

Decisions:

- **Canonical form only.** `sudoku:9x9:hard:0412` is a `FormatException`, not an alias for 412. Two
  strings that name one puzzle would be two `solved` keys in the save for one puzzle.
- **6x6 expert does not parse.** `PLAN.md` §3.4: 6x6 has too little room for a genuine Expert tier, so
  the ID is rejected rather than generating something mislabelled.
- **`const DateTime puzzleEpoch` is `final`, not `const`.** [DateTime] has no const constructor, so the
  epoch is built once at load. Nothing else changes.
- **The index stops at `PuzzleId.maxPuzzleIndex`, 999 999 999.** "Whatever an int holds" is not the
  same everywhere: on the web an int is a double and stops being exact at 2^53, so a longer index
  would name one puzzle in a browser and another on a tablet — the failure this package exists to
  prevent, arriving through the parser rather than the generator. Nine digits is a puzzle a day for
  two and a half million years.
- **`dayIndexFor` clamps at 0 rather than throwing.** A tablet with its clock set to 2019 would
  otherwise crash on the daily card, and `AGENTS.md` forbids surfacing an internal error to a child.
  Every date before the epoch gets day 0's puzzle, which is wrong in a way nobody can see.
- **The date is converted to UTC first**, matching `PLAN.md` §3.2, so crossing a timezone neither skips
  nor repeats a day.

### 4.7 Generator

```dart
class GeneratedPuzzle {
  final PuzzleId id;
  final String clues, solution;
  final Difficulty requested, tier;   // differ only when widened
  final int clueCount, attempts;
  final bool widened;
}

GeneratedPuzzle generateSudoku(PuzzleId id);
```

Three stages, per `PLAN.md` §3.4, with the seed derivation written down because it is frozen:

```
attempt 0 : seed = fnv1a32(id.value)
attempt n : seed = fnv1a32('${id.value}#$n')
```

**Grow.** Backtracking fill over an empty board, trying digits in `Rng`-shuffled order per cell. A
complete grid always exists, so this backtracks but never fails.

**Dig.** Shuffle the cell index list with `Rng`, walk it once, remove one digit at a time, and keep the
hole only when `countSolutions(board, max: 2) == 1` **and the grid is still no harder than the tier
asked for**. Stop once the tier has been reached and `filledCount` is down to the recipe's floor.

Both halves of that were rebuilt in PR 5 against measurements, because the rule this section first
gave — dig blindly to the floor, then judge — aims at a clue count and hopes for a tier:

- Without the tier ceiling, 9x9 Hard came out Expert 30 times in 50: a hole that jumps the grid two
  tiers is taken and never given back. Tier never falls as clues come out, so refusing that hole and
  carrying on with the next cell costs nothing and keeps the grid inside the label.
- Stopping at the floor *regardless* of tier throws away grids that three more holes would have made
  right. Hard is reached at 24 to 26 clues far more often than at 26 exactly, so the dig now passes
  the floor while the grid is still too easy, and the band moved to where puzzles actually land.

Judging after each accepted removal costs one technique solve per hole rather than one per attempt,
and pays for itself several times over in attempts not made.

**Judge.** `solveWithTechniques` on the dug board, against the *recipe* for that size and label rather
than against the label alone. A recipe is a tier range and a clue band: `PuzzleRecipe` in
`generator.dart`, tabulated in `recipeFor`. Six of the seven combinations name a single tier; 6x6
Medium names Easy over 12 clues, because a 6x6 has no room for a tier between "singles finish it" and
"needs a triple or a wing" — needing a pair and nothing more is about one dug 6x6 in three hundred.
`PLAN.md` §3.4 records that decision and the measurement behind it.

**Retry.** Up to `generatorMaxAttempts` — **250, not 40**. The number is a budget for a search whose
hit rate is a property of Sudoku rather than of this code: at 40 attempts, 9x9 Hard widened 2 in 50
and 6x6 Hard 40 in 50; at 250 both are inside 1 in 100, and the slowest single puzzle measured is
still under the `PLAN.md` §3.5 target multiplied by the benchmark's 3x ceiling. On the last failure,
accept the closest attempt seen and widen: the result carries `widened: true` with the tier actually
achieved in `tier` and the request in `requested`. Nothing throws, and phase 3 shows the puzzle. The
widening rate is measured, not assumed — the golden run fails if more than 5 of any 100 indices
widened, which turns "expert is unreachable at 6x6-like clue counts" into a red build instead of a
silently easier game.

### 4.8 Determinism tests and goldens

```
test/golden/sudoku_9x9_easy.golden      # header + 100 lines
test/golden/sudoku_9x9_medium.golden
test/golden/sudoku_9x9_hard.golden
test/golden/sudoku_9x9_expert.golden
test/golden/sudoku_6x6_easy.golden
test/golden/sudoku_6x6_medium.golden
test/golden/sudoku_6x6_hard.golden
```

Line format: `index clueCount tier widened clues`, with a first line recording `generatorVersion: 1`.
The version line is asserted against the engine constant, so regenerating goldens without deciding
about the version fails the run that produced them.

The `widened` field — `ok` or `widened` — is a fourth column this section did not originally have.
Built in PR 6, because §7's guard-rail wants the widening rate committed rather than recomputed: it
is the one fact about a line that is not derivable from the grid, `grep -c ' widened '` answers "is
this label reachable" from the file itself, and a puzzle that starts widening shows up as a changed
line rather than as a game that is quietly easier than its label. The clue count and tier stay too,
though a re-solve could derive both: a diff moving a puzzle from `hard` to `medium` says what
happened, where two changed rows of digits do not.

Regeneration is `dart run tool/regen_goldens.dart` inside the package, and the failure message names
it. There is no automated defence against regenerating goldens to make a red build green — the
control is that the diff lists every puzzle that changed, which is unmissable in review. Stating it
plainly is better than implying a mechanism that does not exist.

Beyond goldens, per `PLAN.md` §3.6:

- Every generated puzzle has exactly one solution (`countSolutions(..., max: 2) == 1`).
- Round trip: `solveWithTechniques` on the emitted clues reports the tier the generator recorded.
- 6x6 boxes are 2 rows x 3 columns, checked by placing a digit and asserting which cells lose it.
- The same seed generates byte-identical output twice in one process — `generator_test.dart`, since
  PR 5 — and across two `dart test` invocations, which is what the goldens check. Both halves are
  needed: the first catches state left between calls, the second catches output that depends on the
  build, the platform or the day.
- Fuzz: `FUZZ_SEEDS` puzzles (default 200, CI and `verify.sh` set 2000) dealt round-robin across
  every size and difficulty — no throw, no `-1` from the node cap, and no single generate over 2 s.
  Non-termination is caught by `dart test`'s own per-test timeout; the 2 s assertion catches
  slow-but-terminating, which is the failure a timeout alone would let through as an occasional flake.

  **`FUZZ_SEEDS` counts puzzles in total, not indices per combination**, which is what this section
  first meant. Measured in PR 6, the seven combinations differ in cost by two orders of magnitude — a
  6x6 Easy is 0.1 ms at the median and a 9x9 Hard is 51 ms — so 2000 indices *each* is about five
  minutes of fuzz, against the "about three minutes" §7 promised for the whole of `verify.sh`. A
  3-minute check that could have been 40 s is the check people stop running, which is the risk §7
  already names. 2000 across the matrix is 285 or 286 indices of each, which still walks every
  combination well past the 100 the goldens freeze.

Measured on the development container, and the reason `PLAN.md` §3.5's targets have room: over those
2000 puzzles, 4 were widened (all 6x6 Hard, none anywhere else) and the slowest single generate was
547 ms, against the 2 s ceiling. Per combination, p50/p95/max in ms: 9x9 Easy 0.9/1.5/22.8, Medium
34.8/161.8/547.0, Hard 51.1/244.2/483.1, Expert 25.1/78.7/186.0; 6x6 Easy 0.1/0.4/2.1, Medium
0.2/0.3/1.8, Hard 9.6/52.4/79.8. PR 7's benchmark is what holds these to a ceiling; this is what they
were when the goldens were written.

### 4.9 Benchmark

`packages/puzzle_engine/tool/benchmark.dart` generates 50 puzzles for each size × difficulty and prints
p50, p95 and max in milliseconds. It may use `dart:io` — the purity check scans `lib/` only.

It exits non-zero above **three times** the `PLAN.md` §3.5 target (so: 300 ms for 9x9 easy and medium,
1200 ms for hard and expert, 90 ms for 6x6), while printing the measurement against the real target.
The ceiling is loose on purpose: a shared CI runner varies by more than a factor of two, so a tight
assertion would be a flaky build that gets deleted, whereas an order-of-magnitude regression is a real
one and is caught.

---

## 5. Repository layout

```
packages/puzzle_engine/
├─ lib/
│  ├─ puzzle_engine.dart          # exports the app-facing API only
│  └─ src/
│     ├─ generator_version.dart   # exists
│     ├─ uint32.dart              # mask, 2^32, split multiply — not exported
│     ├─ digit_mask.dart          # the candidate bitmask helpers — added in PR 4
│     ├─ rng.dart                 # not exported
│     ├─ hash.dart                # not exported
│     ├─ difficulty.dart          # the tier enum — added in PR 4
│     ├─ sudoku_spec.dart
│     ├─ sudoku_board.dart
│     ├─ solver.dart              # countSolutions
│     ├─ techniques/
│     │  ├─ technique.dart        # enum + the step type
│     │  ├─ candidates.dart       # CandidateGrid and the units — added in PR 4
│     │  ├─ singles.dart
│     │  ├─ subsets.dart          # naked/hidden pairs and triples
│     │  ├─ intersections.dart    # pointing pair, box-line reduction
│     │  ├─ fish.dart             # x-wing
│     │  └─ wings.dart            # xy-wing — added in PR 5
│     ├─ technique_solver.dart    # tier judgement, nextStep
│     ├─ generator.dart           # grow / dig / judge / retry
│     └─ puzzle_id.dart
├─ test/
│  ├─ rng_test.dart               # also runs under -p chrome
│  ├─ hash_test.dart              # also runs under -p chrome
│  ├─ sudoku_board_test.dart
│  ├─ solver_test.dart
│  ├─ technique_test.dart         # one fixture per technique
│  ├─ generator_test.dart
│  ├─ puzzle_id_test.dart
│  ├─ determinism_test.dart       # the goldens; same-seed equality is generator_test's
│  ├─ fuzz_test.dart              # FUZZ_SEEDS
│  ├─ combinations.dart           # the seven size-and-label pairs, shared by four files
│  ├─ golden_format.dart          # the golden line format, shared with regen_goldens.dart
│  └─ golden/*.golden
└─ tool/
   ├─ benchmark.dart
   └─ regen_goldens.dart
```

Boundaries:

- **`rng.dart` and `hash.dart` stay unexported.** Freezing a sequence is only meaningful if nothing
  outside the package can start a different one.
- **`uint32.dart` was added in PR 1**, holding the 32-bit mask, 2^32 as a literal and the split
  multiply of §4.2. The PRNG's SplitMix32 seeding needs that multiply as much as the hash does, and
  two copies of a subtle masked multiply is two chances to fix only one of them — on a function whose
  answer every stored puzzle ID depends on.
- **`techniques/` is one file per family, not one per technique.** Naked and hidden pairs share their
  unit scan; splitting them would duplicate it.
- **`difficulty.dart` is its own file rather than part of the technique enum's.** `Technique` names its
  tier, so the two cannot live in one file without the app-facing type sitting inside `techniques/`,
  which is the wrong way round: `Difficulty` is what phase 3 shows a child, and `Technique` is an
  implementation detail of judging.
- **`digit_mask.dart` was added in PR 4**, holding the candidate bitmask's bit numbering, its
  population count and the digit of a single-bit mask. `solver.dart` had a private copy of the count
  and every technique needs it; a bit numbered from the wrong end produces a plausible grid rather
  than an error, which is exactly the kind of thing to write once.
- **`solver.dart` (counting) is separate from `technique_solver.dart` (judging).** The first is called
  once per dug cell and is the hot path; the second is called once per attempt. Keeping them apart
  keeps an optimisation in one from quietly changing the other's step order.
- **`tool/` is inside the package, not the repository's `tool/`.** These two scripts import
  `package:puzzle_engine/…`, and the repository's `tool/` is analysed as part of the root package.
- **`tool/check_determinism.dart` is at the repository root**, next to `check_offline.dart`, because
  `tool/verify.sh` and CI run it and it scans a directory rather than importing it.

---

## 6. Pull requests

One PR per row, merged in order; each leaves the package analysing, testing and green. Estimates assume
one developer working part time, roughly half a working day per unit — the same basis as
`PLAN-phase-1.md` §6. Ranges widen where fixtures have to be built by hand (PR 4) or where a CI
behaviour cannot be checked locally (PR 1's web run). Total 5.25–6.75 days, against `PLAN.md` §7's 5–7
for the phase.

Every PR runs `tool/verify.sh` and a `/caveman-review` pass before it opens, per `AGENTS.md`.

### PR 1 — `Rng`, `fnv1a32` and the determinism guard (0.75–1 day)

Commits:
1. `src/rng.dart` — Xoshiro128+, SplitMix32 seeding, rejection `nextInt`, descending Fisher-Yates.
2. `src/hash.dart` — `fnv1a32` with the split multiply.
3. `tool/check_determinism.dart` plus its `--self-test`: fails on an `import 'dart:math'`,
   `DateTime.now`, `Stopwatch`, or iteration over `.keys`/`.values`/`.entries` anywhere in
   `packages/puzzle_engine/lib`, with a `// determinism: ok` opt-out for a reviewed case. Wired into
   `tool/verify.sh` and `.github/workflows/ci.yml`. As built it also rejects `DateTime.timestamp`,
   which is the same clock behind a different name, and allows `SomeType.values`, which is
   declaration-ordered rather than hash-ordered.
4. A CI step running `dart test -p chrome test/rng_test.dart test/hash_test.dart` in the engine
   package. `tool/verify.sh` runs it too, but skips it with a printed note when the machine has no
   Chrome — the one place the local script is knowingly a subset of CI, stated rather than hidden.

**Done when:** `rng_test.dart` asserts the first 20 `nextUint32()` values of `Rng(0)`, `Rng(1)` and
`Rng(0xFFFFFFFF)` against literals; a 1 000 000-draw `nextInt(3)` test shows each outcome within 0.5%
of a third; the same two test files pass under `-p chrome`; and `check_determinism.dart --self-test`
fails against a fixture containing each banned construct and passes against the real `lib/`.

### PR 2 — `SudokuSpec` and `SudokuBoard` (0.5 day)

Commits:
1. `src/sudoku_spec.dart` with `s9x9` and `s6x6`.
2. `src/sudoku_board.dart` — masks, `place`/`remove`, `candidateMask`, clue-string codec.
3. Tests, including a naive `Set`-based reference board used only in tests.

**Done when:** `candidateMask` agrees with the naive reference on 10 000 `Rng`-seeded partial boards
for both specs; a clue string round-trips through `fromClues`/`toClueString` unchanged; and
`fromClues` throws on a wrong length, an out-of-range character, and a grid with a duplicate in a unit.

### PR 3 — Brute-force solver (0.75 day)

Commits:
1. `src/solver.dart` — MRV backtracking, `max` early exit, `maxNodes` cap.
2. Tests over hand-entered grids.

**Done when:** a known 17-clue 9x9 counts exactly 1; an empty 9x9 returns 2 and a node counter proves
the search stopped at the second solution; a legal grid with no completion returns 0; a board built to
exceed `maxNodes: 100` returns `-1`; and every count is identical across two runs.

The 0 case was written as "a grid with a contradictory clue pair", which PR 2 made unconstructible:
`SudokuBoard` refuses a duplicate in a unit, so a board holding one cannot be built to hand to the
solver. Two grids that *are* constructible replace it — one whose empty cell has no candidates, found
before any move, and one that is legal everywhere and still has no completion, which takes 1361 nodes
to refute. The second is the one worth having: it is the search saying 0, not the board.

### PR 4 — Technique solver and tiers (1–1.5 day)

Commits:
1. `techniques/` — singles, subsets, intersections, x-wing, each with the enum entry.
2. `src/technique_solver.dart` — tier loop, `SolveReport`, `nextStep`.
3. `technique_test.dart` — per technique, a fixture where that technique is the only progress
   available, asserting both the deduction and that the tier loop reached exactly that tier.

**Done when:** each of the nine techniques has a fixture that fails if that technique is removed; a
board solvable by singles alone reports `Difficulty.easy`; a board needing an x-wing reports
`Difficulty.hard`; a board no technique advances reports `Difficulty.expert` with `solved: false`; and
a test asserts the input board is byte-identical after `solveWithTechniques` returns.

Three things about the fixtures, all found while building them:

- **They are checked by search, not by assertion of what the solver said.** Every elimination is put
  back on the board and handed to `countSolutions`, which must then report no solution at all; every
  placement is the only digit that leaves one. A technique that ruled out a digit the puzzle needs
  fails there rather than merely disagreeing with a number typed into the test file.
- **A hidden triple cannot be the first available technique below a nine-cell unit.** If the unit has
  six or fewer empty cells, the three the triple does not occupy hold exactly the unit's remaining
  digits — a naked subset of three or fewer, which is tried first. So there is no 6x6 hidden-triple
  fixture, and the 9x9 one needed a position with a wide-open box; it was built by adding solved cells
  to a dug position until the rest of the grid fell to T1–T3, since no natural one turned up in about
  20 000 dug puzzles.
- **"A board no technique advances" is the empty grid, plus a real Expert puzzle for the tier.** Every
  one of 5000 minimal grids dug while building this test offered at least one *elimination* on its
  opening position, so a committed puzzle fixture with no step at all is not something this search
  found. The empty grid is the case in its pure form — every digit possible everywhere, so nothing is
  a single and nothing is confined — and a 25-clue Expert puzzle covers `tier: expert` with
  `solved: false` on a grid that is a puzzle.

### PR 5 — Generator and `PuzzleId` (1–1.5 day)

Commits:
1. `src/puzzle_id.dart` — parse, canonical `value`, `seed`, `puzzleEpoch`, `dayIndexFor`.
2. `src/generator.dart` — grow, dig with the band floor, judge, the 40-attempt retry and widening.
3. `puzzle_engine.dart` exports the app-facing API.
4. Tests for both.

**Done when:** for 200 indices per size × difficulty, every result has exactly one solution, a clue
count inside its `PLAN.md` §3.4 band, and a judged tier equal to `requested` unless `widened` is set;
`PuzzleId.parse` rejects `sudoku:9x9:hard:0412`, `sudoku:6x6:expert:1` and `sudoku:4x4:easy:1`;
`dayIndexFor` returns 0 for 2026-01-01 UTC, 0 for 2019-06-01, and agrees across a timezone offset
either side of midnight; and generating the same ID twice returns identical clue strings.

### PR 6 — Goldens, fuzz and the suite wiring (0.75 day)

Commits:
1. `tool/regen_goldens.dart` and the seven golden files.
2. `determinism_test.dart` and `fuzz_test.dart` with `FUZZ_SEEDS`.
3. `tool/verify.sh` and CI run the fuzz with `FUZZ_SEEDS=2000`; `AGENTS.md`'s command table and its
   "about a minute" line are updated to match.

**Done when:** all seven goldens are committed with a `generatorVersion: 1` header and compared in CI;
no golden file has more than 5 widened entries in 100; the 2000-seed fuzz passes with no generate over
2 s; and perturbing one Xoshiro constant is shown to turn the goldens red before being reverted —
recorded in the PR body, per `AGENTS.md`'s rule that a guard is checked against the broken version.

Met: 1 of 700 golden puzzles is widened, and changing `rotl32(_s[3], 11)` to `12` turned eleven tests
red — all seven golden comparisons, each naming 100 of 100 changed puzzles, plus four `rng_test.dart`
literals. Differed from the plan, decided while building it:

- **A golden line gained a fourth field, `ok` or `widened`** (§4.8), so the widening rate is committed
  rather than recomputed.
- **`FUZZ_SEEDS` counts puzzles in total rather than per combination** (§4.8), because per combination
  it is five minutes of fuzz and a five-minute check is the check people stop running.
- **The suite is about 25 s at the default rather than §1's "under 10 s"**, because comparing goldens
  means generating them. §1 says so now, and `AGENTS.md`'s runtimes moved with it.

### PR 7 — Benchmark and phase close (0.5–0.75 day)

Commits:
1. `tool/benchmark.dart` and a CI step at the 3× ceiling.
2. `PLAN.md`: phase 2 marked done; §3.1 updated to Xoshiro128+ with the SplitMix seeding; §3.3's
   four-field spec reduced to the box shape; §3.6's sha256 replaced by the verbatim clue string.
3. `packages/puzzle_engine/README.md` status section; anything that differed recorded here and in
   `PLAN.md` §7.

**Done when:** `dart tool/benchmark.dart` prints p50/p95/max per combination on the development
machine, the numbers are recorded in the PR body against the `PLAN.md` §3.5 targets with any miss
named, and the CI step passes at the 3× ceiling.

Met. Differed from the plan, decided while closing it:

- **The command is `dart run tool/benchmark.dart`**, and it is in `tool/verify.sh` as well as in CI —
  `AGENTS.md` says `verify.sh` is everything CI runs, and a benchmark that only ran on a merge would
  make that sentence false for the sake of ten seconds.
- **The ceiling applies to the median, not to the max**, which §4.9 did not pin down. One slow puzzle
  in fifty is a property of Sudoku rather than of this code, and the tail already has a guard in the
  fuzz's 2 s per-puzzle ceiling over 2000 puzzles. p95 and max are printed so a tail that moves is
  visible without failing a build.
- **It warms up three puzzles per combination before timing.** The VM compiles a method properly only
  after it has run a few times, so without that the first puzzle of each combination lands in the
  `max` column at ten to twenty times its own median — which is the column somebody reads to decide
  whether the tail moved.
- **Every median is inside the plain §3.5 target, not merely inside the 3× ceiling**, but two p95s are
  not: 9x9 Medium at 138 ms against 100 ms, and 6x6 Hard at 54 ms against 30 ms. Named rather than
  averaged away. `PLAN.md` §3.5 records them and answers them with the cache and the pre-warm, which
  is phase 3's work: a puzzle is generated once and read from the save file thereafter.
- **`PLAN-phase-2.md` is not deleted.** `PLAN-phase-1.md`'s PR 7 said "delete or archive this file";
  the convention that settled instead — a banner marking it closed, in place, under its original name
  — is what `AGENTS.md` now describes, and it is what the engine's comments depend on.

---

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| A masking step is missed and native and web diverge | High | Every operation masks; `rng_test.dart` and `hash_test.dart` run under `dart test -p chrome` in CI from PR 1. Residual: only those two files are covered, since the generator is not run in a browser — a divergence introduced in the generator's own arithmetic would not be caught until a web target exists, and there is no web target planned. |
| Goldens are regenerated to turn a red build green | High | None that is automated. The `generatorVersion` header line makes the version decision explicit, and the diff names every changed puzzle. This is a review control, stated as one. |
| Expert at 9x9 is rarely reachable, so most puzzles silently widen | Medium | `widened` is recorded per puzzle and the golden files carry it; the determinism test fails above 5 widened in 100. If it fails, the fix is the band in `PLAN.md` §3.4, decided with data rather than by loosening the check. |
| Uniqueness counting misses `PLAN.md` §3.5's targets on Expert | Medium | Bitmask board and MRV from PR 2 and PR 3; PR 7's benchmark measures it. If Expert misses, the isolate in phase 3 keeps the UI responsive and the cache makes it once-per-puzzle — the target slips, the app does not. |
| A `Map`/`Set` iteration sneaks into `lib/` and output drifts between runs | Medium | `tool/check_determinism.dart` from PR 1, in `verify.sh` and CI, with its own self-test. It is a textual scan, so it can be evaded; the golden files are the backstop that catches the effect rather than the cause. |
| The technique solver disagrees with the generator about a puzzle's tier | Medium | The round-trip assertion in PR 5 re-judges the emitted clue string and compares with the recorded tier, so the two cannot drift apart unnoticed. |
| Generation loops forever on some seed | Medium | `maxNodes` caps the counting solver deterministically, the retry loop caps at `generatorMaxAttempts` (250 since PR 5, 40 when this row was written), and the fuzz asserts a 2 s per-puzzle ceiling. Non-termination inside one solver call is bounded by `maxNodes`, not by a timer. |
| The 2000-seed fuzz makes `verify.sh` slow enough that people skip it | Medium | `FUZZ_SEEDS` defaults to 200 for a per-file run while iterating; `verify.sh` and CI both set 2000, so the two never diverge into "the check CI runs" and "the check we run". PR 6 measured it: the engine suite is about a minute at 2000 and `verify.sh` about a minute and a half, so `AGENTS.md`'s "about a minute" moved with it rather than being left wrong. The five-minute version of this — 2000 indices of *each* combination — is what §4.8's total-rather-than-per-combination reading avoids. |
| The clue-string format is wrong for phase 3's `puzzleCache` | Low | It is a fixed-length row-major string with `.` for empty, which is what `PLAN.md` §5.2 already stores, and `fromClues` validates it. Changing it later is a save migration, not a generator change. |
| Scope creep into phase 3 while building the hint API | Medium | `nextStep()` is one function with a test and no caller. A widget in this phase's diff is in the wrong directory. |

---

## 8. Verification checklist

- [x] `tool/verify.sh` passes from a clean checkout.
- [x] `dart tool/check_determinism.dart --self-test` fails against each banned construct and passes
      against `packages/puzzle_engine/lib` — 25 self-test cases, 20 files clean.
- [x] `dart tool/check_offline.dart` reports no violations, including engine purity.
- [x] `cd packages/puzzle_engine && dart test` passes at the default `FUZZ_SEEDS`, in about 25 s —
      the goldens are 19 s of that, and `dart test test/<file>` is what stays fast while iterating.
- [x] `cd packages/puzzle_engine && dart test -p chrome test/rng_test.dart test/hash_test.dart` passes.
      Run against the container's Chromium; `verify.sh` skips it locally for want of a Chrome on
      `PATH`, and CI runs it on every push.
- [x] `FUZZ_SEEDS=2000 dart test test/fuzz_test.dart` passes with no generate over 2 s.
- [x] The 2000-puzzle fuzz's widening rate and slowest generate are recorded in PR 6's body: 4 in 2000
      widened, all 6x6 Hard, and 547 ms.
- [x] All seven `test/golden/*.golden` files exist, carry `generatorVersion: 1`, and cover indices
      0–99.
- [x] Editing one Xoshiro constant turns the goldens red; reverted, with the run recorded in PR 6's
      body.
- [x] No banned construct in `packages/puzzle_engine/lib`. The grep this item first named —
      `grep -rn "dart:math\|DateTime.now\|Stopwatch"` — returns three hits and always will: they are
      doc comments in `rng.dart` and `puzzle_engine.dart` explaining why those constructs are banned.
      `tool/check_determinism.dart` is the check that answers the question, because it strips comments
      before scanning, which is the same reason `check_offline.dart` does.
- [x] `grep -rn "Rng\|fnv1a32" app/lib` returns nothing — neither is exported.
- [x] Every golden file has 5 or fewer widened entries per 100: one file has 1, the other six have 0.
- [x] `dart run tool/benchmark.dart` output recorded in PR 7's body against the `PLAN.md` §3.5 targets,
      with any miss named rather than omitted.
- [x] `PLAN.md` §3.1, §3.3, §3.4, §3.5, §3.6, §7 and §10 match what was built.

---

## 9. Open questions

| Question | Current assumption | What resolves it |
|---|---|---|
| Xoshiro128+ instead of `PLAN.md` §3.1's two-word sketch? | Assumed yes; the sketch is illustrative and the four-word generator is stronger for the same code size. | Owner's call before PR 1 merges. After it merges and goldens exist, changing it costs a `generatorVersion` bump. |
| ~~Golden files store the clue string rather than `PLAN.md` §3.6's sha256?~~ **Resolved: yes.** | Built in PR 6: no `crypto` dependency, and a failure names the puzzles that changed. The seven files are 76 KB, close to the ~70 KB estimated. | PR 6's diff. Changing it later costs nothing but the diff, since nothing reads a golden but its own test. |
| ~~Should `tool/verify.sh` carry the 2000-seed fuzz, taking it from about one minute to about three?~~ **Resolved: yes, and it costs less than that.** | Built in PR 6: `verify.sh` is about a minute and a half, and about two once PR 7's benchmark joined it — rather than the five-plus minutes it would have been, because `FUZZ_SEEDS` counts puzzles across the matrix rather than per combination (§4.8). `verify.sh` stays "everything CI runs" with no note about being a subset. | PR 6's measurement. If it ever becomes the reason people skip the script, the fallback is unchanged: a CI-only job and a line in `AGENTS.md` saying so. |
| ~~Is `dart test -p chrome` available on the CI runner without extra setup?~~ **Resolved: yes.** | `ubuntu-latest` ships Chrome and the step needs no browser setup. | PR 1's first CI run, green, and PR 2's after it. §7's masking risk keeps its residual note: the two frozen test files are covered, the generator's own arithmetic is not. |
| Should 9x9 Expert (T4, "needs guessing") be offered to children at all? | Assumed yes, as `PLAN.md` §3.4 specifies. The engine generates it either way. | A phase-3 decision about which difficulties the picker shows. Nothing here blocks it. |
| Does phase 3 need a "generate the next N indices" batch API for pre-warming? | Assumed no: `PLAN.md` §3.5 pre-warms one puzzle when the menu opens, which is one call. | Phase 3, when the isolate wiring is written. Adding it later is additive. |

---

## 10. Starting order

1. **PR 1 — `Rng`, `fnv1a32` and `check_determinism.dart`.** `PLAN.md` §10 puts it first: the sequence
   has to be frozen and guarded before anything draws from it, and the guard is cheapest to add while
   `lib/` has three files in it.
2. **PR 2 — `SudokuSpec` and `SudokuBoard`.** No search and no randomness, so it can be checked against
   a naive reference implementation rather than against itself.
3. **PR 3 — the counting solver.** Everything above it calls it, and its correctness is testable on
   hand-entered grids before a generator exists to produce them.
