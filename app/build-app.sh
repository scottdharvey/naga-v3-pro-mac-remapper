#!/bin/bash
# Builds "Naga Remapper.app" next to this script.
#   VERSION=1.2.0   version shown in Finder (default 0.1)
#   BUILD=7         build number (default 1)
#   UNIVERSAL=1     build for both Apple silicon and Intel (needs the full Xcode app; used by the release workflow)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${VERSION:-0.1}"
BUILD="${BUILD:-1}"
ARCH_FLAGS=()
if [[ "${UNIVERSAL:-0}" == "1" ]]; then ARCH_FLAGS=(--arch arm64 --arch x86_64); fi

swift build -c release --product NagaRemapper ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/NagaRemapper"

APP="Naga Remapper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/NagaRemapper"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Naga Remapper</string>
  <key>CFBundleDisplayName</key><string>Naga Remapper</string>
  <key>CFBundleIdentifier</key><string>local.naga.remapper</string>
  <key>CFBundleExecutable</key><string>NagaRemapper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD}</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $(pwd)/$APP ($(lipo -archs "$APP/Contents/MacOS/NagaRemapper"))"
