#!/bin/bash
set -e

# Deployer Install Script
# Usage: curl -fsSL https://raw.githubusercontent.com/base-go/dr/main/install.sh | sudo bash
# Or with domain: DEPLOYER_DOMAIN=example.com curl -fsSL ... | sudo bash

DEPLOYER_VERSION="${DEPLOYER_VERSION:-latest}"
DEPLOYER_DIR="${DEPLOYER_DIR:-/opt/deployer}"
DEPLOYER_USER="${DEPLOYER_USER:-deployer}"
DEPLOYER_DOMAIN="${DEPLOYER_DOMAIN:-}"
DEPLOYER_PASSWORD="${DEPLOYER_PASSWORD:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[x]${NC} $1"; exit 1; }
ask() { echo -e "${BLUE}[?]${NC} $1"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: curl -fsSL ... | sudo bash"
fi

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    error "Cannot detect OS"
fi

log "Detected OS: $OS"

# Interactive domain setup if not provided
setup_domain() {
    # Check if DEPLOYER_DOMAIN was passed via sudo
    if [ -z "$DEPLOYER_DOMAIN" ] && [ -n "$SUDO_DEPLOYER_DOMAIN" ]; then
        DEPLOYER_DOMAIN="$SUDO_DEPLOYER_DOMAIN"
    fi

    if [ -n "$DEPLOYER_DOMAIN" ]; then
        log "Using domain: $DEPLOYER_DOMAIN"
        log "Dashboard will be at: d.$DEPLOYER_DOMAIN"
        # Generate random password if not provided
        if [ -z "$DEPLOYER_PASSWORD" ]; then
            DEPLOYER_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
        fi
        log "Admin password generated"
        return
    fi

    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}         Domain Configuration          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo "Deployer needs a root domain for your apps."
    echo ""
    echo "Example: If you enter 'example.com':"
    echo "  - Dashboard:  d.example.com"
    echo "  - Apps:       myapp.example.com, ghost.example.com, etc."
    echo ""
    echo "Prerequisites:"
    echo "  1. You own this domain"
    echo "  2. DNS wildcard A record: *.yourdomain.com -> this server's IP"
    echo ""

    # Check if stdin is a terminal (interactive mode)
    if [ -t 0 ]; then
        ask "Enter your root domain (e.g., example.com):"
        read -r DEPLOYER_DOMAIN

        if [ -z "$DEPLOYER_DOMAIN" ]; then
            warn "No domain entered. Apps will use IP:port access only."
            warn "You can configure a domain later in: $DEPLOYER_DIR/config/deployer.yaml"
        else
            log "Domain set to: $DEPLOYER_DOMAIN"
            log "Dashboard will be at: d.$DEPLOYER_DOMAIN"

            # Ask for email for SSL certificates
            ask "Enter email for SSL certificates (optional, press Enter to skip):"
            read -r DEPLOYER_EMAIL

            if [ -n "$DEPLOYER_EMAIL" ]; then
                log "Email set to: $DEPLOYER_EMAIL"
            fi

            # Generate random password if not provided
            if [ -z "$DEPLOYER_PASSWORD" ]; then
                DEPLOYER_PASSWORD=$(openssl rand -base64 12 | tr -d '/+=' | head -c 16)
            fi
            log "Admin password generated"
        fi
    else
        # Non-interactive mode without domain - piping curl without DEPLOYER_DOMAIN set
        warn "Non-interactive mode detected."
        warn "To configure domain, use: curl ... | sudo DEPLOYER_DOMAIN=example.com bash"
        warn ""
        warn "Proceeding without domain. Dashboard will be accessible via IP:port."
        warn "You can configure domain later in: $DEPLOYER_DIR/config/deployer.yaml"
    fi
    echo ""
}

# Install dependencies based on OS
install_deps() {
    log "Installing dependencies..."

    case $OS in
        ubuntu|debian)
            apt-get update -qq
            apt-get install -y -qq curl wget podman sqlite3 ca-certificates
            ;;
        fedora|centos|rhel|rocky|alma)
            dnf install -y podman sqlite curl wget ca-certificates
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm podman sqlite curl wget
            ;;
        *)
            error "Unsupported OS: $OS. Please install manually."
            ;;
    esac
}

