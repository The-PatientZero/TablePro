#!/bin/bash
# Create a professional DMG background image

set -e

OUTPUT_DIR="${1:-.dmg-assets}"
OUTPUT_FILE="$OUTPUT_DIR/dmg-background.png"

mkdir -p "$OUTPUT_DIR"

echo "🎨 Creating DMG background image..."

if ! command -v convert &> /dev/null; then
    echo "❌ ERROR: ImageMagick not found"
    echo "   Install with: brew install imagemagick"
    exit 1
fi

# DMG window size: 600x400
WIDTH=600
HEIGHT=400

# Create background with gradient
convert -size ${WIDTH}x${HEIGHT} \
    gradient:'#f5f5f7-#ffffff' \
    "$OUTPUT_FILE"

# Add arrow pointing from left to right
convert "$OUTPUT_FILE" \
    -stroke '#007AFF' \
    -strokewidth 3 \
    -fill none \
    -draw "path 'M 250,200 L 350,200'" \
    -draw "path 'M 340,190 L 350,200 L 340,210'" \
    "$OUTPUT_FILE"

# Add subtle text hint at bottom
convert "$OUTPUT_FILE" \
    -font "Helvetica" \
    -pointsize 13 \
    -fill '#86868b' \
    -gravity South \
    -annotate +0+30 'Drag the app icon to the Applications folder to install' \
    "$OUTPUT_FILE"

# Add subtle shadow effect
convert "$OUTPUT_FILE" \
    \( +clone -background black -shadow 60x3+0+0 \) \
    +swap -background none -layers merge +repage \
    "$OUTPUT_FILE"

echo "✅ Background image created: $OUTPUT_FILE"
echo "   Size: ${WIDTH}x${HEIGHT}"
