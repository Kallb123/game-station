#!/usr/bin/env bash
#
# Prints the --dart-define flags that stamp a build with its version and the
# time it was compiled, which the settings screen's footer shows
# (app/lib/core/build_info.dart). Use it on any build a person will run:
#
#   cd app && flutter build apk --release $(../tool/build_defines.sh)
#
# Unquoted on purpose: the output is two flags and neither value contains a
# space, so word splitting is what turns one string into two arguments.
#
# The version is read from app/pubspec.yaml rather than passed in, so the number
# in the footer, the number in the APK's file name and the number a store sees
# are the same one. A build that skips this script is not stamped at all and
# says "Development build" — the deliberate alternative to reporting a version
# that might be stale.
set -euo pipefail

cd "$(dirname "$0")/.."

version=$(sed -n 's/^version: *//p' app/pubspec.yaml | head -1)
if [ -z "$version" ]; then
  echo 'Could not read version from app/pubspec.yaml' >&2
  exit 1
fi

# Seconds, in UTC, with the Z: DateTime.tryParse in build_info.dart wants an
# ISO-8601 instant, and a local time would read differently on the device than
# on the machine that built it.
printf -- '--dart-define=APP_VERSION=%s --dart-define=BUILD_TIME=%s\n' \
  "$version" "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
