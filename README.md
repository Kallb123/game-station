# Game Station

A local, offline, ad-free games app for kids. Android, iOS, Windows, macOS, and Linux from one
codebase.

**Status:** planning. No code yet — see [PLAN.md](PLAN.md) for the implementation plan.

## What it is

- **Sudoku** — 9x9 and 6x6, four difficulty tiers, puzzles generated deterministically from a date
  or an index, so the same puzzle appears on every device with nothing stored and nothing fetched.
- **Retro arcade** — Space Invaders first, driven by large on-screen left/right/fire buttons (plus
  keyboard on desktop). More simple games later.
- **Progress that sticks** — solved puzzles, best times, daily streaks and high scores persist
  across sessions, per local profile.

## Principles

| | |
|---|---|
| No ads | No ad SDK in the dependency tree. |
| No network | Android ships without the `INTERNET` permission, so the OS itself enforces it. |
| No tracking | No analytics, no crash reporting, no telemetry. Nothing leaves the device. |
| No purchases | No IAP, no timers, no gated content. |
| Kid-first UI | Big touch targets, minimal reading, no pressure, no scary failure states. |

## Planned stack

Flutter + [Flame](https://flamengine.org) (Dart) for all six targets, with a pure-Dart
`puzzle_engine` package for Sudoku generation and solving, and progress saved to an atomically
written local JSON file.

See [PLAN.md](PLAN.md) for the reasoning, alternatives considered, phase breakdown, and risks.

## Repository tooling

`.claude/` is committed so the tooling travels with the repo:

Vendored from [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) (MIT) — provenance
and licence in [`.claude/skills/NOTICE.md`](.claude/skills/NOTICE.md):

| Skill | Use |
|---|---|
| `/caveman` | Terse replies, at `lite`/`full`/`ultra` intensity |
| `/caveman-compress <file>` | Compress a Markdown file to caveman register |
| `/caveman-review` | One-line-per-finding code review |

Written for this repo:

| | Use |
|---|---|
| `/caveman-plan` | Write an implementation plan: constraints, alternatives rejected, phases with done-criteria, risks, checklist |
| `agents/caveman.md` | Documentation-compression subagent, with a review mode |

Both local additions default to `lite` intensity, which keeps ordinary prose. Documents that live in
the repo are written in normal English, not caveman-speak — which is what the upstream skill's own
"Boundaries" section calls for.
