#!/usr/bin/env bash
# Installs iOS pods with an up-to-date CocoaPods specs repo.
# Use this if plain `pod install` fails with Firebase/CoreOnly version errors.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"

cd "$IOS_DIR"
bash "$SCRIPT_DIR/apply_plugin_patches.sh"
bash "$SCRIPT_DIR/patch_swift_package_platform.sh"
pod install --repo-update "$@"
