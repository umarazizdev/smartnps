#!/usr/bin/env bash
# FlutterGeneratedPluginSwiftPackage defaults to iOS 13.0; Firebase SPM needs 15.0+.
# Run after flutter pub get (which generates Package.swift) and before Xcode archive.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"
PACKAGES_DIR="$IOS_DIR/Flutter/ephemeral/Packages"
DEPLOYMENT_TARGET="${IOS_SWIFT_PACKAGE_DEPLOYMENT_TARGET:-15.0}"

patch_package_swift() {
  local manifest="$1"
  [[ -f "$manifest" ]] || return 0

  if [[ ! -w "$manifest" ]]; then
    echo "patch_swift_package_platform: warning: could not update $manifest" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  perl -0pe "
    s/\.iOS\\(\"\\d+\\.\\d+\"\\)/.iOS(\"${DEPLOYMENT_TARGET}\")/g;
  " "$manifest" > "$tmp"

  if ! cmp -s "$manifest" "$tmp"; then
    mv "$tmp" "$manifest"
    echo "patch_swift_package_platform: set iOS ${DEPLOYMENT_TARGET} in $(basename "$(dirname "$manifest")")/Package.swift"
  else
    rm "$tmp"
  fi
}

if [[ ! -d "$PACKAGES_DIR" ]]; then
  echo "patch_swift_package_platform: no Swift packages yet (run flutter pub get first)."
  exit 0
fi

while IFS= read -r -d '' manifest; do
  patch_package_swift "$manifest"
done < <(find "$PACKAGES_DIR" -name Package.swift -print0)

echo "patch_swift_package_platform: done (iOS >= ${DEPLOYMENT_TARGET})."
