# Zibo Games

A local, offline, ad-free games app for kids. Android, iOS, Windows, macOS, and Linux from one
codebase.

**Status:** phases 1 and 2 done. The app shell runs: home screen, local profiles, settings,
day/night/system theme, and progress saved to an atomically written JSON file that survives a
force-quit and recovers from a corrupt one. The Sudoku engine is finished behind it — 9x9 and 6x6
generated deterministically from an ID, four difficulty tiers judged by technique, hints, and 700
golden puzzles that turn CI red if any of it drifts.

Still no games to play: nothing in the app imports the engine yet, so the Sudoku and Arcade cards open
"coming soon" screens. Next is phase 3, which draws the grid and wires generation into an isolate.
Checked by hand on Android; the other four targets build in CI but have not been run on a device. See
[PLAN.md](PLAN.md) §7 for the phase order.

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
tool/check_determinism.dart # enforces the engine's no-clock, no-dart:math rules
tool/verify.sh          # everything CI runs, in the same order
tool/install_flutter.sh # installs the pinned SDK, for cloud sessions
tool/check_apk_permissions.sh # asserts a built APK requests no permissions
tool/icon/              # resamples the icon master into every platform's launcher sizes
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

### Getting an APK onto a phone

The **Android APK** workflow builds the release APK and uploads it, so a device can be handed a
build without a store account or a local Flutter install. Run it from the Actions tab on any branch,
or take the artifact from the CI run of any pull request — CI calls the same workflow rather than
building its own, so the two are the same package. Download it from the run's **Artifacts** section
and `adb install -r game-station-<version>-<commit>.apk`, or copy it to the device and open it.

Publishing a GitHub release builds the APK from that release's tag and attaches it to the release
page, where it needs no login and does not expire — the **Android release APK** workflow, which can
also be re-run by hand from a tag if an upload failed.

Every build asserts that the package requests no platform permission
([`tool/check_apk_permissions.sh`](tool/check_apk_permissions.sh)) before it is uploaded, so an APK
that reached a phone was checked on the way.

Locally, `cd app && flutter build apk --release` produces the same thing at
`app/build/app/outputs/flutter-apk/app-release.apk`.

### The signing key

Android identifies an app by its package name and its signing certificate together, and refuses to
install an update signed by a different certificate. Flutter's debug key is generated per machine, so
while the workflow used it, every run signed with a key nobody had seen before: a new build would not
install over the last one, and the only way through was to uninstall — which throws the saved puzzles
away with it.

Set four repository secrets (Settings → Secrets and variables → Actions) and every build is signed
with one key instead, so each is an update of the one before:

| Secret | What it is |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The keystore file, base64-encoded. |
| `ANDROID_KEYSTORE_PASSWORD` | Password for the keystore. |
| `ANDROID_KEY_ALIAS` | Alias of the key inside it. |
| `ANDROID_KEY_PASSWORD` | Password for that key — often the same as the keystore's. |

To create one, and print the value to paste into the first secret:

```sh
keytool -genkeypair -v -keystore upload-keystore.jks -storetype JKS \
  -keyalg RSA -keysize 2048 -validity 10000 -alias upload
base64 -w0 upload-keystore.jks     # macOS: base64 -i upload-keystore.jks
```

**Keep the keystore and its passwords backed up somewhere outside this repository.** Losing them
means no future build can update an installed app — the store release in Phase 6 has the same
property, permanently, so treat this key as the one the app will keep.

With no secrets set the build falls back to the debug key rather than failing, so a fork still
produces an installable APK. Setting some but not all of the four is a hard failure instead of a
fallback: it would otherwise sign with the debug key and look exactly like success, which is the bug
this fixes. Every run prints which key it used and the certificate's SHA-256 fingerprint in its
summary ([`tool/apk_signing_cert.sh`](tool/apk_signing_cert.sh)) — two builds install over each other
when those fingerprints match.

Android still warns about an unknown source, and this is not yet a store release; that is the rest of
Phase 6. To build a signed APK locally, put the same values in `app/android/key.properties`, which is
gitignored:

```properties
storeFile=upload-keystore.jks
storePassword=...
keyAlias=upload
keyPassword=...
```

`storeFile` is resolved relative to `app/android/`. Without that file, a local release build uses the
debug key exactly as before.

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

Puzzle determinism is enforced the same way, by two checks rather than by care. A save file stores
puzzle IDs and not grids, so a generator that read a clock or drew from `dart:math` would turn a
solved puzzle into a different unsolved one on someone else's device, months later.
[`tool/check_determinism.dart`](tool/check_determinism.dart) catches the cause — a clock, `Random`, or
iterating a `Set` or `Map` in the engine's `lib/` — and the golden puzzle files catch the effect, by
holding 700 generated puzzles that CI compares against on every run. The scanner has its own
self-test, because a scanner that silently stops scanning looks exactly like one that found nothing;
the goldens were checked the other way round, by breaking a PRNG constant and watching them go red.

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
