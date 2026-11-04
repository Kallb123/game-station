# Best times that say how they were set

A best time on the Sudoku and Tracks menus is the fastest solve of a size and difficulty, and nothing
else. A two-minute solve with five hints and a dozen wrong digits reads the same as a two-minute solve
with neither, so the number cannot tell a child — or the parent beside them — whether it was earned by
thinking or by trying everything. This plan stores the hints and mistakes of the solve that set each
best time, and shows them beside it. Where this file and [`PLAN.md`](PLAN.md) disagree, the reason is
stated here and `PLAN.md` §5.2 is updated in the same change.

## 1. Scope and constraints

| Constraint | Rationale |
|---|---|
| Sudoku and Tracks only. | They are the two games with a best time and with hints and mistakes. The arcade games keep score tables; a run has neither hints nor mistakes. |
| `schemaVersion` stays 1; the change is one optional field per game. | Adding an optional field to an existing object is not a shape change (`PLAN.md` §5.2, `mistakeFeedback`). A bump would make every older build refuse a players file from this one (`PLAN-transfer.md`), for a field an older build can safely drop. |
| `bestTimeMs` keeps its shape: a map of `"<size>:<tier>"` to an integer. | An older build reads it strictly as integers (`save_codec.dart` decision 1). Turning the values into objects would make that build treat every newer save as corrupt and start fresh. |
| A detail is shown only when it is known to belong to the best time. | Showing the hints of a different, slower solve beside the best time is worse than showing none. Section 4.2's consistency rule is the mechanism. |
| The menu label stays one short line of plain words. | The audience is a child (`AGENTS.md`). The words reuse the completion card's: *hints*, *mistakes*, *No hints, no mistakes*. |

## 2. Non-goals

- **Ranking by hints or mistakes.** The best time is still the fastest solve. Whether a clean slow
  solve should outrank a fast assisted one is a separate decision (§8); this change makes the
  difference visible, which is what was asked for.
- **A second, "clean only" best time.** Same reason, and it would double the menu text.
- **A "new best" banner on the completion card.** The card already shows this solve's hints and
  mistakes.
- **Arcade high scores.** See §1.
- **Rewriting existing saves.** An old best time gains its detail at read time where `solved` still
  holds the solve (§4.3); nothing migrates the file.

## 3. Approach

Each progress object gains `bestSolve`: a map from the same `"<size>:<tier>"` key to the
`SolvedPuzzle` that set the best time. `SolvedPuzzle` already carries `timeMs`, `hints`, `mistakes`,
`solvedAt` and `clean`, and already has a reader and writer in the codec, so the new field adds no new
type. The repository writes it in the same mutation that lowers `bestTimeMs`.

**The load-bearing decision** is keeping `bestTimeMs` as the authority and treating `bestSolve` as a
detail that must agree with it (§4.2). If that changes — for example `bestSolve` becoming the only
store — an older build that drops the unknown field would silently lose every best time on its next
write.

| Alternative | Rejected because |
|---|---|
| Change `bestTimeMs` values to `{timeMs, hints, mistakes}` objects | An older build reads the values strictly as integers, so it would refuse the whole save and start fresh. Needs a schema bump and a migration step, and breaks transfer from a newer device to an older one. |
| Two parallel integer maps, `bestTimeHints` and `bestTimeMistakes` | Three maps that must agree instead of two, and a new shape for data `SolvedPuzzle` already describes. |
| Store the puzzle id of the best solve and look it up in `solved` | `recordSolved` overwrites `solved[id]` when a puzzle is replayed, so a slower replay would silently change the hints shown beside a faster time. |
| Derive everything from `solved` at read time, store nothing | Same overwrite problem, and `bestTimeMs` is stored precisely so the menu need not search `solved` (`save_data.dart`). Kept only as the fallback for saves written before this change (§4.3). |

## 4. Design

### 4.1 Data: `app/lib/core/storage/save_data.dart`

```dart
class SudokuProgress {
  // … existing fields …
  /// `"9x9:easy"` to the solve that set [bestTimeMs] for that key.
  final Map<String, SolvedPuzzle> bestSolve;   // default const {}

  /// The solve behind the best time for [key], or null when none is known.
  SolvedPuzzle? bestSolveFor(String key);
}
```

`TracksProgress` gains the same field and method. Both take part in `copyWith`, `==` and
`hashCode`, as every other field does.

### 4.2 The consistency rule

`bestSolveFor(key)` returns `bestSolve[key]` only when `bestTimeMs[key]` is non-null and equal to
`bestSolve[key].timeMs`; otherwise null. This covers the one way the two can disagree without a hand
edit: a newer save opened by an older build, which drops `bestSolve` on its next write — but if a
future build kept a stale entry, the rule still refuses to show a detail for a time it does not
describe.

### 4.3 Saves written before this change

A best time set before this change has no `bestSolve` entry. `SudokuMenu.of` and `TracksMenu.of`
already walk `solved` and parse every key; during that walk each also collects, per tier key, the
solved entries whose `timeMs` equals `bestTimeMs[key]`. Among those it picks the one with the fewest
`hints + mistakes`, then the lowest puzzle id, so the result does not depend on map order. The menu's
answer for a tier is `progress.bestSolveFor(key)`, else that fallback, else null. Nothing is written
back: the next faster solve writes a real entry.

### 4.4 Codec: `app/lib/core/storage/save_codec.dart`

`bestSolve` is read with `_readMapOf(…, _readSolvedPuzzle)` under `sudoku.bestSolve` and
`tracks.bestSolve`, optional and defaulting to empty, and written with
`_sorted(…, _writeSolvedPuzzle)` so the bytes stay a function of content. A value of the wrong type
is a `SaveFormatException` naming its path, as everywhere else in the codec.

