#!/usr/bin/env bash
set -euo pipefail

savy_mode="${1:---verify}"
case "$savy_mode" in
  run|--verify|--debug|--logs|--telemetry) ;;
  *) echo "Usage: $0 [run|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
savy_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
savy_install="${SAVY_MAC_INSTALL_PATH:-/Applications/SAVY.app}"
savy_artifacts="$savy_root/artifacts/mac-build"
mkdir -p "$savy_artifacts"
cd "$savy_root"

pkill -x SAVY >/dev/null 2>&1 || true
savy_build_args=(-project SAVY.xcodeproj -scheme SAVY -configuration Release
  -destination 'platform=macOS,variant=Mac Catalyst' -disableAutomaticPackageResolution)
xcodebuild "${savy_build_args[@]}" build > "$savy_artifacts/build.log" 2>&1 || {
  tail -60 "$savy_artifacts/build.log" >&2
  exit 1
}
xcodebuild "${savy_build_args[@]}" -showBuildSettings -json > "$savy_artifacts/settings.json"
savy_product="$(/usr/bin/python3 - "$savy_artifacts/settings.json" <<'PY'
import json, pathlib, sys
settings = next(row['buildSettings'] for row in json.load(open(sys.argv[1])) if row['target'] == 'SAVY')
print(pathlib.Path(settings['TARGET_BUILD_DIR']) / settings['WRAPPER_NAME'])
PY
)"
/usr/bin/codesign --verify --deep --strict "$savy_product"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$savy_product/Contents/Info.plist")" = com.adamblair.savy

savy_staging="$(mktemp -d "$(dirname "$savy_install")/.savy-install.XXXXXX")"
trap 'rmdir "$savy_staging" 2>/dev/null || true' EXIT
/usr/bin/ditto "$savy_product" "$savy_staging/SAVY.app"
/usr/bin/codesign --verify --deep --strict "$savy_staging/SAVY.app"
if [[ -e "$savy_install" ]]; then
  savy_backup="$(mktemp -d "$savy_artifacts/previous.XXXXXX")"
  mv "$savy_install" "$savy_backup/SAVY.app"
fi
mv "$savy_staging/SAVY.app" "$savy_install"

case "$savy_mode" in
  --debug) lldb -- "$savy_install/Contents/MacOS/SAVY" ;;
  --logs)
    /usr/bin/open "$savy_install"
    /usr/bin/log stream --info --style compact --predicate 'process == "SAVY"'
    ;;
  --telemetry)
    /usr/bin/open "$savy_install"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.adamblair.savy"'
    ;;
  *)
    /usr/bin/open "$savy_install"
    if [[ "$savy_mode" == --verify ]]; then
      sleep 1
      pgrep -x SAVY >/dev/null
    fi
    ;;
esac
echo "Built and launched $savy_install"
