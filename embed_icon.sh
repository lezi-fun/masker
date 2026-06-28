#!/bin/bash
# Convert master 1024x1024 PNG to .icns and embed into .app bundles
set -e

cd "$(dirname "$0")"
MASTER="masker-icon/master.png"

if [ ! -f "$MASTER" ]; then
    echo "❌ Master icon not found: $MASTER"
    echo "Run generate_icon.sh first"
    exit 1
fi

echo "Creating iconset..."
ICONSET="masker-icon/Masker.iconset"
mkdir -p "$ICONSET"

# Generate all required sizes from master
sips -z 16 16     "$MASTER" --out "$ICONSET/icon_16x16.png" > /dev/null 2>&1
sips -z 32 32     "$MASTER" --out "$ICONSET/icon_16x16@2x.png" > /dev/null 2>&1
cp "$ICONSET/icon_16x16@2x.png" "$ICONSET/icon_32x32.png"
sips -z 64 64     "$MASTER" --out "$ICONSET/icon_32x32@2x.png" > /dev/null 2>&1
sips -z 128 128   "$MASTER" --out "$ICONSET/icon_128x128.png" > /dev/null 2>&1
sips -z 256 256   "$MASTER" --out "$ICONSET/icon_128x128@2x.png" > /dev/null 2>&1
cp "$ICONSET/icon_128x128@2x.png" "$ICONSET/icon_256x256.png"
sips -z 512 512   "$MASTER" --out "$ICONSET/icon_256x256@2x.png" > /dev/null 2>&1
cp "$ICONSET/icon_256x256@2x.png" "$ICONSET/icon_512x512.png"
cp "$MASTER" "$ICONSET/icon_512x512@2x.png"

# Convert to .icns
echo "Converting to .icns..."
iconutil -c icns "$ICONSET" -o "masker-icon/Masker.icns"
echo "✅ masker-icon/Masker.icns created"

# Embed into .app bundles
for APP in Masker.app Masker-轻量版.app; do
    if [ -d "$APP" ]; then
        cp "masker-icon/Masker.icns" "$APP/Contents/Resources/"
        # Update Info.plist to reference the icon
        PLIST="$APP/Contents/Info.plist"
        if ! grep -q "CFBundleIconFile" "$PLIST" 2>/dev/null; then
            # Insert icon reference before closing dict
            sed -i '' 's|</dict>|  <key>CFBundleIconFile</key>\n  <string>Masker</string>\n</dict>|' "$PLIST"
        fi
        # Touch to refresh icon cache
        touch "$APP"
        echo "✅ Icon embedded: $APP"
    fi
done

echo ""
echo "Done! App icons are ready."
