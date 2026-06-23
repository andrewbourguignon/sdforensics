#!/bin/bash
set -e

PNG_INPUT=$1
OUT_ICNS=$2

if [ -z "$PNG_INPUT" ] || [ -z "$OUT_ICNS" ]; then
    echo "Usage: ./create_icns.sh <input_png> <output_icns>"
    exit 1
fi

ICONSET_DIR="AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

echo "Scaling and converting icon sizes to PNG..."
sips -s format png -z 16 16     "$PNG_INPUT" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null 2>&1
sips -s format png -z 32 32     "$PNG_INPUT" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null 2>&1
sips -s format png -z 32 32     "$PNG_INPUT" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null 2>&1
sips -s format png -z 64 64     "$PNG_INPUT" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null 2>&1
sips -s format png -z 128 128   "$PNG_INPUT" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null 2>&1
sips -s format png -z 256 256   "$PNG_INPUT" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null 2>&1
sips -s format png -z 256 256   "$PNG_INPUT" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null 2>&1
sips -s format png -z 512 512   "$PNG_INPUT" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null 2>&1
sips -s format png -z 512 512   "$PNG_INPUT" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null 2>&1
sips -s format png -z 1024 1024 "$PNG_INPUT" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null 2>&1

echo "Compiling .icns format..."
iconutil -c icns "$ICONSET_DIR" -o "$OUT_ICNS"

rm -rf "$ICONSET_DIR"
echo "Icon generated successfully: $OUT_ICNS"
