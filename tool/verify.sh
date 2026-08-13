#!/usr/bin/env bash
#
# Everything CI runs, in the same order, so a red build is reproducible locally.
# Run from anywhere in the repository:
#
#   tool/verify.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step 'Resolving dependencies'
(cd packages/puzzle_engine && dart pub get)
(cd app && flutter pub get)

step 'Checking formatting'
dart format --output=none --set-exit-if-changed .

step 'Analyzing puzzle_engine'
(cd packages/puzzle_engine && dart analyze --fatal-infos --fatal-warnings)

step 'Analyzing app'
(cd app && flutter analyze)

step 'Analyzing tool scripts'
dart analyze --fatal-infos --fatal-warnings tool

# FUZZ_SEEDS is how many puzzles test/fuzz_test.dart generates, across every
# size and difficulty. It defaults to 200 so a bare `dart test` stays usable
# while iterating; this and CI both set 2000, so the check that blocks a merge
# and the check people run here are the same one rather than two that drift.
# It is most of this script's runtime — see AGENTS.md's table.
step 'Testing puzzle_engine'
(cd packages/puzzle_engine && FUZZ_SEEDS=2000 dart test)

# The PRNG and the hash mask every operation to 32 bits so that a JavaScript
# number, which is exact only to 53 bits, produces the same puzzles as a 64-bit
# VM. Running those two files in a browser is the only thing that checks it.
#
# CI always runs this. Locally it needs a Chrome, which not every machine has,
# so a missing browser is reported and skipped rather than failing the run —
# the one place this script is knowingly a subset of CI.
step 'Testing the engine on the web platform'
chrome="${CHROME_EXECUTABLE:-$(command -v google-chrome || command -v chromium || command -v chromium-browser || true)}"
if [ -n "$chrome" ]; then
  (cd packages/puzzle_engine &&
    CHROME_EXECUTABLE="$chrome" dart test -p chrome test/rng_test.dart test/hash_test.dart)
else
  printf 'skipped: no Chrome found. CI runs this step; set CHROME_EXECUTABLE to run it here.\n'
fi

step 'Testing app'
(cd app && flutter test)

step 'Testing the offline check'
dart tool/check_offline.dart --self-test

step 'Checking the offline, no-ads, no-tracking constraints'
dart tool/check_offline.dart

step 'Testing the determinism check'
dart tool/check_determinism.dart --self-test

step 'Checking the engine determinism rules'
dart tool/check_determinism.dart

printf '\n\033[32mAll checks passed.\033[0m\n'
