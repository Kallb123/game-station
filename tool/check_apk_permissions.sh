#!/usr/bin/env bash
#
# Asserts that a built Android APK requests no platform permission:
#
#   tool/check_apk_permissions.sh app/build/app/outputs/flutter-apk/app-release.apk
#
# `tool/check_offline.dart` reads the manifest in the repository; this reads the
# package that actually gets installed, which is the evidence a parent can check
# for themselves. The two can disagree — a dependency's manifest is merged in at
# build time, and no source file in this repository mentions it — so the promise
# is checked on both sides of the build.
#
# One permission is expected and allowed:
# <applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION, which AndroidX Core
# declares so the app's own broadcast receivers are not exported. It is
# signature-level and scoped to this app, grants access to nothing outside it,
# and does not appear on a Play listing. Anything else — including any
# `android.permission.*` — fails, so a permission arriving with a future
# dependency has to be looked at rather than absorbed.
set -euo pipefail

apk=${1:-}
if [ -z "$apk" ]; then
  echo "usage: ${0##*/} <path-to-apk>" >&2
  exit 2
fi
if [ ! -r "$apk" ]; then
  echo "No readable APK at $apk" >&2
  exit 2
fi

# aapt2 ships per build-tools version rather than on PATH, so take the newest
# installed one. Sorted by version, not lexically: 34.0.0 sorts before 9.0.0
# without -V, which would silently pick an ancient build-tools.
aapt=$(command -v aapt2 || true)
if [ -z "$aapt" ]; then
  sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}
  if [ -n "$sdk" ] && [ -d "$sdk/build-tools" ]; then
    aapt=$(find "$sdk/build-tools" -name aapt2 -type f | sort -V | tail -1)
  fi
fi
if [ -z "$aapt" ]; then
  echo "aapt2 not found: put it on PATH, or set ANDROID_HOME to an SDK that has build-tools." >&2
  exit 2
fi

permissions=$("$aapt" dump permissions "$apk" |
  sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p")

echo "Permissions requested by $apk:"
if [ -z "$permissions" ]; then
  echo '  (none)'
else
  printf '  %s\n' $permissions
fi

unexpected=$(printf '%s\n' "$permissions" |
  grep -v '^$' |
  grep -v '\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION$' || true)
if [ -n "$unexpected" ]; then
  echo 'Unexpected permissions in the APK:' >&2
  printf '  %s\n' $unexpected >&2
  exit 1
fi

echo 'No platform permissions — in particular, no INTERNET.'
