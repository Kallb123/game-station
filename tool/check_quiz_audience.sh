#!/usr/bin/env bash
#
# Asserts which quiz packs a built Android APK carries:
#
#   tool/check_quiz_audience.sh app/build/app/outputs/flutter-apk/app-store-release.apk store
#   tool/check_quiz_audience.sh app/build/app/outputs/flutter-apk/app-private-release.apk private
#   tool/check_quiz_audience.sh --self-test
#
# The private packs name series that are someone else's trademarks, and the
# owner wants them for home use only (PLAN-phase-10-quiz.md §4.9). They are kept
# out of a store build by leaving them out of its asset bundle, not by hiding
# them at runtime, so the evidence that matters is the package itself: this
# lists what is inside the APK that would be handed out.
#
# - store:   fails if any entry is under assets/quiz/private/, and prints those.
# - private: fails if there is no assets/quiz/private/index.json. That proves the
#            flavour mechanism really bundled the private packs, so the store
#            check cannot pass merely because nothing is ever bundled.
#
# Both modes first require assets/quiz/store/index.json. Without it the listing
# is not of a Flutter APK that carries the quiz at all (an empty listing, the
# wrong file, a build that moved the assets), and a store check that finds no
# private entries in such a listing would pass vacuously.
#
# The entries come from `unzip -Z1`, the names-only form of the `unzip -l`
# listing the plan names; it needs no parsing of sizes and dates. The decision
# itself is a function that reads a listing on stdin, so --self-test feeds
# canned listings through exactly the code the real check runs. A guard that has
# never been seen to fail proves nothing (AGENTS.md).
#
# Exit status: 0 the check passed, 1 it failed, 2 a usage error or an APK that
# cannot be read.
set -euo pipefail

# Where the assets sit inside the package: an APK has them under
# assets/flutter_assets/, so these are matched as suffixes and substrings of
# that path rather than as whole names.
store_index='flutter_assets/assets/quiz/store/index.json'
private_dir='flutter_assets/assets/quiz/private/'
private_index='flutter_assets/assets/quiz/private/index.json'

# check_audience <store|private>, with the listing on stdin. Prints why on
# failure and returns 1; returns 0 when the listing is what the mode expects.
check_audience() {
  local mode=$1 listing
  listing=$(cat)

  # Here-strings rather than `printf | grep -q`: grep -q exits at its first
  # match, and on a real APK's thousands of entries the printf behind it can die
  # of SIGPIPE, which pipefail turns into "not found" — an intermittent failure
  # on a healthy package. The long-listing self-test case below pins this.
  if ! grep -q -- "${store_index}\$" <<< "$listing"; then
    echo "No entry ending in $store_index: this is not a Flutter APK carrying the quiz." >&2
    return 1
  fi

  case "$mode" in
    store)
      local found
      found=$(grep -F -- "$private_dir" <<< "$listing" || true)
      if [ -n "$found" ]; then
        echo 'Private quiz packs in a build that must not carry them:' >&2
        printf '  %s\n' "$found" >&2
        return 1
      fi
      ;;
    private)
      if ! grep -q -- "${private_index}\$" <<< "$listing"; then
        echo "No entry ending in $private_index: the private packs were not bundled." >&2
        return 1
      fi
      ;;
    *)
      echo "Unknown mode: $mode" >&2
      return 2
      ;;
  esac
}

self_test() {
  local store_listing private_listing no_quiz_listing empty_listing long_listing
  local failures=0

  store_listing='AndroidManifest.xml
classes.dex
assets/flutter_assets/AssetManifest.bin
assets/flutter_assets/assets/quiz/store/index.json
assets/flutter_assets/assets/quiz/store/animals.json'

  private_listing='AndroidManifest.xml
classes.dex
assets/flutter_assets/AssetManifest.bin
assets/flutter_assets/assets/quiz/store/index.json
assets/flutter_assets/assets/quiz/private/index.json
assets/flutter_assets/assets/quiz/private/faraway-tree.json'

  no_quiz_listing='AndroidManifest.xml
classes.dex
assets/flutter_assets/AssetManifest.bin'

  empty_listing=''

  # A real APK lists thousands of entries. The index files come first here and
  # a long tail follows, so a check that stops reading at its first match while
  # something is still writing the listing to it is caught.
  long_listing="$private_listing
$(seq -f 'assets/flutter_assets/padding/%g.bin' 1 20000)"

  # expect <case name> <mode> <listing> <pass|fail>. The decision runs in a
  # subshell because a failure inside it must not end the self-test.
  expect() {
    local name=$1 mode=$2 listing=$3 want=$4 got
    if (printf '%s' "$listing" | check_audience "$mode") > /dev/null 2>&1; then
      got=pass
    else
      got=fail
    fi
    if [ "$got" = "$want" ]; then
      echo "ok   $name, $mode mode: $got"
    else
      echo "FAIL $name, $mode mode: wanted $want, got $got" >&2
      failures=$((failures + 1))
    fi
  }

  expect 'store listing'   store   "$store_listing"   pass
  expect 'store listing'   private "$store_listing"   fail
  expect 'private listing' private "$private_listing" pass
  expect 'private listing' store   "$private_listing" fail
  expect 'no quiz assets'  store   "$no_quiz_listing" fail
  expect 'no quiz assets'  private "$no_quiz_listing" fail
  expect 'empty listing'   store   "$empty_listing"   fail
  expect 'empty listing'   private "$empty_listing"   fail
  expect 'long listing'    private "$long_listing"    pass
  expect 'long listing'    store   "$long_listing"    fail

  if [ "$failures" -ne 0 ]; then
    echo "$failures self-test case(s) failed." >&2
    return 1
  fi
  echo 'Self-test passed.'
}

if [ "${1:-}" = '--self-test' ]; then
  self_test
  exit
fi

apk=${1:-}
mode=${2:-}
if [ -z "$apk" ] || { [ "$mode" != store ] && [ "$mode" != private ]; }; then
  echo "usage: ${0##*/} <path-to-apk> store|private" >&2
  echo "       ${0##*/} --self-test" >&2
  exit 2
fi
if [ ! -r "$apk" ]; then
  echo "No readable APK at $apk" >&2
  exit 2
fi

# Listed into a variable first so that an unzip failure (a truncated or
# non-zip file) stops the script here. In a pipeline it would be hidden behind
# the check's exit status, and an empty listing could then be mistaken for one.
if ! listing=$(unzip -Z1 "$apk"); then
  echo "Could not list the entries of $apk" >&2
  exit 2
fi

if printf '%s\n' "$listing" | check_audience "$mode"; then
  echo "$apk is a $mode build as far as quiz packs go."
else
  exit 1
fi
