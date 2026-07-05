#!/bin/bash
#
# install.sh — Quick installer for zlm (ZLaunch Manager CLI)
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/zavora-ai/macos-zlaunch-manager/main/scripts/install.sh | bash
#
# Or manually:
#   git clone https://github.com/zavora-ai/macos-zlaunch-manager.git
#   cd macos-zlaunch-manager/cli && swift build -c release
#   cp .build/release/zlm /usr/local/bin/zlm
#
# Copyright 2024-2026 Zavora Technologies Ltd
# Apache License 2.0

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   zlm — ZLaunch Manager CLI Installer ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# Check macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo -e "${RED}✗ This tool only works on macOS${NC}"
    exit 1
fi

# Check Swift
if ! command -v swift &> /dev/null; then
    echo -e "${RED}✗ Swift not found. Install Xcode Command Line Tools:${NC}"
    echo "  xcode-select --install"
    exit 1
fi

INSTALL_DIR="/usr/local/bin"
TEMP_DIR=$(mktemp -d)
REPO_URL="https://github.com/zavora-ai/macos-zlaunch-manager.git"

# Check if already installed
if command -v zlm &> /dev/null; then
    CURRENT_VERSION=$(zlm --version 2>/dev/null || echo "unknown")
    echo -e "${YELLOW}  zlm is already installed (${CURRENT_VERSION})${NC}"
    echo -e "  Reinstalling..."
    echo ""
fi

# Clone and build
echo -e "${YELLOW}[1/3]${NC} Downloading source..."
git clone --depth 1 --quiet "$REPO_URL" "$TEMP_DIR/macos-zlaunch-manager" 2>/dev/null

echo -e "${YELLOW}[2/3]${NC} Building (this may take a minute)..."
cd "$TEMP_DIR/macos-zlaunch-manager/cli"
swift build -c release --quiet 2>/dev/null

echo -e "${YELLOW}[3/3]${NC} Installing to ${INSTALL_DIR}..."
if [[ -w "$INSTALL_DIR" ]]; then
    cp ".build/release/zlm" "$INSTALL_DIR/zlm"
else
    sudo cp ".build/release/zlm" "$INSTALL_DIR/zlm"
fi

# Cleanup
rm -rf "$TEMP_DIR"

# Verify
if command -v zlm &> /dev/null; then
    VERSION=$(zlm --version 2>/dev/null || echo "1.2.0")
    echo ""
    echo -e "${GREEN}✓ Installed zlm ${VERSION} to ${INSTALL_DIR}/zlm${NC}"
    echo ""
    echo -e "  Get started:"
    echo -e "    ${BLUE}zlm${NC}                    List all services"
    echo -e "    ${BLUE}zlm list -d user${NC}       List user agents"
    echo -e "    ${BLUE}zlm list --running${NC}     Show running services"
    echo -e "    ${BLUE}zlm status <label>${NC}     Service details"
    echo -e "    ${BLUE}zlm start <label>${NC}      Start a service"
    echo -e "    ${BLUE}zlm gui${NC}                Open the GUI app"
    echo -e "    ${BLUE}zlm --help${NC}             Full help"
    echo ""
else
    echo -e "${RED}✗ Installation failed. Try manually:${NC}"
    echo "  git clone $REPO_URL"
    echo "  cd macos-zlaunch-manager/cli && swift build -c release"
    echo "  cp .build/release/zlm /usr/local/bin/zlm"
    exit 1
fi
