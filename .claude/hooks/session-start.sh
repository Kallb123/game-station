#!/usr/bin/env bash
#
# Gets an agent session ready to work: the pinned Flutter SDK on PATH and both
# packages resolved, so `tool/verify.sh` runs from the first command instead of
# after a toolchain download — and a session that skips the download cannot
# verify what it changes.
#
# The SDK install itself is usually already done, by the environment setup
# script whose filesystem snapshot every container starts from; see
# tool/install_flutter.sh. This hook is what covers the container that starts
# before that snapshot exists, and it is where the per-branch work belongs,
# since a snapshot is shared by sessions on different branches.
#
# Runs only in Claude Code on the web. A local checkout has its own Flutter on
# PATH, and installing a second one under $HOME is not this hook's business.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

repo="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# A no-op, in about a second, when the snapshot already carries the SDK.
sdk=$("$repo/tool/install_flutter.sh")
export PATH="$sdk/bin:$PATH"

# Whatever this hook prints becomes context in the session that follows, so the
# chatter of a successful run is thrown away and only a failure speaks. Runs in
# <dir>: quietly <dir> <command>...
quietly() {
  local dir=$1 output
  shift
  if ! output=$(cd "$dir" && "$@" 2>&1); then
    printf '%s\n' "$output" >&2
    return 1
  fi
}

quietly "$repo/packages/puzzle_engine" dart pub get
quietly "$repo/app" flutter pub get

# Persist PATH for the session, so `flutter`, `dart` and `tool/verify.sh` work
# in every shell the agent opens.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$sdk/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

echo "Ready: Flutter ${sdk##*/}, dependencies resolved. Run tool/verify.sh before committing."
