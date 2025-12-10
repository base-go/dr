# Deployer

Self-hosted PaaS with Podman and Caddy. Deploy apps with automatic SSL.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/base-go/dr/main/install.sh | sudo DEPLOYER_DOMAIN=example.com bash
```

This will:
- Install Podman and Caddy
- Set up dashboard at `d.example.com`
- Enable automatic SSL for all subdomains
- Generate admin password (shown after install)

### Prerequisites

1. A domain you own (e.g., `example.com`)
2. DNS wildcard A record: `*.example.com` pointing to your server IP
3. Ubuntu/Debian, Fedora/RHEL, or Arch Linux

## Upgrade

To upgrade an existing installation (preserves config and data):

```bash
curl -fsSL https://raw.githubusercontent.com/base-go/dr/main/upgrade.sh | sudo bash
```

## Current Version

**v0.1.16**

## Features

- Password-protected dashboard
- One-click app deployment
- Automatic SSL certificates via Caddy
- Podman containers (rootless)
- App templates (Ghost, Wordpress, etc.)

## Binaries

| Platform | Architecture | Download |
|----------|--------------|----------|
| Linux | amd64 | [deployer-linux-amd64](https://github.com/base-go/dr/releases/latest/download/deployer-linux-amd64) |
| Linux | arm64 | [deployer-linux-arm64](https://github.com/base-go/dr/releases/latest/download/deployer-linux-arm64) |
| macOS | amd64 | [deployer-darwin-amd64](https://github.com/base-go/dr/releases/latest/download/deployer-darwin-amd64) |
| macOS | arm64 | [deployer-darwin-arm64](https://github.com/base-go/dr/releases/latest/download/deployer-darwin-arm64) |

## Commands

```bash
# Check status
systemctl status deployer

# View logs
journalctl -u deployer -f

# Restart
systemctl restart deployer

# Update binary
deployer update
```

## Configuration

Config file: `/opt/deployer/config/deployer.yaml`

```yaml
server:
  api_port: 3000
  host: 0.0.0.0

auth:
  password_hash: <sha256-hash>

domain:
  base: example.com
  wildcard: true
  email: admin@example.com
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/base-go/dr/main/install.sh | sudo bash -s -- uninstall
```
