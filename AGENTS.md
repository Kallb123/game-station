# Working practices

For anyone — human or agent — making changes in this repository.

## What this project is

A local, offline, ad-free games app for children: Sudoku plus retro arcade games, Flutter and Flame
on six platforms. [`PLAN.md`](PLAN.md) is the design document and the source of truth for scope,
phases and their done-criteria. [`README.md`](README.md) covers layout and commands.

## The workflow

**1. Plan before building anything non-trivial.** Run `/caveman-plan` and write the plan to a
repository file: `PLAN.md` for the project plan, `PLAN-<feature>.md` for a feature that needs its
own. A plan states scope and constraints with reasons, non-goals, the approach with rejected
alternatives, phases each ending in an observable `**Done when:**`, risks with falsifiable
mitigations, and a verification checklist. Skip the planning step only for a change small enough to
describe in one sentence.

For work already covered by `PLAN.md`, follow the phase rather than re-planning it. If the work turns
out to differ from the plan, update the plan in the same change — a plan that no longer matches the
code is worse than none, because it is still believed.

**2. Build the phase, not the project.** Phases exist so that each one is finishable and reviewable.
Do not pull work forward from a later phase: adding a dependency three phases early means carrying it
through every intervening review. Do not leave a phase half-done either; if part of it is blocked,
finish everything else and say plainly what was left and why.

**3. Verify before committing.** `tool/verify.sh` runs everything CI runs, in the same order:

```sh
tool/verify.sh
```

A change is not done because it compiles. It is done when the checks pass and, for anything with
visible behaviour, when it has been run. Report what was actually verified and what was not — "CI
will tell us" is a gap to state, not to hide.

**4. Review after completing work.** Run `/caveman-review` on the diff before opening or updating a
pull request, and fix what it finds. Findings come one line each: location, problem, fix. Review your
own work as if someone else wrote it; the useful findings are the ones that are embarrassing to
report.

**5. Then commit and open the PR.** Describe why, not what — the diff shows what. Explain any
decision a reader would otherwise have to re-derive, and any tradeoff taken deliberately.

## Rules specific to this project

**The constraints are not stylistic.** No network, no ads, no tracking, no purchases. They are the
reason the app exists, and they are enforced by `tool/check_offline.dart` rather than by good
intentions. If it fails, fix the code — do not narrow the check to fit the code, and never skip it.
Adding a dependency means checking what it drags in: a package that reaches the network fails the
build even when nothing calls it.

**Prefer a mechanism over a promise.** Whenever a rule can be enforced by the build, the platform or
CI, enforce it there. Android omits the `INTERNET` permission so the OS blocks network access; the
golden puzzle tests fail if generation output drifts. A constraint that only lives in a document is
already broken, it just does not know it yet.

**A guard needs its own test.** `check_offline.dart --self-test` exists because a scanner bug made the
check pass while reporting nothing. Anything whose failure mode is "silently stops working" gets a
test that fails when it does — and check that the test fails against the broken version, not only that
it passes against the fixed one.

**Puzzle determinism is load-bearing.** Saved progress stores puzzle IDs, not grids, so identical
input must produce identical output forever. Nothing in the engine may use `dart:math`'s `Random`,
iterate a `Set` or `Map` for anything order-dependent, or read a clock. Changing generation output
means bumping `generatorVersion`, regenerating goldens, keeping the old generator reachable and
writing a save migration — all in the same commit. The pinned Flutter version moves in its own commit
for the same reason.

**`packages/puzzle_engine` stays pure Dart.** No Flutter, no `dart:io`, no `dart:ui`. Its speed is
what makes thousands of fuzz seeds affordable.

**The audience is a child.** Large touch targets, minimal reading, no time pressure, no scary failure
states. Never surface an internal error to the player: on a corrupt save, start fresh and say so
once; on a generation failure, widen the difficulty and log it. A boot loop is worse than a lost high
score.

## Writing

Documents in this repository are written in plain professional English — no filler, no hedging, and
no caveman-speak, which is a defect in a committed file. `/caveman` and `/caveman-review` change how
*replies and review comments* read, not how documents in the repository read.

Comments earn their place by explaining why, or by recording a decision or a trap that the code
cannot state itself. A comment restating the line below it is noise.
