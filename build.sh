#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

desktop_app="${HOME}/Desktop/PDF Viewer.app"
stage="$(mktemp -d)/PDF Viewer.app"
mkdir -p "$stage/Contents/MacOS" "$stage/Contents/Resources"
cp Info.plist "$stage/Contents/Info.plist"
printf 'APPL????' > "$stage/Contents/PkgInfo"

icon_src="Resources/AppIcon.png"
iconset="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$iconset"
sips -z 16 16 "$icon_src" --out "$iconset/icon_16x16.png" >/dev/null
sips -z 32 32 "$icon_src" --out "$iconset/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$icon_src" --out "$iconset/icon_32x32.png" >/dev/null
sips -z 64 64 "$icon_src" --out "$iconset/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$icon_src" --out "$iconset/icon_128x128.png" >/dev/null
sips -z 256 256 "$icon_src" --out "$iconset/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$icon_src" --out "$iconset/icon_256x256.png" >/dev/null
sips -z 512 512 "$icon_src" --out "$iconset/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$icon_src" --out "$iconset/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$icon_src" --out "$iconset/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$iconset" -o "$stage/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$iconset")"

swiftc -parse-as-library -O \
  -o "$stage/Contents/MacOS/PDF Viewer" \
  Sources/main.swift

codesign --force --sign - "$stage"

app_pids() {
  /bin/ps -axww -o pid=,command= | /usr/bin/awk '
    index($0, "/Contents/MacOS/PDF Viewer") && $0 !~ /build\.sh/ && $0 !~ /awk/ {
      print $1
    }
  '
}

quit_app() {
  local signal pids
  for signal in TERM KILL; do
    pids="$(app_pids || true)"
    echo "pdf viewer pids before ${signal}: [${pids}]"
    if [[ -z "${pids}" ]]; then
      return 0
    fi
    # shellcheck disable=SC2086
    kill "-${signal}" ${pids} || true
    for _ in {1..30}; do
      pids="$(app_pids || true)"
      if [[ -z "${pids}" ]]; then
        echo "pdf viewer quit after ${signal}"
        return 0
      fi
      sleep 0.1
    done
  done
  echo "pdf viewer still running: [$(app_pids || true)]"
  return 1
}

if ! quit_app; then
  echo "PDF Viewer is still running, so the new app was not installed." >&2
  exit 1
fi

rm -rf "$desktop_app"
ditto "$stage" "$desktop_app"
rm -rf "$(dirname "$stage")"
xattr -cr "$desktop_app" >/dev/null 2>&1 || true
codesign --force --sign - "$desktop_app"
touch "$desktop_app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$desktop_app" >/dev/null 2>&1 || true

echo "Built $desktop_app"
