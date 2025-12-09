#!/bin/bash
set -e

# Deployer Upgrade Script
# Usage: curl -fsSL https://raw.githubusercontent.com/base-go/dr/main/upgrade.sh | sudo bash

DEPLOYER_VERSION="${DEPLOYER_VERSION:-latest}"
DEPLOYER_DIR="${DEPLOYER_DIR:-/opt/deployer}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: curl -fsSL ... | sudo bash"
fi

# Check if deployer is installed
if [ ! -f "$DEPLOYER_DIR/bin/deployer" ]; then
    error "Deployer not found at $DEPLOYER_DIR. Please run install.sh first."
fi

echo ""
echo "  ____             _                       "
echo " |  _ \  ___ _ __ | | ___  _   _  ___ _ __ "
echo " | | | |/ _ \ '_ \| |/ _ \| | | |/ _ \ '__|"
echo " | |_| |  __/ |_) | | (_) | |_| |  __/ |   "
echo " |____/ \___| .__/|_|\___/ \__, |\___|_|   "
echo "            |_|            |___/           "
echo ""
echo " Upgrade Script"
echo ""

# Get current version
CURRENT_VERSION=$("$DEPLOYER_DIR/bin/deployer" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
log "Current version: $CURRENT_VERSION"

# Detect architecture
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *) error "Unsupported architecture: $ARCH" ;;
esac

# Download URL
if [ "$DEPLOYER_VERSION" = "latest" ]; then
    DOWNLOAD_URL="https://github.com/base-go/dr/releases/latest/download/deployer-linux-$ARCH"
    # Get latest version from GitHub API
    LATEST_VERSION=$(curl -sL https://api.github.com/repos/base-go/dr/releases/latest | grep '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
    log "Latest version: $LATEST_VERSION"
else
    DOWNLOAD_URL="https://github.com/base-go/dr/releases/download/$DEPLOYER_VERSION/deployer-linux-$ARCH"
    LATEST_VERSION="$DEPLOYER_VERSION"
fi

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    log "Already running the latest version ($CURRENT_VERSION)"
    exit 0
fi

# Stop service
log "Stopping deployer service..."
systemctl stop deployer 2>/dev/null || true

# Backup current binary
log "Backing up current binary..."
cp "$DEPLOYER_DIR/bin/deployer" "$DEPLOYER_DIR/bin/deployer.bak"

# Download new binary
log "Downloading version $LATEST_VERSION..."
if ! curl -fsSL "$DOWNLOAD_URL" -o "$DEPLOYER_DIR/bin/deployer.new"; then
    warn "Download failed, restoring backup..."
    mv "$DEPLOYER_DIR/bin/deployer.bak" "$DEPLOYER_DIR/bin/deployer"
    systemctl start deployer
    error "Failed to download new version"
fi

# Replace binary
mv "$DEPLOYER_DIR/bin/deployer.new" "$DEPLOYER_DIR/bin/deployer"
chmod +x "$DEPLOYER_DIR/bin/deployer"

# Verify new binary works
if ! "$DEPLOYER_DIR/bin/deployer" version &>/dev/null; then
    warn "New binary failed verification, restoring backup..."
    mv "$DEPLOYER_DIR/bin/deployer.bak" "$DEPLOYER_DIR/bin/deployer"
    systemctl start deployer
    error "New binary verification failed"
fi

# Remove backup
rm -f "$DEPLOYER_DIR/bin/deployer.bak"

# Restart services
log "Restarting deployer service..."
systemctl restart deployer

log "Restarting caddy service..."
systemctl restart caddy 2>/dev/null || true

# Verify service is running
sleep 2
if systemctl is-active --quiet deployer; then
    NEW_VERSION=$("$DEPLOYER_DIR/bin/deployer" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "$LATEST_VERSION")
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Upgrade successful!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "  Previous version: $CURRENT_VERSION"
    echo "  Current version:  $NEW_VERSION"
    echo ""
    echo "  Config preserved at: $DEPLOYER_DIR/config/"
    echo "  Data preserved at:   $DEPLOYER_DIR/data/"
    echo ""
else
    warn "Service failed to start, restoring backup..."
    mv "$DEPLOYER_DIR/bin/deployer.bak" "$DEPLOYER_DIR/bin/deployer" 2>/dev/null || true
    systemctl start deployer
    error "Service failed to start after upgrade"
fi
