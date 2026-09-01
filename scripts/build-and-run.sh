#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="TokenBar"
BUNDLE_ID="local.tokenbar"
APP="$ROOT/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LABEL="$BUNDLE_ID"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

swift build -c release --disable-sandbox

BINARY="$ROOT/.build/release/tokenbar"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/tokenbar"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
if [[ -d "$ROOT/Sources/TokenBar/Resources" ]]; then
    cp -R "$ROOT/Sources/TokenBar/Resources/." "$APP/Contents/Resources/"
fi

codesign --force --options runtime --sign - "$APP/Contents/MacOS/tokenbar"
codesign --force --options runtime --sign - "$APP"
xattr -cr "$APP" 2>/dev/null || true

mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents"
launchctl unload "$PLIST" 2>/dev/null || true
pkill -f "$INSTALLED_APP/Contents/MacOS/tokenbar" 2>/dev/null || true
pkill -x tokenbar 2>/dev/null || true
rm -rf "$INSTALLED_APP"
cp -R "$APP" "$INSTALL_DIR/"
xattr -cr "$INSTALLED_APP" 2>/dev/null || true

cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALLED_APP/Contents/MacOS/tokenbar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST_EOF

launchctl load "$PLIST" || launchctl bootstrap gui/"$UID" "$PLIST" || true
echo "Installed and launched: $INSTALLED_APP"
