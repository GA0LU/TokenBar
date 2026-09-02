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

# Register with launchd. In shells that aren't children of the user's GUI
# session (e.g. an agent sandbox), launchctl is unreliable: `load` can return
# 0 without the service actually registering, and `bootstrap` fails with
# "5: Input/output error". So the pgrep check below is the source of truth —
# if the binary isn't up, fall back to LaunchServices rather than leaving the
# Touch Bar dead.
if launchctl load "$PLIST" 2>/dev/null; then
    echo "launchd: load returned 0 (verify below)"
elif launchctl bootstrap gui/"$UID" "$PLIST" 2>/dev/null; then
    echo "launchd: bootstrapped"
else
    echo "launchd unavailable (non-GUI shell?)"
fi

sleep 1
if ! pgrep -f "$INSTALLED_APP/Contents/MacOS/tokenbar" >/dev/null 2>&1; then
    echo "launchd did not bring the app up — starting via LaunchServices"
    open "$INSTALLED_APP"
    sleep 1
fi
if pgrep -f "$INSTALLED_APP/Contents/MacOS/tokenbar" >/dev/null 2>&1; then
    echo "Installed and launched: $INSTALLED_APP (pid $(pgrep -f "$INSTALLED_APP/Contents/MacOS/tokenbar" | head -1))"
else
    echo "ERROR: tokenbar did not come up — inspect $INSTALLED_APP and $PLIST" >&2
    exit 1
fi