### 4.5 Repository: `app/lib/core/storage/progress_repository.dart`

`recordSolved` and `recordTracksSolved` already decide `best == null || result.timeMs < best`. Under
that same condition they now also write `bestSolve[key] = _stamped(result)`. A slower or equal solve
changes neither map. The stamped value is the same one stored in `solved`, so the two agree on
`solvedAt`.

### 4.6 Menu label: `app/lib/core/ui/puzzle_menu.dart`

`tierProgressLabel` gains an optional `({int hints, int mistakes})? bestAssists`, and `DifficultyRow`
a matching optional field passed through from the menus. The record type keeps `core/ui` free of the
storage layer.

| Case | Label |
|---|---|
| Nothing solved | `Not solved yet` (unchanged) |
| Best time, detail unknown | `Solved 3 · Best 4:05` (unchanged) |
| No hints and no mistakes | `Solved 3 · Best 4:05 · No hints, no mistakes` |
| Some of either | `Solved 3 · Best 4:05 · 2 hints, 1 mistake` |
| Only one kind | `Solved 3 · Best 4:05 · 1 hint` — a zero count is left out |

Singular and plural follow the count. *No hints, no mistakes* is `completionCleanLabel`, so the
menu and the completion card use one phrase for one fact.

## 5. Repository layout

| File | Change |
|---|---|
| `app/lib/core/storage/save_data.dart` | `bestSolve`, `bestSolveFor` on both progress classes. |
| `app/lib/core/storage/save_codec.dart` | Read and write `bestSolve`. |
| `app/lib/core/storage/progress_repository.dart` | Write `bestSolve` beside `bestTimeMs`. |
| `app/lib/core/ui/puzzle_menu.dart` | Label and `DifficultyRow` field. |
| `app/lib/features/sudoku/model/sudoku_menu.dart`, `features/tracks/model/tracks_menu.dart` | `bestAssists(spec, difficulty)`, with the §4.3 fallback. |
| `app/lib/features/sudoku/ui/sudoku_menu_screen.dart`, `features/tracks/ui/tracks_menu_screen.dart` | Pass it to the row. |
| `PLAN.md` §5.2 | Document `bestSolve` in prose, as the Tracks fields are. |

The label lives in `core/ui` because both menus share it (`PLAN-phase-9-tracks.md` §4.14); the
fallback lives in each menu because each already owns the walk over `solved` and the parsing of its
own ids.

## 6. Phases

One pull request. Estimates assume one agent working continuously; the range is the app test suite's
two minutes per run multiplied by however many fix-and-rerun rounds it takes.

### Phase A — storage (about 1 hour)

`bestSolve` on both classes, codec round trip, repository writes, and tests for each: the codec
reads, writes and sorts the field and refuses a wrong type; a file without it decodes to empty; the
repository writes `bestSolve` on a faster solve and leaves it alone on a slower or equal one; and
`bestSolveFor` returns null when the times disagree.

**Done when:** `cd app && flutter test test/core/storage` passes, including a test that fails if
`recordSolved` stops writing `bestSolve` and one that fails if `bestSolveFor` ignores a time
mismatch.

### Phase B — menus (about 1 hour)

`tierProgressLabel`, `DifficultyRow`, both menus' `bestAssists` with the §4.3 fallback, both menu
screens.

**Done when:** label tests cover every row of §4.6's table; menu-model tests cover a stored
`bestSolve`, a stale one (ignored), and the fallback from `solved` including its tie-break; and a
Sudoku and a Tracks menu screen test each find `Best 4:05 · 2 hints, 1 mistake`-style text for a
seeded profile, and the Sudoku one also renders at 200% text without an overflow.

### Phase C — documents and review

`PLAN.md` §5.2, this file's closing banner, `/caveman-review` on the diff, `tool/verify.sh`.

**Done when:** `tool/verify.sh` passes in full and the PR description lists what was verified.

**Release line:** the pull request ships Phases A–C together. §8's open question does not block it.

## 7. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| A hint count shown beside a time it does not belong to | Medium | §4.2's rule, with a test that seeds disagreeing values and expects no detail. |
| An older build opening a newer save | Low | `bestTimeMs` keeps its type, so it decodes; the unknown `bestSolve` is dropped, and §4.2 hides any stale detail. Tested by decoding a save with `bestSolve` removed and asserting best times survive. |
| The menu walk becomes slow for a long history | Low | One extra comparison per solved entry, in a walk that already runs. No new pass over `solved`. |
| Label too long at 200% text scale | Low | `ListTile` subtitles wrap. `layout_sweep_test.dart` sweeps the menus with a fresh save, so it never sees the longest label; Phase B adds a menu screen test at 200% text with a seeded best solve, which fails on any overflow. |

## 8. Open questions

- **Should a clean solve outrank a faster assisted one?** This change keeps "fastest wins" and shows
  the assists. If the answer is yes, the decision in `recordSolved` changes and §4.3's fallback
  changes with it; the stored shape does not.

## 9. Verification checklist

- [ ] `tool/verify.sh` passes.
- [ ] `cd app && flutter test test/core/storage` includes `bestSolve` round-trip, sort, wrong-type
      and absent-field tests.
- [ ] `cd app && flutter test test/core/ui test/features/sudoku test/features/tracks` covers every
      row of §4.6, the §4.3 fallback, and a 200%-text menu with a seeded best solve.
- [ ] `PLAN.md` §5.2 names `bestSolve`.
- [ ] The two `bestTimeKey` docs and `bestSolve` docs agree on the key spelling.

## 10. Starting order

1. Add `bestSolve` and `bestSolveFor` to `SudokuProgress` and `TracksProgress`, then the codec.
2. Write it from `recordSolved` and `recordTracksSolved`.
3. Thread it through the menus and the label.
