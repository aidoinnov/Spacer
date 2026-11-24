#!/bin/bash
# Legacy SwiftUI reference/CLI packaging. Primary UI: scripts/build-gpui-app.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
app="$(pwd)/dist/Mac Space Sniffer.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/AppIcon.iconset
if [[ "${1:-}" == "--universal" ]]; then
  swift build -c "$configuration" --arch arm64
  swift build -c "$configuration" --arch x86_64
  lipo -create ".build/arm64-apple-macosx/$configuration/MacSpaceSniffer" ".build/x86_64-apple-macosx/$configuration/MacSpaceSniffer" -output "$app/Contents/MacOS/MacSpaceSniffer"
else
  swift build -c "$configuration"
  bin_path="$(swift build -c "$configuration" --show-bin-path)"
  cp "$bin_path/MacSpaceSniffer" "$app/Contents/MacOS/MacSpaceSniffer"
fi
mkdir -p "$app/Contents/Resources/MCP"
cp scripts/mcp/space_sniffer_mcp.py "$app/Contents/Resources/MCP/space_sniffer_mcp.py"
cp scripts/mcp/control_transport.py "$app/Contents/Resources/MCP/control_transport.py"
swift scripts/make-icon.swift dist/AppIcon-1024.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" dist/AppIcon-1024.png --out "dist/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" dist/AppIcon-1024.png --out "dist/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Mac Space Sniffer</string>
<key>CFBundleDisplayName</key><string>Mac Space Sniffer</string>
<key>CFBundleIdentifier</key><string>local.macspacesniffer.app</string>
<key>CFBundleExecutable</key><string>MacSpaceSniffer</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>20261121.1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Independent macOS implementation. Not affiliated with Uderzo Software.</string>
</dict></plist>
PLIST
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/MacSpaceSniffer-macOS.zip"
printf 'Built: %s\n' "$app"
