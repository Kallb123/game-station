# Game Station

A local, offline, ad-free games app for kids. Android, iOS, Windows, macOS, and Linux from one
codebase.

**Status:** phase 0 done — app and engine packages scaffolded, strict lints, CI, and the offline
constraints enforced by a build check. No games yet. See [PLAN.md](PLAN.md) §7 for the phase order.

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

## Layout

```
app/                    # the Flutter application (UI, storage, audio, arcade games)
packages/puzzle_engine/ # pure-Dart Sudoku generation and solving
tool/check_offline.dart # enforces no network, no ads, no tracking
tool/verify.sh          # everything CI runs, in the same order
tool/install_flutter.sh # installs the pinned SDK, for cloud sessions
```

Two packages joined by a plain path dependency — no melos; see [PLAN.md](PLAN.md) §6.

## Working on it

Working practices — plan first, verify with `tool/verify.sh`, review before opening a PR — are in
[AGENTS.md](AGENTS.md).

Flutter **3.44.9** (Dart 3.12.2), pinned in [`.github/workflows/ci.yml`](.github/workflows/ci.yml).
The toolchain version moves deliberately, in its own commit, because the puzzle generator's output
has to stay byte-identical across releases.

```sh
tool/verify.sh                 # format, analyze, test, offline check — both packages
cd app && flutter run -d linux # or macos, windows, or a connected device
```

Desktop Linux builds need `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`.

## How the constraints are enforced

The promises above are checked by `tool/check_offline.dart` on every CI run, so breaking one fails
the build rather than surviving to a release:

| Check | Failure |
|---|---|
| Networking APIs, network imports or URLs in shipped Dart | `HttpClient`, `Socket`, `dart:html`, an `https://` string literal. URLs in comments are fine — comments cannot open sockets. |
| Ad, analytics and HTTP packages | In a declared dependency, or anywhere in the runtime dependency graph. Test-only tooling may contain an HTTP client, since it never ships. |
| Android release manifest | Requests `INTERNET`. CI also asserts the built release APK requests no platform permission — the only one present is the signature-level `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` that AndroidX grants the app over itself. |
| macOS release entitlements | Grant a network entitlement. |
| `puzzle_engine` purity | Imports Flutter, `dart:io`, `dart:ui` or `dart:isolate`. |

Code is MIT ([`LICENSE`](LICENSE)). Assets are licensed per file, with rules and an inventory in
[`app/assets/LICENSE-ASSETS.md`](app/assets/LICENSE-ASSETS.md).

## Repository tooling

`.claude/` is committed so the tooling travels with the repo.

### The toolchain in cloud sessions

An agent that has to download Flutter before it can run `tool/verify.sh` spends its first minutes on
a toolchain rather than the work, so the SDK is installed ahead of the session, in two layers:

- [`tool/install_flutter.sh`](tool/install_flutter.sh) installs the pinned SDK under
  `$HOME/flutter-sdk/<version>` and warms its tool cache — about 90 seconds cold, a second warm. It
  reads the version from the CI workflow, so the pin keeps one home.
- [`.claude/hooks/session-start.sh`](.claude/hooks/session-start.sh) runs it as a `SessionStart`
  hook, then resolves both packages and puts `flutter` on `PATH`. It does nothing outside Claude
  Code on the web, where `CLAUDE_CODE_REMOTE` is set.

The hook alone would pay the install once per container. Paste this into the **Setup script** field
of the cloud environment as well, and it is paid once per environment instead: Anthropic snapshots
the filesystem after a setup script runs and starts later containers from that snapshot, which a
`SessionStart` hook — running after Claude Code launches — is too late to be part of.

```sh
# Flutter 3.44.9
curl -fsSL https://raw.githubusercontent.com/Kallb123/game-station/main/tool/install_flutter.sh | bash || true
```

Two details are load-bearing. The version in the comment is what rebuilds the snapshot when the pin
moves: the script re-runs when its own text changes, when the environment's allowed hosts change, and
when the snapshot expires after about a week. And `|| true` keeps a failed download from failing the
session outright — the hook retries it, in the session, where an agent can see what went wrong.

Skills vendored from [JuliusBrussee/caveman](https://github.com/JuliusBrussee/caveman) (MIT) —
provenance and licence in [`.claude/skills/NOTICE.md`](.claude/skills/NOTICE.md):

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
