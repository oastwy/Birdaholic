#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="鸟瘾 OSEA 批量识别"
BUILD_DIR="$ROOT/build/osea_batch_identifier_app"
DIST_DIR="$ROOT/dist"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/OSEA_Batch_Identifier.dmg"
STAGE_DIR="$BUILD_DIR/dmg_stage"

rm -rf "$BUILD_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/packager" "$DIST_DIR" "$STAGE_DIR"

cp "$ROOT/packager/osea_batch_identifier.py" "$APP_DIR/Contents/Resources/packager/"
cp "$ROOT/packager/OSEA_BATCH_IDENTIFIER.md" "$APP_DIR/Contents/Resources/packager/"

# Bundle OSEA model files if they exist
OSEA_MODEL="$ROOT/models/osea/bird_model.onnx"
OSEA_INFO="$ROOT/models/osea/bird_info.json"
if [[ -f "$OSEA_MODEL" && -f "$OSEA_INFO" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources/models/osea"
  cp "$OSEA_MODEL" "$APP_DIR/Contents/Resources/models/osea/"
  cp "$OSEA_INFO" "$APP_DIR/Contents/Resources/models/osea/"
  echo "✓ Bundled OSEA model files ($(du -sh "$OSEA_MODEL" | cut -f1))"
else
  echo "⚠ OSEA model files not found – DMG will require manual model placement"
  echo "  Expected: $OSEA_MODEL"
  echo "  Expected: $OSEA_INFO"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>launcher</string>
  <key>CFBundleIdentifier</key>
  <string>com.birdaholic.osea.batchidentifier</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>鸟瘾 OSEA 批量识别</string>
  <key>CFBundleDisplayName</key>
  <string>鸟瘾 OSEA 批量识别</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

swiftc "$ROOT/packager/OseaBatchIdentifierApp.swift" \
  -parse-as-library \
  -o "$APP_DIR/Contents/MacOS/launcher" \
  -framework SwiftUI \
  -framework AppKit

cp -R "$APP_DIR" "$STAGE_DIR/"
cp "$ROOT/packager/OSEA_BATCH_IDENTIFIER.md" "$STAGE_DIR/使用说明.md"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "$DMG_PATH"
