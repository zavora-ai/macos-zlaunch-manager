#!/bin/bash
#
# create-dmg.sh
# Builds a release .dmg for Launch Manager
#
# Usage: ./scripts/create-dmg.sh
#
# Prerequisites:
#   - Xcode command line tools
#   - Optional: Developer ID certificate for signing/notarization
#
# Copyright 2024-2026 Zavora Technologies Ltd
# Licensed under Apache License 2.0

set -e

# Configuration
APP_NAME="LaunchManager"
BUNDLE_ID="com.launchmanager.app"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
XCODE_PROJECT="$PROJECT_DIR/LaunchManager/LaunchManager.xcodeproj"
BUILD_DIR="$PROJECT_DIR/build"
DMG_DIR="$BUILD_DIR/dmg"
RELEASE_DIR="$BUILD_DIR/release"
VERSION=$(date +"%Y.%m.%d")
DMG_WINDOW_WIDTH=660
DMG_WINDOW_HEIGHT=440

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     Launch Manager — DMG Builder         ║${NC}"
echo -e "${BLUE}║     Zavora Technologies Ltd              ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

# Clean previous builds
echo -e "${YELLOW}[1/5]${NC} Cleaning previous builds..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DMG_DIR" "$RELEASE_DIR"

# Build release
echo -e "${YELLOW}[2/5]${NC} Building release configuration (Universal Binary)..."
xcodebuild -project "$XCODE_PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -arch arm64 -arch x86_64 \
    ONLY_ACTIVE_ARCH=NO \
    build \
    CONFIGURATION_BUILD_DIR="$RELEASE_DIR" \
    2>&1 | grep -E "(BUILD SUCCEEDED|BUILD FAILED|error:)" || true

if [ ! -d "$RELEASE_DIR/$APP_NAME.app" ]; then
    echo -e "${RED}✗ Build failed! App bundle not found.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build succeeded${NC}"

# Optional: Code sign with Developer ID
if [ -n "$DEVELOPER_ID" ]; then
    echo -e "${YELLOW}[3/5]${NC} Signing with Developer ID: $DEVELOPER_ID"
    codesign --force --deep --sign "Developer ID Application: $DEVELOPER_ID" \
        --options runtime \
        "$RELEASE_DIR/$APP_NAME.app"
    echo -e "${GREEN}✓ Signed successfully${NC}"
else
    echo -e "${YELLOW}[3/5]${NC} Skipping code signing (set DEVELOPER_ID env var to enable)"
fi

# Prepare DMG contents
echo -e "${YELLOW}[4/5]${NC} Preparing DMG contents..."
cp -R "$RELEASE_DIR/$APP_NAME.app" "$DMG_DIR/"

# Create Applications symlink for drag-to-install
ln -sf /Applications "$DMG_DIR/Applications"

# Add a visible README with install instructions
cat > "$DMG_DIR/Install Instructions.txt" << 'INSTRUCTIONS'
╔══════════════════════════════════════════════════════════╗
║              Launch Manager — Installation               ║
╚══════════════════════════════════════════════════════════╝

  INSTALL:
    Drag "LaunchManager.app" → "Applications" folder

  FIRST RUN:
    If macOS shows "unidentified developer" warning:
    1. Right-click LaunchManager.app
    2. Select "Open"
    3. Click "Open" in the dialog

  WHAT IT DOES:
    Launch Manager provides a native GUI for managing
    macOS launchd services (agents and daemons).

    • View all launchd services across all domains
    • Start, stop, restart, load/unload services
    • Edit plist configuration files
    • View service logs
    • Create new services from templates

  REQUIREMENTS:
    • macOS 14.0 (Sonoma) or later

  UNINSTALL:
    Drag LaunchManager from Applications to Trash.

──────────────────────────────────────────────────────────
  © 2024-2026 Zavora Technologies Ltd
  james.karanja@zavora.ai
  Apache License 2.0
──────────────────────────────────────────────────────────
INSTRUCTIONS

# Add background image
mkdir -p "$DMG_DIR/.background"
if [ -f "$SCRIPT_DIR/dmg-background.png" ]; then
    cp "$SCRIPT_DIR/dmg-background.png" "$DMG_DIR/.background/background.png"
    if [ -f "$SCRIPT_DIR/dmg-background@2x.png" ]; then
        cp "$SCRIPT_DIR/dmg-background@2x.png" "$DMG_DIR/.background/background@2x.png"
    fi
fi

# Create a DS_Store to configure the DMG window appearance
# We'll create a temporary writable DMG, configure it, then convert

DMG_NAME="LaunchManager-${VERSION}.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
TEMP_DMG="$BUILD_DIR/tmp.dmg"

echo -e "${YELLOW}[5/5]${NC} Creating DMG: $DMG_NAME"

# Create compressed DMG directly (skip Finder customization for reliability)
hdiutil create -volname "Launch Manager" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO \
    -imagekey zlib-level=9 \
    -fs HFS+ \
    "$DMG_PATH" \
    >/dev/null 2>&1

# Optional: Notarize
if [ -n "$APPLE_ID" ] && [ -n "$APPLE_TEAM_ID" ]; then
    echo ""
    echo -e "${YELLOW}Notarizing with Apple...${NC}"
    xcrun notarytool submit "$DMG_PATH" \
        --apple-id "$APPLE_ID" \
        --team-id "$APPLE_TEAM_ID" \
        --keychain-profile "notarytool-profile" \
        --wait

    # Staple the notarization ticket
    xcrun stapler staple "$DMG_PATH"
    echo -e "${GREEN}✓ Notarization complete${NC}"
else
    echo -e "  ${BLUE}ℹ${NC}  Skipping notarization (set APPLE_ID and APPLE_TEAM_ID to enable)"
fi

# Summary
DMG_SIZE=$(du -h "$DMG_PATH" | awk '{print $1}')
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║        DMG Created Successfully!         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BLUE}File:${NC}    $DMG_PATH"
echo -e "  ${BLUE}Size:${NC}    $DMG_SIZE"
echo -e "  ${BLUE}Version:${NC} $VERSION"
echo ""
echo -e "  ${YELLOW}To install:${NC} Open the DMG and drag Launch Manager → Applications"
echo ""
echo -e "  ${YELLOW}For distribution:${NC}"
echo -e "    export DEVELOPER_ID=\"Your Name (TEAMID)\""
echo -e "    export APPLE_ID=\"your@email.com\""
echo -e "    export APPLE_TEAM_ID=\"TEAMID\""
echo -e "    ./scripts/create-dmg.sh"
echo ""
