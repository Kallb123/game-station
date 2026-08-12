#!/usr/bin/env bash
#
# Installs the pinned Flutter SDK under $HOME/flutter-sdk/<version> and warms
# its tool cache. Idempotent, quiet, and prints the SDK path on stdout so a
# caller can put it on PATH:
#
#   sdk=$(tool/install_flutter.sh)
#   export PATH="$sdk/bin:$PATH"
#
# Two callers, for two different caches:
#
#   - The setup script of the Claude Code on the web environment. Its filesystem
#     is snapshotted once and reused by every later container, so the download
#     is paid per environment rather than per session. Run it from anywhere:
#
#       curl -fsSL "$RAW/tool/install_flutter.sh" | bash
#
#   - .claude/hooks/session-start.sh, which covers the containers that start
#     before that snapshot exists, or after it expires.
set -euo pipefail

raw=https://raw.githubusercontent.com/Kallb123/game-station/main

# One pinned version for the whole project, read from the CI workflow rather
# than copied here: a second copy is a second thing to forget when the pin
# moves, and the generator's output has to stay byte-identical across
# toolchains. Piped from the network there is no checkout to read, so the
# workflow is fetched instead — still the same one file.
# ${BASH_SOURCE[0]} is unset when this arrives on stdin, which is exactly the
# case that has no checkout to read.
self=${BASH_SOURCE[0]:-}
workflow=""
if [ -n "$self" ]; then
  workflow="$(cd "$(dirname "$self")/.." && pwd)/.github/workflows/ci.yml"
fi
if [ -n "$workflow" ] && [ -r "$workflow" ]; then
  pin=$(cat "$workflow")
else
  pin=$(curl -fsSL --retry 3 --retry-delay 2 "$raw/.github/workflows/ci.yml")
fi

version=$(printf '%s\n' "$pin" | sed -n 's/^ *FLUTTER_VERSION: *//p' | head -1)
if [ -z "$version" ]; then
  echo "Could not read FLUTTER_VERSION from .github/workflows/ci.yml" >&2
  exit 1
fi

# Versioned path, so moving the pin installs alongside the old SDK rather than
# over the top of it, and a stale snapshot is a slow session rather than a
# wrong toolchain.
sdk="$HOME/flutter-sdk/$version"

# Progress goes to stderr; stdout is the SDK path and nothing else.
if [ ! -x "$sdk/bin/flutter" ]; then
  echo "Installing Flutter $version into $sdk" >&2
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$version-stable.tar.xz"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/flutter.tar.xz" "$url"
  tar -xJf "$tmp/flutter.tar.xz" -C "$tmp"
  # Land it in one move: the check above treats bin/flutter as proof of a
  # complete install, so a half-extracted directory must never sit at the
  # real path.
  mkdir -p "$(dirname "$sdk")"
  rm -rf "$sdk.partial"
  mv "$tmp/flutter" "$sdk.partial"
  mv "$sdk.partial" "$sdk"
fi

export PATH="$sdk/bin:$PATH"

# Flutter shells out to git inside its own clone on nearly every command.
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$sdk"; then
  git config --global --add safe.directory "$sdk"
fi

# Nothing in this project reports anything anywhere, tooling included.
flutter config --no-analytics >/dev/null 2>&1 || true
dart --disable-analytics >/dev/null 2>&1 || true

# Unpacks the bundled Dart SDK and the tool snapshot, which is otherwise paid
# for by whichever command runs first — and paid in the session rather than in
# the snapshot.
if ! warmup=$(flutter --version 2>&1); then
  printf '%s\n' "$warmup" >&2
  exit 1
fi

printf '%s\n' "$sdk"