# Install Caddy
install_caddy() {
    if command -v caddy &> /dev/null; then
        log "Caddy already installed"
        return
    fi

    log "Installing Caddy..."

    case $OS in
        ubuntu|debian)
            apt-get install -y -qq debian-keyring debian-archive-keyring apt-transport-https
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
            curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
            apt-get update -qq
            apt-get install -y -qq caddy
            ;;
        fedora|centos|rhel|rocky|alma)
            dnf install -y 'dnf-command(copr)'
            dnf copr enable -y @caddy/caddy
            dnf install -y caddy
            ;;
        arch|manjaro)
            pacman -Sy --noconfirm caddy
            ;;
        *)
            # Fallback: download binary
            curl -fsSL "https://caddyserver.com/api/download?os=linux&arch=$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')" -o /usr/local/bin/caddy
            chmod +x /usr/local/bin/caddy
            ;;
    esac
}

# Create deployer user
create_user() {
    if id "$DEPLOYER_USER" &>/dev/null; then
        log "User $DEPLOYER_USER already exists"
    else
        log "Creating user $DEPLOYER_USER..."
        useradd -r -m -s /bin/bash "$DEPLOYER_USER"
    fi

    # Add to podman group if exists
    usermod -aG podman "$DEPLOYER_USER" 2>/dev/null || true

    # Configure subuid/subgid for rootless Podman
    # This is required for Podman to map UIDs/GIDs in containers
    log "Configuring subuid/subgid for rootless Podman..."
    if ! grep -q "^$DEPLOYER_USER:" /etc/subuid 2>/dev/null; then
        echo "$DEPLOYER_USER:100000:65536" >> /etc/subuid
    fi
    if ! grep -q "^$DEPLOYER_USER:" /etc/subgid 2>/dev/null; then
        echo "$DEPLOYER_USER:100000:65536" >> /etc/subgid
    fi
}

# Download and install deployer
install_deployer() {
    log "Installing Deployer to $DEPLOYER_DIR..."

    # Create directories with proper permissions (as root)
    mkdir -p "$DEPLOYER_DIR"/{bin,config,data,logs}
    chown -R root:root "$DEPLOYER_DIR/bin"
    chmod 755 "$DEPLOYER_DIR" "$DEPLOYER_DIR/bin"

    # Detect architecture
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        *) error "Unsupported architecture: $ARCH" ;;
    esac

    # Get latest version info
    LATEST_VERSION=$(curl -fsSL "https://api.github.com/repos/base-go/dr/releases/latest" 2>/dev/null | grep '"tag_name"' | sed 's/.*"v\(.*\)".*/\1/' || echo "unknown")
    log "Installing version: $LATEST_VERSION"

    # Download deployer binary
    if [ "$DEPLOYER_VERSION" = "latest" ]; then
        DOWNLOAD_URL="https://github.com/base-go/dr/releases/latest/download/deployer-linux-$ARCH"
    else
        DOWNLOAD_URL="https://github.com/base-go/dr/releases/download/$DEPLOYER_VERSION/deployer-linux-$ARCH"
    fi

    log "Downloading from $DOWNLOAD_URL..."
    rm -f "$DEPLOYER_DIR/bin/deployer"
    curl -fsSL "$DOWNLOAD_URL" -o "$DEPLOYER_DIR/bin/deployer" || {
        warn "Binary not found, building from source..."
        build_from_source
    }

    chmod +x "$DEPLOYER_DIR/bin/deployer"
    ln -sf "$DEPLOYER_DIR/bin/deployer" /usr/local/bin/deployer
}

# Build from source if binary not available
build_from_source() {
    log "Building from source..."

    # Install Go if not present
    if ! command -v go &> /dev/null; then
        log "Installing Go..."
        curl -fsSL "https://go.dev/dl/go1.22.0.linux-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/').tar.gz" | tar -C /usr/local -xzf -
        export PATH=$PATH:/usr/local/go/bin
    fi

    # Clone and build
    TMPDIR=$(mktemp -d)
    git clone --depth 1 https://github.com/base-go/deployer.git "$TMPDIR"
    cd "$TMPDIR"
    go build -o "$DEPLOYER_DIR/bin/deployer" ./cmd/deployer
    cd -
    rm -rf "$TMPDIR"
}

