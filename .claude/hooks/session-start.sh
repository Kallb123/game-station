#!/usr/bin/env bash
#
# Installs the toolchain an agent session needs before it starts working:
# the pinned Flutter SDK and the resolved dependencies of both packages.
#
# Without this, every session spends its first minutes downloading Flutter
# before it can run `tool/verify.sh` — and a session that skips the download
# cannot verify anything it changes.
#
# Runs only in Claude Code on the web. A local checkout already has a Flutter
# on PATH, and silently installing a second one under $HOME is not this
# script's business.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

repo="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# One pinned version for the whole project, read from the workflow rather than
# copied here: a second copy is a second thing to forget when the pin moves,
# and the generator's output has to stay byte-identical across toolchains.
version=$(sed -n 's/^ *FLUTTER_VERSION: *//p' "$repo/.github/workflows/ci.yml" | head -1)
if [ -z "$version" ]; then
  echo "Could not read FLUTTER_VERSION from .github/workflows/ci.yml" >&2
  exit 1
fi

# Versioned path, so moving the pin installs alongside rather than over the top
# and a half-extracted directory from an interrupted run is never mistaken for
# a complete one.
sdk_root="$HOME/flutter-sdk"
sdk="$sdk_root/$version"
export PATH="$sdk/bin:$PATH"

if [ ! -x "$sdk/bin/flutter" ]; then
  echo "Installing Flutter $version into $sdk"
  url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_$version-stable.tar.xz"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp/flutter.tar.xz" "$url"
  mkdir -p "$sdk_root"
  # Extract to a scratch directory first: the check above treats the presence
  # of bin/flutter as "installed", so a partial extraction must never land at
  # the real path.
  tar -xJf "$tmp/flutter.tar.xz" -C "$tmp"
  rm -rf "$sdk.partial"
  mv "$tmp/flutter" "$sdk.partial"
  mv "$sdk.partial" "$sdk"
fi

# The SDK is a git clone, and Flutter shells out to git on nearly every command.
if ! git config --global --get-all safe.directory 2>/dev/null | grep -qx "$sdk"; then
  git config --global --add safe.directory "$sdk"
fi

# Nothing in this project reports anything anywhere, tooling included.
flutter config --no-analytics >/dev/null 2>&1 || true
dart --disable-analytics >/dev/null 2>&1 || true

# Whatever this hook prints becomes context in the session that follows, so the
# chatter of a successful run is thrown away and only a failure speaks. Run in
# <dir>: quietly <dir> <command>...
quietly() {
  local dir=$1 output
  shift
  if ! output=$(cd "$dir" && "$@" 2>&1); then
    printf '%s\n' "$output" >&2
    return 1
  fi
}

# First run unpacks the bundled Dart SDK and the framework caches, which is
# otherwise paid for by whichever command the agent runs first.
quietly "$repo" flutter --version

quietly "$repo/packages/puzzle_engine" dart pub get
quietly "$repo/app" flutter pub get

# Persist PATH for the session, so `flutter`, `dart` and `tool/verify.sh` work
# in every shell the agent opens.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$sdk/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

echo "Ready: Flutter $version, dependencies resolved. Run tool/verify.sh before committing."
