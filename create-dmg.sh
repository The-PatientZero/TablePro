#!/bin/bash
# Create a DMG installer with drag-and-drop installation window
# No Apple Developer account required

set -e

# Configuration
APP_NAME="TablePro"
VERSION="${1:-0.1.13}"
ARCH="${2:-universal}"
SOURCE_APP="${3:-build/Release/${APP_NAME}.app}"
DMG_NAME="${APP_NAME}-${VERSION}-${ARCH}.dmg"
VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG_DIR="build/dmg"
TEMP_DMG="$DMG_DIR/temp.dmg"
FINAL_DMG="build/Release/$DMG_NAME"

echo "📦 Creating DMG installer for $APP_NAME..."
echo "   Version: $VERSION"
echo "   Architecture: $ARCH"
echo "   Source: $SOURCE_APP"

# Verify source app exists
if [ ! -d "$SOURCE_APP" ]; then
    echo "❌ ERROR: Source app not found: $SOURCE_APP"
    exit 1
fi

# Clean and create DMG directory
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"

# Create staging directory
STAGING_DIR="$DMG_DIR/staging"
mkdir -p "$STAGING_DIR"

echo "📋 Preparing DMG contents..."

# Copy app to staging
cp -R "$SOURCE_APP" "$STAGING_DIR/$APP_NAME.app"

# Create Applications symlink for drag-and-drop
ln -s /Applications "$STAGING_DIR/Applications"

# Create .background directory for custom background
mkdir -p "$STAGING_DIR/.background"

# Create a simple background image using ImageMagick or skip if not available
if command -v convert &> /dev/null; then
    echo "🎨 Creating background image..."

    # Create a nice gradient background with instructions
    convert -size 600x400 \
        -background "#f0f0f0" \
        -fill "#333333" \
        -font "Helvetica-Bold" -pointsize 24 \
        -gravity North -annotate +0+30 "Install $APP_NAME" \
        -font "Helvetica" -pointsize 14 \
        -gravity Center -annotate +0+0 "Drag $APP_NAME to the Applications folder" \
        -font "Helvetica" -pointsize 12 \
        -fill "#666666" \
        -gravity South -annotate +0+20 "→" \
        "$STAGING_DIR/.background/background.png"
else
    echo "⚠️  ImageMagick not found, skipping custom background"
    echo "   Install with: brew install imagemagick"
fi

# Calculate size needed for DMG
echo "📐 Calculating DMG size..."
SIZE=$(du -sh "$STAGING_DIR" | awk '{print $1}')
echo "   Staging size: $SIZE"

# Add 50MB padding
SIZE_MB=$(du -sm "$STAGING_DIR" | awk '{print $1}')
SIZE_MB=$((SIZE_MB + 50))

echo "🔨 Creating temporary DMG ($SIZE_MB MB)..."

# Create temporary DMG
hdiutil create -srcfolder "$STAGING_DIR" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDRW \
    -size ${SIZE_MB}m \
    "$TEMP_DMG"

echo "📝 Configuring DMG layout..."

# Mount the temporary DMG
MOUNT_DIR="/Volumes/$VOLUME_NAME"
hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen

# Wait for mount
sleep 2

# Run AppleScript to set window properties
osascript <<EOF
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {100, 100, 700, 500}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 80
        set background picture of viewOptions to file ".background:background.png"

        -- Position icons
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}

        close
        open
        update without registering applications
        delay 2
    end tell
end tell
EOF

# Sync changes
sync

# Unmount
echo "💾 Finalizing DMG..."
hdiutil detach "$MOUNT_DIR"

# Convert to compressed read-only DMG
hdiutil convert "$TEMP_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$FINAL_DMG"

# Clean up
rm -rf "$DMG_DIR"

# Verify final DMG
if [ ! -f "$FINAL_DMG" ]; then
    echo "❌ ERROR: Failed to create DMG"
    exit 1
fi

# Get final size
FINAL_SIZE=$(du -h "$FINAL_DMG" | awk '{print $1}')

echo ""
echo "✅ DMG created successfully!"
echo "   📍 Location: $FINAL_DMG"
echo "   📊 Size: $FINAL_SIZE"
echo ""
echo "🧪 Test the DMG:"
echo "   open \"$FINAL_DMG\""