# Create configuration
create_config() {
    log "Creating configuration..."

    # Determine email for SSL
    local ssl_email="${DEPLOYER_EMAIL:-}"
    if [ -z "$ssl_email" ] && [ -n "$DEPLOYER_DOMAIN" ]; then
        ssl_email="admin@$DEPLOYER_DOMAIN"
    fi

    # Generate password hash using sha256
    local password_hash=""
    if [ -n "$DEPLOYER_PASSWORD" ]; then
        password_hash=$(echo -n "$DEPLOYER_PASSWORD" | sha256sum | cut -d' ' -f1)
    fi

    if [ -n "$DEPLOYER_DOMAIN" ]; then
        # Production mode with real domain
        cat > "$DEPLOYER_DIR/config/deployer.yaml" <<EOF
server:
  api_port: 3000
  host: 0.0.0.0

auth:
  password_hash: $password_hash

podman:
  socket: /run/podman/podman.sock

caddy:
  admin_url: http://localhost:2019

database:
  path: $DEPLOYER_DIR/data/deployer.db

domain:
  base: $DEPLOYER_DOMAIN
  wildcard: true
  email: $ssl_email
EOF
    else
        # No domain mode - access via IP:port (no auth required for local)
        cat > "$DEPLOYER_DIR/config/deployer.yaml" <<EOF
server:
  api_port: 3000
  host: 0.0.0.0

podman:
  socket: /run/podman/podman.sock

caddy:
  admin_url: http://localhost:2019

database:
  path: $DEPLOYER_DIR/data/deployer.db

domain:
  suffix: ""
  wildcard: false
EOF
    fi
}

# Create Caddyfile
create_caddyfile() {
    log "Creating Caddyfile..."

    # Use provided email or default
    local ssl_email="${DEPLOYER_EMAIL:-admin@$DEPLOYER_DOMAIN}"

    if [ -n "$DEPLOYER_DOMAIN" ]; then
        cat > "$DEPLOYER_DIR/config/Caddyfile" <<EOF
{
    admin localhost:2019
    email $ssl_email
    on_demand_tls {
        ask http://localhost:3000/api/caddy/check
    }
}

d.$DEPLOYER_DOMAIN {
    tls {
        on_demand
    }
    reverse_proxy localhost:3000
}

:443 {
    tls {
        on_demand
    }
    reverse_proxy localhost:3000
}
EOF
    else
        cat > "$DEPLOYER_DIR/config/Caddyfile" <<EOF
{
    admin localhost:2019
    auto_https off
}

# Dashboard accessible via IP:80
:80 {
    reverse_proxy localhost:3000
}
EOF
    fi
}

# Create systemd services
create_services() {
    log "Creating systemd services..."

    # Run podman system migrate for the deployer user (required after subuid/subgid changes)
    log "Running podman system migrate..."
    sudo -u "$DEPLOYER_USER" sh -c "cd /tmp && podman system migrate" 2>/dev/null || true

    # Deployer service
    cat > /etc/systemd/system/deployer.service <<EOF
[Unit]
Description=Deployer PaaS
After=network.target podman.socket

[Service]
Type=simple
User=$DEPLOYER_USER
Group=$DEPLOYER_USER
WorkingDirectory=$DEPLOYER_DIR
ExecStart=$DEPLOYER_DIR/bin/deployer
Restart=always
RestartSec=5
Environment=DEPLOYER_CONFIG=$DEPLOYER_DIR/config/deployer.yaml
Environment=PODMAN_SOCKET=/run/podman/podman.sock

[Install]
WantedBy=multi-user.target
EOF

    # Configure Caddy to use our Caddyfile
    # If system Caddy service exists, copy our Caddyfile to /etc/caddy/
    if [ -f /lib/systemd/system/caddy.service ] || [ -f /usr/lib/systemd/system/caddy.service ]; then
        log "Using system Caddy service, updating /etc/caddy/Caddyfile..."
        mkdir -p /etc/caddy
        cp "$DEPLOYER_DIR/config/Caddyfile" /etc/caddy/Caddyfile
        chown root:root /etc/caddy/Caddyfile
        chmod 644 /etc/caddy/Caddyfile
    else
        # No system service, create our own
        cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy Web Server
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/caddy run --config $DEPLOYER_DIR/config/Caddyfile
ExecReload=/usr/bin/caddy reload --config $DEPLOYER_DIR/config/Caddyfile
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    fi

    # Enable system-wide podman socket (preferred for server use)
    log "Enabling Podman socket..."
    systemctl enable podman.socket 2>/dev/null || true
    systemctl start podman.socket 2>/dev/null || true

    # Also enable user-level podman socket as fallback
    sudo -u "$DEPLOYER_USER" systemctl --user enable podman.socket 2>/dev/null || true
    sudo -u "$DEPLOYER_USER" systemctl --user start podman.socket 2>/dev/null || true
    loginctl enable-linger "$DEPLOYER_USER" 2>/dev/null || true

    # Add deployer user to podman socket group for access
    if [ -S /run/podman/podman.sock ]; then
        chmod 660 /run/podman/podman.sock 2>/dev/null || true
        chgrp "$DEPLOYER_USER" /run/podman/podman.sock 2>/dev/null || true
    fi

    systemctl daemon-reload
}

