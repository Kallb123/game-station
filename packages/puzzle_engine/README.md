# puzzle_engine

Deterministic Sudoku generation and solving for [Zibo Games](../../README.md).

Pure Dart. No Flutter, no `dart:io`, no networking — data in, data out. That keeps the tests fast
enough to fuzz thousands of seeds on every run, with no emulator and no Flutter bindings.

## Contract

A puzzle is a pure function of its ID:

```
id   = "sudoku:9x9:hard:412"
seed = fnv1a32(id)
```

The same ID must produce the same grid on every platform, in every release. Saved progress stores
IDs rather than grids, so a drift in generation would silently turn a solved puzzle into a different
unsolved one. Two things protect that:

- The PRNG and hash are implemented in this package and frozen once written — `dart:math`'s
  `Random(seed)` makes no cross-version guarantee.
- Golden files record indices 0–99 for every size and difficulty, so any change to ordering, the
  PRNG or the hash turns CI red. They store each puzzle's clue string verbatim rather than a hash of
  it: a failure then names the puzzles that changed instead of reporting that something did.

When such a change is deliberate, bump `generatorVersion` and keep the previous generator reachable
behind that switch. See [`lib/src/generator_version.dart`](lib/src/generator_version.dart).

## Status

**Complete, as of phase 2.** Generation, both solvers, puzzle IDs and the determinism tests are here
and frozen; nothing in `app/` imports the package yet, which is phase 3's work.

```dart
final puzzle = generateSudoku(PuzzleId.parse('sudoku:9x9:hard:412'));
final board = SudokuBoard.fromClues(puzzle.id.spec, puzzle.clues);
final hint = nextStep(board);
```

- `generateSudoku` never throws for a puzzle it could not make well. It settles for the closest
  attempt and sets `widened` on the result, because a child cannot act on "could not generate a
  puzzle". It does throw `ArgumentError` for 6x6 Expert, which has no tier and no ID.
- `Rng`, `fnv1a32`, `countSolutions` and `CandidateGrid` are not exported. Freezing a sequence is only
  meaningful if nothing outside the package can start a different one.
- Generation is synchronous and the package holds no mutable top-level state, so `compute()` is all
  the isolate wiring an app needs.

Median generation is 1 ms for a 9x9 Easy and 65 ms for a 9x9 Hard, with a tail into the hundreds of
milliseconds — `tool/benchmark.dart` prints the table and CI fails at three times the
[PLAN.md](../../PLAN.md) §3.5 target. See §3 there for the design, §7 for the phase order, and
[PLAN-phase-2.md](../../PLAN-phase-2.md) for why each piece is shaped the way it is.

## Commands

```sh
dart pub get
dart test                          # goldens and the fuzz at its default 200 puzzles
FUZZ_SEEDS=2000 dart test          # what CI and tool/verify.sh run
dart analyze --fatal-infos
dart run tool/benchmark.dart       # generation speed against PLAN.md §3.5
dart run tool/regen_goldens.dart   # only when generation is meant to change
```
