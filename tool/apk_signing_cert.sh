#!/usr/bin/env bash
#
# Prints the certificate an APK is signed with:
#
#   tool/apk_signing_cert.sh app/build/app/outputs/flutter-apk/app-release.apk
#
# Android identifies an app by its package name and its signing certificate
# together, and refuses to install an update signed by a different one — the
# install fails with INSTALL_FAILED_UPDATE_INCOMPATIBLE and the only way through
# is to uninstall, which takes the saved puzzles with it. Two builds are
# therefore interchangeable on a device only if this fingerprint matches.
#
# The workflow prints it into the run summary so the answer to "why will this
# build not install over the last one" is on the page rather than something to
# work out from a device log. It is informational: it reports what signed the
# package and does not decide whether that was the right key.
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

apksigner=$("$(dirname "$0")/android_sdk_tool.sh" apksigner)

# --print-certs reports every signer and every signature scheme version. Its
# output is quoted rather than parsed down to one line: the subject says which
# key it was (Flutter's debug key self-identifies as "Android Debug"), and the
# scheme versions say whether the package will verify on modern Android.
"$apksigner" verify --print-certs --verbose "$apk"
