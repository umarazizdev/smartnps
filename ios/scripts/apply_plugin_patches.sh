#!/usr/bin/env bash
# Applies production-ready iOS patches to Flutter plugin sources.
# Run automatically from the Podfile before `pod install`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IOS_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_DIR="$(dirname "$IOS_DIR")"
PLUGINS_DIR="$IOS_DIR/.symlinks/plugins"
PATCHES_DIR="$IOS_DIR/plugin_patches"
DEPLOYMENT_TARGET="15.0"

if [[ ! -d "$PLUGINS_DIR" ]]; then
  echo "apply_plugin_patches: no plugin symlinks found, skipping."
  exit 0
fi

copy_patch_tree() {
  local plugin="$1"
  local patch_root="$PATCHES_DIR/$plugin"
  [[ -d "$patch_root" ]] || return 0

  while IFS= read -r -d '' patch_file; do
    local rel="${patch_file#"$patch_root"/}"
    local target="$PLUGINS_DIR/$plugin/$rel"
    if [[ -f "$target" ]]; then
      if [[ ! -w "$target" ]]; then
        echo "apply_plugin_patches: warning: could not patch $plugin/$rel" >&2
        continue
      fi

      if cp "$patch_file" "$target"; then
        echo "apply_plugin_patches: patched $plugin/$rel"
      else
        echo "apply_plugin_patches: warning: could not patch $plugin/$rel" >&2
      fi
    fi
  done < <(find "$patch_root" -type f -print0)
}

patch_file_in_place() {
  local file="$1"
  shift
  [[ -f "$file" ]] || return 0
  if [[ ! -w "$file" ]]; then
    echo "apply_plugin_patches: warning: could not update $file" >&2
    return 0
  fi

  local tmp
  tmp="$(mktemp)"
  cp "$file" "$tmp"
  if "$@" "$tmp"; then
    if ! cmp -s "$file" "$tmp"; then
      if mv "$tmp" "$file"; then
        echo "apply_plugin_patches: updated $(basename "$file")"
      else
        rm "$tmp"
        echo "apply_plugin_patches: warning: could not update $file" >&2
      fi
    else
      rm "$tmp"
    fi
  else
    rm "$tmp"
    return 1
  fi
}

patch_flutter_inappwebview_ios() {
  local root="$PLUGINS_DIR/flutter_inappwebview_ios/ios/Classes"
  [[ -d "$root" ]] || return 0

  local inapp_webview="$root/InAppWebView/InAppWebView.swift"
  patch_file_in_place "$inapp_webview" perl -0pi -e '
    s/\n\s*configuration\.preferences\.javaScriptEnabled = [^\n]+//g;
    s/configuration\.preferences\.javaScriptEnabled/configuration.defaultWebpagePreferences.allowsContentJavaScript/g;
    s/\n\s*configuration\.processPool = WKProcessPoolManager\.sharedProcessPool//g;
  '

  local settings="$root/InAppWebView/InAppWebViewSettings.swift"
  patch_file_in_place "$settings" perl -0pi -e '
    s/\n\s*realSettings\["javaScriptEnabled"\] = configuration\.preferences\.javaScriptEnabled//g;
  '

  local util="$root/Util.swift"
  patch_file_in_place "$util" perl -0pi -e '
    s/case "SPOTLIGHT_SUGGESTION":\n\s*return \.spotlightSuggestion/case "SPOTLIGHT_SUGGESTION":\n                return .lookupSuggestion/g;
    s/if type\.contains\(\.spotlightSuggestion\) \{\n\s*dataDetectorTypeString\.append\("SPOTLIGHT_SUGGESTION"\)\n\s*\}//g;
  '

  local browser_manager="$root/InAppBrowser/InAppBrowserManager.swift"
  patch_file_in_place "$browser_manager" perl -0pi -e '
    s/if previousStatusBarStyle == -1 \{\n\s*previousStatusBarStyle = UIApplication\.shared\.statusBarStyle\.rawValue\n\s*\}\n\s*//s;
  '

  local browser_vc="$root/InAppBrowser/InAppBrowserWebViewController.swift"
  patch_file_in_place "$browser_vc" perl -0pi -e '
    s/if previousStatusBarStyle != -1, let statusBarStyle = UIStatusBarStyle\(rawValue: previousStatusBarStyle\) \{\n\s*UIApplication\.shared\.statusBarStyle = statusBarStyle\n\s*\}\n\s*//s;
  '

  local process_pool="$root/WKProcessPoolManager.swift"
  if [[ -f "$process_pool" ]]; then
    if [[ ! -w "$process_pool" ]]; then
      echo "apply_plugin_patches: warning: could not update $process_pool" >&2
      return 0
    fi

    local tmp
    tmp="$(mktemp)"
    cat > "$tmp" <<'EOF'
//
//  WKProcessPoolManager.swift
//  flutter_inappwebview
//
//  Created by Lorenzo Pichilli on 19/11/2019.
//

import Foundation

// WKProcessPool is deprecated on iOS 15+. WebKit now manages process isolation automatically.
public class WKProcessPoolManager {}
EOF
    if ! cmp -s "$process_pool" "$tmp"; then
      if mv "$tmp" "$process_pool"; then
        echo "apply_plugin_patches: updated WKProcessPoolManager.swift"
      else
        rm "$tmp"
        echo "apply_plugin_patches: warning: could not update $process_pool" >&2
      fi
    else
      rm "$tmp"
    fi
  fi
}

