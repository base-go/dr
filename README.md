# Deployer

A self-hosted Platform as a Service (PaaS) built with **Go**, **Podman**, and **Caddy**. Deploy your applications with ease, similar to CapRover but using rootless containers.

## Features

- **Easy Deployments** - Deploy from Docker images or Git repositories
- **Automatic SSL** - Free HTTPS via Let's Encrypt with Caddy
- **Rootless Containers** - Powered by Podman, no root required
- **Modern Web UI** - Built with Nuxt 4 and Nuxt UI 4
- **Powerful CLI** - Full control from the command line
- **OS Agnostic** - Works on Linux and macOS

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Frontend                             │
│              Nuxt 4 + Nuxt UI 4 (Vue 3)                    │
├─────────────────────────────────────────────────────────────┤
│                        REST API                             │
│                    Deployer (Go)                            │
├──────────┬──────────┬───────────┬────────────┬─────────────┤
│   Apps   │  Proxy   │    SSL    │   Deploy   │   Storage   │
│  Manager │ (Caddy)  │  (ACME)   │   Engine   │  (SQLite)   │
├──────────┴──────────┴───────────┴────────────┴─────────────┤
│                      Podman                                 │
└─────────────────────────────────────────────────────────────┘
```

## Quick Install (VPS/Linux)

One-line install on any Linux VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/base-go/deployer/main/install.sh | sudo bash
```

With a custom domain (enables automatic SSL):

```bash
DEPLOYER_DOMAIN=deploy.example.com curl -fsSL https://raw.githubusercontent.com/base-go/deployer/main/install.sh | sudo bash
```

Supported: Ubuntu, Debian, Fedora, CentOS, Rocky, Alma, Arch

After install:
- Dashboard: `http://your-server-ip:3000`
- Apps get domains: `appname.deploy.example.com`
- SSL is automatic via Let's Encrypt

## Quick Start (macOS)

Complete setup for local development with `*.pod` domains.

### Step 1: Install Dependencies

```bash
# Install Homebrew packages
brew install podman caddy dnsmasq

# Initialize Podman VM
podman machine init
podman machine start
```

### Step 2: Setup Local DNS and Port Forwarding

This enables wildcard `*.pod` domains (e.g., `nginx.pod`, `mysql.pod`).

```bash
# Configure dnsmasq
echo -e "address=/pod/127.0.0.2\nlisten-address=127.0.0.2\nport=53" | sudo tee /opt/homebrew/etc/dnsmasq.conf

# Create loopback alias for 127.0.0.2
sudo ifconfig lo0 alias 127.0.0.2

# Setup macOS resolver
sudo mkdir -p /etc/resolver
sudo bash -c 'echo "nameserver 127.0.0.2" > /etc/resolver/pod'

# Start dnsmasq
sudo /opt/homebrew/sbin/dnsmasq

# Forward port 80 to 8080 (so you can use http://app.pod instead of :8080)
echo "rdr pass on lo0 inet proto tcp from any to 127.0.0.2 port 80 -> 127.0.0.2 port 8080" | sudo pfctl -ef -

# Verify DNS works
ping -c 1 test.pod
# Should show: PING test.pod (127.0.0.2)
```

### Step 3: Build and Run

```bash
# Clone and build
git clone https://github.com/deployer/deployer.git
cd deployer
go build -o deployer ./cmd/deployer

# Start the server (auto-starts Podman & Caddy)
./deployer

# In a new terminal, start the web UI
cd web
bun install
bun dev
```

### Step 4: Access Dashboard

Open http://localhost:3000

- Create apps manually or use **One-Click Apps**
- Apps automatically get `{name}.pod` domains
- Access apps at `http://nginx.pod`, `http://ghost.pod`, etc.

### After Reboot

The loopback alias, dnsmasq, and port forwarding don't persist. Run on each boot:

```bash
sudo ifconfig lo0 alias 127.0.0.2
sudo /opt/homebrew/sbin/dnsmasq
echo "rdr pass on lo0 inet proto tcp from any to 127.0.0.2 port 80 -> 127.0.0.2 port 8080" | sudo pfctl -ef -
```

Or create a startup script at `~/deployer-start.sh`:

```bash
#!/bin/bash
sudo ifconfig lo0 alias 127.0.0.2
sudo /opt/homebrew/sbin/dnsmasq
echo "rdr pass on lo0 inet proto tcp from any to 127.0.0.2 port 80 -> 127.0.0.2 port 8080" | sudo pfctl -ef -
cd ~/Base/deployer && ./deployer
```

### Troubleshooting

**Cloudflare WARP conflict:** WARP uses port 53. Disable it when developing locally.

**dnsmasq won't start:** Check if something else is using port 53:
```bash
sudo lsof -i :53
```

**Podman not connecting:** Restart the machine:
```bash
podman machine stop
podman machine start
```

**DNS not resolving:** Flush cache:
```bash
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

## One-Click Apps

Pre-configured templates available:

| Category | Apps |
|----------|------|
| Databases | MySQL, PostgreSQL, MariaDB, MongoDB, Redis |
| Admin Tools | phpMyAdmin, Adminer, pgAdmin |
| Web Servers | Nginx, Apache, Caddy |
| CMS | WordPress, Ghost |
| Dev Tools | Gitea, Portainer, Uptime Kuma |
| Automation | n8n |

## REST API

```bash
# List apps
curl http://localhost:3000/api/apps

# Create app
curl -X POST http://localhost:3000/api/apps \
  -H "Content-Type: application/json" \
  -d '{"name": "myapp"}'

# Deploy
curl -X POST http://localhost:3000/api/apps/{id}/deploy \
  -H "Content-Type: application/json" \
  -d '{"image": "nginx:latest"}'

# Get templates
curl http://localhost:3000/api/templates
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Web UI (Nuxt 3)                         │
│                   http://localhost:3000                     │
├─────────────────────────────────────────────────────────────┤
│                     Go API Server                           │
│                   http://localhost:3000                     │
├──────────┬──────────┬───────────┬────────────┬─────────────┤
│   Apps   │  Proxy   │    DNS    │  Templates │   Storage   │
│  Manager │ (Caddy)  │ (dnsmasq) │  (1-click) │  (SQLite)   │
├──────────┴──────────┴───────────┴────────────┴─────────────┤
│                      Podman VM                              │
│                   (rootless containers)                     │
└─────────────────────────────────────────────────────────────┘
```

## How It Works

1. **Create App** - App gets auto-assigned `{name}.pod` domain
2. **Deploy** - Podman pulls image, creates container with port mapping
3. **Routing** - Caddy proxies `{name}.pod` to container port
4. **Access** - Browse to `http://{name}.pod`

## Comparison with CapRover

| Feature | Deployer | CapRover |
|---------|----------|----------|
| Container Runtime | Podman (rootless) | Docker (root) |
| Reverse Proxy | Caddy | Nginx |
| Language | Go | Node.js |
| Installation | User-space (~/) | System-wide |
| SSL | Auto (built-in) | Auto (Let's Encrypt) |
| Web UI | Nuxt 4 | React |
| Multi-node | Planned | Docker Swarm |

## Roadmap

- [ ] Git push deployments
- [ ] Dockerfile builds
- [ ] Environment variable encryption
- [ ] App templates (one-click deploys)
- [ ] Multi-node support
- [ ] Backup & restore
- [ ] Metrics & monitoring
- [ ] Authentication & RBAC

## License

MIT License - see [LICENSE](LICENSE)

## Contributing

Contributions are welcome! Please read our [Contributing Guide](CONTRIBUTING.md) first.
