#!/bin/bash
# Make a professional macOS DMG with background arrow + Applications link
# Usage: make_dmg.sh <app-bundle-path> <output-dmg-path> [volume-name]
set -e

APP_PATH="$1"
DMG_PATH="$2"
VOL_NAME="${3:-Masker}"

if [ -z "$APP_PATH" ] || [ -z "$DMG_PATH" ]; then
  echo "Usage: make_dmg.sh <app-bundle> <output.dmg> [volume-name]"
  exit 1
fi

APP_NAME=$(basename "$APP_PATH")
STAGING=$(mktemp -d)
BG_DIR="$STAGING/.background"
DMG_TMP="${DMG_PATH}.tmp.dmg"
CONFIG_DIR="$STAGING/.config"

mkdir -p "$BG_DIR" "$CONFIG_DIR"

# ── 1. Generate background image with arrow ──
python3 - "$APP_NAME" << 'PYEOF'
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

app_name = sys.argv[1] if len(sys.argv) > 1 else "Masker"
W, H = 660, 460

img = Image.new("RGBA", (W, H), (245, 245, 247, 255))
draw = ImageDraw.Draw(img)

try:
    font_large = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 28)
    font_small = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 16)
except:
    font_large = ImageFont.load_default()
    font_small = ImageFont.load_default()

draw.text((W//2, 30), app_name, fill=(60, 60, 70, 255), font=font_large, anchor="mt")
draw.text((W//2, 65), "Drag app to Applications folder", fill=(140, 140, 150, 255), font=font_small, anchor="mt")

# App icon rectangle (left)
ax1, ay1 = 110, 150
aw, ah = 120, 120
draw.rounded_rectangle([ax1, ay1, ax1+aw, ay1+ah], radius=18, fill=(30, 60, 140, 220))
gloss = Image.new("RGBA", (aw, ah//2), (255, 255, 255, 30))
gloss = gloss.filter(ImageFilter.GaussianBlur(6))
img.paste(gloss, (ax1, ay1+5), gloss)

# Lock icon
lock_cx, lock_cy = ax1+aw//2, ay1+ah//2
draw.rounded_rectangle([lock_cx-18, lock_cy-8, lock_cx+18, lock_cy+22], radius=4, fill=(255, 255, 255, 220))
draw.arc([lock_cx-14, lock_cy-30, lock_cx+14, lock_cy-2], start=0, end=360, fill=(255, 255, 255, 220), width=5)

# Arrow
arrow_x = W//2
arrow_y = ay1 + ah//2
draw.line([arrow_x-40, arrow_y, arrow_x+40, arrow_y], fill=(100, 100, 180, 200), width=4)
draw.polygon([(arrow_x+45, arrow_y), (arrow_x+30, arrow_y-12), (arrow_x+30, arrow_y+12)], fill=(100, 100, 180, 200))

# Applications folder rectangle
fx1, fy1 = ax1+aw+150, ay1
fw, fh = 120, 120
draw.rounded_rectangle([fx1, fy1, fx1+fw, fy1+fh], radius=18, fill=(220, 220, 228, 200))
draw.rounded_rectangle([fx1+2, fy1+2, fx1+fw-2, fy1+fh-2], radius=16, fill=(245, 245, 247, 200))
draw.rounded_rectangle([fx1+25, fy1+22, fx1+65, fy1+35], radius=3, fill=(180, 180, 190, 200))
draw.rounded_rectangle([fx1+20, fy1+30, fx1+100, fy1+95], radius=6, fill=(180, 180, 190, 200))

draw.text((ax1+aw//2, ay1+ah+15), app_name.replace(".app", ""), fill=(80, 80, 90, 255), font=font_small, anchor="mt")
draw.text((fx1+fw//2, fy1+fh+15), "Applications", fill=(80, 80, 90, 255), font=font_small, anchor="mt")
img.save("/tmp/dmg_bg.png")
print("Background image done")
PYEOF

cp /tmp/dmg_bg.png "$BG_DIR/background.png"

# ── 2. Populate staging directory ──
cp -R "$APP_PATH" "$STAGING/$APP_NAME"
ln -s /Applications "$STAGING/Applications"

# ── 3. Create DMG (read-write first for configuration) ──
echo "Creating DMG..."
hdiutil create -volname "$VOL_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDRW \
  "$DMG_TMP" 2>&1

echo "Mounting DMG for configuration..."
DEVICE=""
for i in 1 2 3; do
  DEVICE=$(hdiutil attach -readwrite -noverify "$DMG_TMP" 2>&1 | grep "/Volumes/$VOL_NAME" | awk '{print $1}')
  if [ -n "$DEVICE" ]; then
    echo "Mounted: $DEVICE"
    break
  fi
  sleep 2
done

if [ -n "$DEVICE" ]; then
  VOLUME_PATH="/Volumes/$VOL_NAME"

  # Try to configure via osascript (non-blocking, with timeout)
  if command -v osascript &>/dev/null; then
    echo "Configuring DMG window via osascript..."
    timeout 10 osascript <<-EOF 2>/dev/null || true
tell application "Finder"
  set bgPath to "$VOLUME_PATH/.background/background.png" as POSIX file as alias
  set targetView to (startup disk's folder "$VOL_NAME")
  delay 1
  try
    tell icon view options of targetView
      set arrangement to not arranged
      set icon size to 96
      set shows item info to false
      set background picture to bgPath
    end tell
    try
      set position of item "$APP_NAME" of targetView to {160, 230}
    end try
    try
      set position of item "Applications" of targetView to {500, 230}
    end try
    try
      set bounds of window 1 of application "Finder" to {100, 100, 760, 560}
    end try
  end try
end tell
EOF
  fi

  # Force write DMG metadata and detach
  echo "Detaching..."
  hdiutil detach "$DEVICE" -quiet -force 2>/dev/null || true
  sleep 2
else
  echo "Warning: Could not mount DMG, skipping window configuration"
fi

# ── 4. Convert to compressed (read-only) DMG ──
echo "Compressing DMG..."
hdiutil convert "$DMG_TMP" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" 2>&1
rm -f "$DMG_TMP"

# ── 5. Cleanup ──
rm -rf "$STAGING" /tmp/dmg_bg.png

echo "✅ DMG created: $DMG_PATH ($(du -h "$DMG_PATH" | cut -f1))"
