#!/bin/bash
set -e

APP_NAME="VOEBBMenu"
APP_DIR="$APP_NAME.app"
BINARY=".build/release/$APP_NAME"

echo "Building release binary..."
swift build -c release 2>&1

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy icon if available. Defaults to a repo-relative AppIcon.icns;
# override with `ICON_SRC=/path/to/icon.icns ./build_app.sh`.
ICON_SRC="${ICON_SRC:-AppIcon.icns}"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "Icon bundled from: $ICON_SRC"
else
    echo "No icon found at '$ICON_SRC' — building without custom app icon."
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>VOEBBMenu</string>
    <key>CFBundleDisplayName</key>
    <string>VÖBB</string>
    <key>CFBundleIdentifier</key>
    <string>de.voebb.menubar</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleExecutable</key>
    <string>VOEBBMenu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
        <key>NSExceptionDomains</key>
        <dict>
            <key>voebb.de</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
                <key>NSExceptionAllowsInsecureHTTPLoads</key>
                <false/>
            </dict>
        </dict>
    </dict>
</dict>
</plist>
PLIST

echo "App bundle created at: $APP_DIR"
echo "Launch with: open $APP_DIR"
