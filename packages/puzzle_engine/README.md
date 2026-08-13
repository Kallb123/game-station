# puzzle_engine

Deterministic Sudoku generation and solving for [Game Station](../../README.md).

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

Phase 0 scaffold: the package, its lints and its test harness exist; the engine itself lands in
phase 2. See [PLAN.md](../../PLAN.md) §3 for the design and §7 for the phase order.

## Commands

```sh
dart pub get
dart test                          # goldens and the fuzz at its default 200 puzzles
FUZZ_SEEDS=2000 dart test          # what CI and tool/verify.sh run
dart analyze --fatal-infos
dart run tool/regen_goldens.dart   # only when generation is meant to change
```
