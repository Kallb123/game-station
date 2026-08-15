#!/usr/bin/env bash
#
# Prints the path to an Android SDK build-tools executable, so callers can use
# one without knowing where the SDK put it:
#
#   aapt=$(tool/android_sdk_tool.sh aapt2)
#
# build-tools executables ship inside a per-version directory rather than on
# PATH, so this takes the newest installed one. Sorted by version rather than
# lexically: 34.0.0 sorts before 9.0.0 without -V, which would silently pick an
# ancient build-tools.
#
# Shared by check_apk_permissions.sh and apk_signing_cert.sh. It is one lookup
# with one set of failure messages because two copies would drift, and a script
# that cannot find its tool is the first thing anyone hits on a new machine.
set -euo pipefail

name=${1:-}
if [ -z "$name" ]; then
  echo "usage: ${0##*/} <build-tools-executable>" >&2
  exit 2
fi

# Already on PATH — some distributions and CI images install it there.
found=$(command -v "$name" || true)

if [ -z "$found" ]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
    found=$(find "$sdk/build-tools" -name "$name" -type f | sort -V | tail -1)
  fi
fi

if [ -z "$found" ]; then
  echo "$name not found: put it on PATH, or set ANDROID_HOME to an SDK that has build-tools." >&2
  exit 2
fi

echo "$found"