patch_cupertino_native() {
  local root="$PLUGINS_DIR/cupertino_native/ios/Classes/Views"
  [[ -d "$root" ]] || return 0

  patch_file_in_place "$root/CupertinoIconPlatformView.swift" perl -pi -e 's/var img:/let img:/'
  patch_file_in_place "$root/CupertinoButtonPlatformView.swift" perl -pi -e 's/var img = img0/let img = img0/'
  patch_file_in_place "$root/CupertinoTabBarPlatformView.swift" perl -0pi -e '
    s/\n    var sizes: \[NSNumber\] = \[\] \/\/ ignored; use system metrics//;
    s/\n    var colors: \[NSNumber\] = \[\] \/\/ ignored; use tintColor//;
    s/\n      sizes = \(dict\["sfSymbolSizes"\] as\? \[NSNumber\]\) \?\? \[\]//;
    s/\n      colors = \(dict\["sfSymbolColors"\] as\? \[NSNumber\]\) \?\? \[\]//;
    s/var leftInset: CGFloat = 0/let leftInset: CGFloat = 0/g;
    s/var rightInset: CGFloat = 0/let rightInset: CGFloat = 0/g;
    s/let symbols = self\.currentSymbols\n          let appearance:/let symbols = self.currentSymbols\n          let _:/s;
  '
}

patch_flutter_background_service_ios() {
  local file="$PLUGINS_DIR/flutter_background_service_ios/ios/Classes/SwiftFlutterBackgroundServicePlugin.swift"
  [[ -f "$file" ]] || return 0

  patch_file_in_place "$file" perl -0pi -e '
    s/UIApplication\.shared\.setMinimumBackgroundFetchInterval\(UIApplication\.backgroundFetchIntervalMinimum\)\n\s*if #available\(iOS 13\.0, \*\) \{/if #available(iOS 13.0, *) {/s;
    s/@available\(iOS 13, \*\)\nclass FlutterBackgroundRefreshAppOperation: Operation/@available(iOS 13, *)\nclass FlutterBackgroundRefreshAppOperation: Operation, @unchecked Sendable/s;
  '
}

copy_patch_tree "flutter_inappwebview_ios"
copy_patch_tree "cupertino_native"
copy_patch_tree "flutter_background_service_ios"

patch_flutter_inappwebview_ios
patch_cupertino_native
patch_flutter_background_service_ios

echo "apply_plugin_patches: done (iOS deployment target >= ${DEPLOYMENT_TARGET})."
