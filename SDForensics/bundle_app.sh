#!/bin/bash
set -e

# Configuration
APP_NAME="SDForensics"
BUNDLE_DIR="${APP_NAME}.app"
CONTENTS_DIR="${BUNDLE_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "=============================================="
echo "    COMPILING AND PACKAGING macOS APP BUNDLE   "
echo "=============================================="

# 1. Compile package in Release mode
echo "Compiling release binary..."
swift build -c release

# 2. Re-create bundle directory structure
echo "Rebuilding bundle folders..."
rm -rf "$BUNDLE_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Copy built executable directly as bundle entry point
echo "Copying binary to target bundle..."
cp ".build/release/SDForensics" "${MACOS_DIR}/${APP_NAME}"

# 4. Generate Icon file
if [ -f "icon_source.png" ]; then
    echo "Creating AppIcon.icns..."
    chmod +x create_icns.sh
    ./create_icns.sh icon_source.png "${RESOURCES_DIR}/AppIcon.icns"
else
    echo "Warning: icon_source.png not found. App bundle will not have a custom icon."
fi

# 5. Generate standard Info.plist file
echo "Writing Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.company.SDForensics</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

echo "=============================================="
echo "      macOS APP BUNDLE PACKAGING SUCCESS      "
echo "  Created: ${BUNDLE_DIR} in the workspace   "
echo "=============================================="