# Set permissions
set_permissions() {
    log "Setting permissions..."

    # Create builds directory for source deployments
    mkdir -p "$DEPLOYER_DIR/builds"

    chown -R "$DEPLOYER_USER:$DEPLOYER_USER" "$DEPLOYER_DIR"
    chmod 750 "$DEPLOYER_DIR"
    chmod 640 "$DEPLOYER_DIR/config/"*
    chmod 750 "$DEPLOYER_DIR/builds"
}

# Start services
start_services() {
    log "Starting services..."

    systemctl enable caddy
    systemctl start caddy

    systemctl enable deployer
    systemctl start deployer
}

# Print success message
print_success() {
    local server_ip=$(hostname -I | awk '{print $1}')

    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}  Deployer installed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""

    if [ -n "$DEPLOYER_DOMAIN" ]; then
        echo "  Dashboard: https://d.$DEPLOYER_DOMAIN"
        echo "  Apps:      https://appname.$DEPLOYER_DOMAIN"
        echo ""
        echo "  SSL certificates will be automatically obtained from Let's Encrypt."
        echo ""
        echo -e "${YELLOW}  Login password:${NC}"
        echo "    $DEPLOYER_PASSWORD"
        echo ""
        echo -e "${YELLOW}  Save this password! It won't be shown again.${NC}"
    else
        echo "  Dashboard: http://$server_ip:3000"
        echo ""
        echo -e "${YELLOW}  Note: No domain configured.${NC}"
        echo "  Apps will be accessible via direct port mapping only."
        echo ""
        echo "  To add a domain later, edit: $DEPLOYER_DIR/config/deployer.yaml"
        echo "  And set: domain.base: yourdomain.com"
    fi

    echo ""
    echo "  Config:    $DEPLOYER_DIR/config/deployer.yaml"
    echo "  Logs:      journalctl -u deployer -f"
    echo ""
    echo "  Commands:"
    echo "    systemctl status deployer   # Check status"
    echo "    systemctl restart deployer  # Restart"
    echo "    journalctl -u deployer -f   # View logs"
    echo "    deployer update             # Update to latest version"
    echo ""
}

# Main
main() {
    echo ""
    echo "  ____             _                       "
    echo " |  _ \  ___ _ __ | | ___  _   _  ___ _ __ "
    echo " | | | |/ _ \ '_ \| |/ _ \| | | |/ _ \ '__|"
    echo " | |_| |  __/ |_) | | (_) | |_| |  __/ |   "
    echo " |____/ \___| .__/|_|\___/ \__, |\___|_|   "
    echo "            |_|            |___/           "
    echo ""
    echo " Self-hosted PaaS with Podman & Caddy"
    echo ""

    # Ask for domain configuration first
    setup_domain

    install_deps
    install_caddy
    create_user
    install_deployer
    create_config
    create_caddyfile
    create_services
    set_permissions
    start_services
    print_success
}

# Uninstall function
uninstall() {
    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}       Uninstalling Deployer           ${NC}"
    echo -e "${RED}========================================${NC}"
    echo ""

    # Stop services
    log "Stopping services..."
    systemctl stop deployer 2>/dev/null || true
    systemctl disable deployer 2>/dev/null || true

    # Remove systemd service
    log "Removing systemd service..."
    rm -f /etc/systemd/system/deployer.service
    systemctl daemon-reload

    # Remove binary symlink
    log "Removing binary..."
    rm -f /usr/local/bin/deployer

    # Ask about data
    if [ -t 0 ]; then
        ask "Remove all data and config? (y/N):"
        read -r REMOVE_DATA
    else
        REMOVE_DATA="n"
    fi

    if [ "$REMOVE_DATA" = "y" ] || [ "$REMOVE_DATA" = "Y" ]; then
        log "Removing data directory..."
        rm -rf "$DEPLOYER_DIR"

        # Remove user
        log "Removing user..."
        userdel -r "$DEPLOYER_USER" 2>/dev/null || true
    else
        warn "Keeping data directory: $DEPLOYER_DIR"
        warn "Keeping user: $DEPLOYER_USER"
    fi

    echo ""
    echo -e "${GREEN}Deployer uninstalled.${NC}"
    echo ""
    echo "Note: Caddy and Podman were NOT removed."
    echo "To remove them manually:"
    echo "  apt remove caddy podman  # Debian/Ubuntu"
    echo "  dnf remove caddy podman  # Fedora/RHEL"
    echo ""
}

# Check for uninstall argument
if [ "${1:-}" = "uninstall" ] || [ "${1:-}" = "--uninstall" ]; then
    uninstall
    exit 0
fi

main "$@"
