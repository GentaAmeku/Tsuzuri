#!/usr/bin/env bash
# TsuzuriApp を .app にまとめて署名する(OnCue と同じ形。Xcode のプロジェクトは作らない)。
# 権限(マイク・アクセシビリティ)の許可は署名に結び付くので、開発中も Apple Development の証明書で署名する。
#
# 使い方: scripts/build-app-bundle.sh [--install]
#   --install  /Applications/Tsuzuri.app に置き換えて起動する
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRODUCT="TsuzuriApp"
DISPLAY_NAME="Tsuzuri"
CONFIGURATION="${CONFIGURATION:-release}"
BUNDLE_IDENTIFIER="${TSUZURI_BUNDLE_IDENTIFIER:-work.ameku.Tsuzuri}"
INSTALL_DIR="${TSUZURI_INSTALL_DIR:-/Applications}"
INSTALL=0
[[ "${1:-}" == "--install" ]] && INSTALL=1

# 署名の証明書。TSUZURI_SIGNING_IDENTITY が無ければ、キーチェーンの Apple Development を1つ選ぶ
IDENTITY="${TSUZURI_SIGNING_IDENTITY:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)}"
if [[ -z "$IDENTITY" ]]; then
  echo "Apple Development の証明書が見つかりません。TSUZURI_SIGNING_IDENTITY で指定してください" >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build --product "$PRODUCT" -c "$CONFIGURATION"
BIN_DIR="$(swift build --show-bin-path -c "$CONFIGURATION")"
APP_DIR="$ROOT_DIR/.build/$DISPLAY_NAME.app"
BUILD_VERSION="$(git rev-list --count HEAD)"
SOURCE_REVISION="$(git rev-parse --short=12 HEAD)"
[[ -n "$(git status --porcelain)" ]] && SOURCE_REVISION="$SOURCE_REVISION-dirty"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/$PRODUCT" "$APP_DIR/Contents/MacOS/$PRODUCT"
# 初めて起動したときに置く辞書。評価用の辞書と同じ語から始める(設計書「辞書の形と使い方」)
cp "$ROOT_DIR/eval/dictionary.json" "$APP_DIR/Contents/Resources/starter-dictionary.json"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$PRODUCT</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>TsuzuriSourceRevision</key>
  <string>$SOURCE_REVISION</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>話した声を文字にするために、マイクを使います。</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST
# アプリのアイコン(scripts/make-app-icon.swift で作る)。あれば入れる
if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
  plutil -insert CFBundleIconFile -string AppIcon "$APP_DIR/Contents/Info.plist"
fi
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null

# hardened runtime を付け、ほかのプログラムがライブラリを差し込んで権限を使えないようにする。
# hardened runtime ではマイクに entitlement が要る
ENTITLEMENTS="$ROOT_DIR/.build/Tsuzuri.entitlements"
cat > "$ENTITLEMENTS" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
ENT
codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DIR" >/dev/null
codesign --verify --deep --strict "$APP_DIR"

if [[ "$INSTALL" == 1 ]]; then
  pkill -x "$PRODUCT" 2>/dev/null && sleep 1 || true
  rm -rf "$INSTALL_DIR/$DISPLAY_NAME.app"
  cp -R "$APP_DIR" "$INSTALL_DIR/"
  # アイコンなどを macOS に読み直させる(置き換えても、Finder や設定の一覧が古い表示を覚えていることがある)
  touch "$INSTALL_DIR/$DISPLAY_NAME.app"
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_DIR/$DISPLAY_NAME.app" || true
  open "$INSTALL_DIR/$DISPLAY_NAME.app"
  echo "$INSTALL_DIR/$DISPLAY_NAME.app"
else
  echo "$APP_DIR"
fi
