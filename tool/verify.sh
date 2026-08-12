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

step 'Testing puzzle_engine'
(cd packages/puzzle_engine && dart test)

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
