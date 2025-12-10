#!/bin/bash
set -e

# Deployer Uninstall Script
# Usage: curl -fsSL https://raw.githubusercontent.com/base-go/dr/main/uninstall.sh | sudo bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }

if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}[x]${NC} Please run as root"
    exit 1
fi

echo ""
echo -e "${RED}========================================${NC}"
echo -e "${RED}       Uninstalling Deployer           ${NC}"
echo -e "${RED}========================================${NC}"
echo ""

# Stop services
log "Stopping services..."
systemctl stop deployer 2>/dev/null || true
systemctl stop caddy 2>/dev/null || true
systemctl disable deployer 2>/dev/null || true

# Remove systemd service
log "Removing deployer service..."
rm -f /etc/systemd/system/deployer.service
systemctl daemon-reload

# Remove binary symlink
log "Removing binary..."
rm -f /usr/local/bin/deployer

# Remove Caddyfile
log "Removing Caddyfile..."
rm -f /etc/caddy/Caddyfile

# Remove data directory
log "Removing /opt/deployer..."
rm -rf /opt/deployer

# Remove deployer user
log "Removing deployer user..."
userdel -r deployer 2>/dev/null || true

# Optionally remove Caddy and Podman
echo ""
warn "Caddy and Podman were NOT removed."
warn "To remove them:"
echo "  apt remove -y caddy podman  # Debian/Ubuntu"
echo "  dnf remove -y caddy podman  # Fedora/RHEL"
echo ""

echo -e "${GREEN}Deployer completely uninstalled.${NC}"
echo ""
