# Diador Deployment Guide

Comprehensive reference for building, deploying, and operating Diador — a multi-tenant SaaS deployment of AionUi.

## Table of Contents

- [1. Project Overview](#1-project-overview)
- [2. Quick Start (Local Development)](#2-quick-start-local-development)
- [3. Multi-Client Deployment](#3-multi-client-deployment)
- [4. Docker Image Details](#4-docker-image-details)
- [5. TLS / HTTPS Setup](#5-tls--https-setup)
- [6. Critical Gotchas / Pitfalls](#6-critical-gotchas--pitfalls)
- [7. Branding](#7-branding)
- [8. Commit History](#8-commit-history)
- [9. Phase 3 — What's Next](#9-phase-3--whats-next)

---

## 1. Project Overview

### What Diador Is

Diador is a branded multi-tenant SaaS deployment of [AionUi](https://github.com/iOfficeAI/AionUi), an open-source Electron AI chat application (Apache 2.0). Each client gets their own isolated instance running at `clientname.diador.ai`, served from a single EC2 host with per-client Docker containers and Nginx wildcard SSL routing.

### Architecture

```
Internet
    |
    | HTTPS *.diador.ai (wildcard cert, Let's Encrypt DNS-01)
    v
+---------------------------------------------------------------+
|                    EC2 t3.xlarge                                |
|  Ubuntu 22.04 — 100 GB data EBS at /data                       |
|                                                                 |
|  +----------------------------------------------------------+  |
|  |  Nginx (host, port 443/80)                                |  |
|  |  map $host -> $diador_port (one line per client)          |  |
|  +------+---------------------------------------------------+  |
|         | proxy_pass http://127.0.0.1:$diador_port              |
|         v                                                       |
|  +-------------+  +-------------+  +-------------+             |
|  | client1     |  | client2     |  | client3     |             |
|  | Docker      |  | Docker      |  | Docker      |             |
|  | :25809      |  | :25810      |  | :25811      |             |
|  +------+------+  +------+------+  +------+------+             |
|         |                |                |                     |
|  +------+------+  +------+------+  +------+------+             |
|  | vol:        |  | vol:        |  | vol:        |             |
|  | client1_data|  | client2_data|  | client3_data|             |
|  +-------------+  +-------------+  +-------------+             |
+---------------------------------------------------------------+
```

### Current Status

| Phase | Description | Status |
|-------|-------------|--------|
| Phase 1 | Container Foundation — Docker image, branding, health checks | Complete |
| Phase 2 | Orchestration & Routing — multi-client Compose, Nginx, TLS config | Complete |
| Phase 3 | Production Deployment & Operations — EC2, 3 clients live, runbooks | Pending |

---

## 2. Quick Start (Local Development)

### Prerequisites

- Docker Engine 24+ with Compose v2
- ~4 GB free disk space for the image build

### Build and Run

```bash
# Build and start a single container (dev testing)
docker compose up -d --build

# Check health status
docker compose ps

# View logs
docker compose logs -f
```

The WebUI will be available at **http://127.0.0.1:25808**.

### First Login

On first start, the app creates a default admin account. Check the container logs for the initial password:

```bash
docker compose logs | grep -i password
```

Default username: `admin`

### Data Persistence

Data is stored in a named Docker volume (`aionui_data`) mounted at `/root/.config/AionUi/` inside the container. This persists across `docker compose down` and `docker compose up`. To verify:

```bash
# Stop the container
docker compose down

# Start it again
docker compose up -d

# Conversations and settings will still be there
```

To completely reset data:

```bash
docker compose down -v  # -v removes volumes
```

---

## 3. Multi-Client Deployment

### Directory Structure

```
deploy/
├── add-client.sh          # Provision a new client (end-to-end)
├── remove-client.sh       # Teardown a client (backup + cleanup)
├── docker-compose.yml     # Multi-client Compose template
├── port-registry.env      # Source of truth: client -> port mapping
├── clients/               # Per-client .env files (auto-generated)
│   ├── client1.env
│   └── client2.env
├── backups/               # Volume backups from remove-client.sh
├── nginx/
│   └── diador.conf        # Nginx wildcard subdomain routing
└── tls/
    ├── setup-certbot.sh   # Issue wildcard TLS cert
    ├── renew-cron         # Auto-renewal crontab entry
    └── README.md          # TLS setup instructions
```

### Port Registry

`deploy/port-registry.env` is the **single source of truth** for client-to-port mappings. Format:

```
# client_name=port
client1=25809
client2=25810
client3=25811
```

- Port range: **25809-25899** (25808 is reserved for dev)
- Both `add-client.sh` and the Nginx `map` block derive from this file
- Never edit Docker Compose or Nginx configs directly — use the scripts

### Adding a Client

```bash
cd deploy
bash add-client.sh <client-name>
```

**What it does:**
1. Validates client name (lowercase alphanumeric, hyphens allowed)
2. Checks the client doesn't already exist in the registry
3. Allocates the next available port from the 25809-25899 range
4. Adds an entry to `port-registry.env`
5. Creates a per-client `.env` file in `clients/`
6. Injects a line into the Nginx `map` block and reloads Nginx (if available)
7. Starts the container via `docker compose -p diador-<name>`
8. Waits up to 60s for the health check to pass
9. Prints the local URL and subdomain

**Example:**

```bash
$ bash add-client.sh acme
==> Provisioning client 'acme' on port 25809
  [+] Added to port registry
  [+] Created clients/acme.env
  [+] Added to Nginx map block
  [+] Nginx reloaded
  [~] Starting container diador-acme...
  [+] Container started
  [~] Waiting for health check (up to 60s)...
      Attempt 1/12: status=starting

======================================
 Client 'acme' is HEALTHY
 URL: http://127.0.0.1:25809
 Subdomain: https://acme.diador.ai
======================================
```

### Removing a Client

```bash
cd deploy
bash remove-client.sh <client-name>
```

**What it does:**
1. Verifies the client exists in the registry
2. Prompts for confirmation (y/N)
3. **Backs up the named volume** to `backups/<name>-<timestamp>.tar.gz`
4. Stops and removes the container and volume
5. Removes the client's line from the Nginx `map` block and reloads Nginx
6. Removes the port registry entry
7. Removes the per-client `.env` file

The backup always runs before any destructive action.

### Nginx Routing

The Nginx config at `deploy/nginx/diador.conf` uses the `map` module for zero-boilerplate subdomain routing:

```nginx
map $host $diador_port {
    hostnames;
    default             0;
    client1.diador.ai   25809;
    client2.diador.ai   25810;
}
```

Key configuration:

| Directive | Value | Purpose |
|-----------|-------|---------|
| `proxy_read_timeout` | `86400` (24h) | Prevents WebSocket idle disconnect at 60s |
| `proxy_send_timeout` | `86400` | Matches read timeout for symmetry |
| `proxy_buffering` | `off` | Streaming AI responses pass through immediately |
| `proxy_http_version` | `1.1` | Required for WebSocket upgrade |
| `Upgrade` / `Connection` | forwarded | WebSocket handshake headers |

Unknown subdomains return **444** (drop connection, no response body).

HTTP (port 80) automatically redirects to HTTPS (port 443).

### Managing Containers Manually

```bash
# View all running Diador containers
docker ps --filter "name=diador-"

# View logs for a specific client
docker logs diador-client1-diador-1

# Restart a specific client
docker compose --env-file deploy/clients/client1.env \
  -f deploy/docker-compose.yml -p diador-client1 restart

# Check health status
docker inspect --format='{{.State.Health.Status}}' diador-client1-diador-1
```

---

## 4. Docker Image Details

### Base Image

**`debian:bookworm-slim`** — this is a hard constraint, not a choice.

Alpine Linux uses musl libc, which is ABI-incompatible with:
- Electron's pre-built Chromium binaries (linked against glibc)
- better-sqlite3 native bindings (compiled for glibc)

Using Alpine causes immediate crashes with cryptic errors or, worse, silent data corruption in SQLite.

### Build Stages

```dockerfile
FROM debian:bookworm-slim

# 1. System dependencies — Chromium runtime libs + build tools
apt-get install libgtk-3-0 libnss3 libgbm1 ... python3 make g++ curl unzip

# 2. Node.js 22 LTS (via nodesource)
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -

# 3. Bun package manager
curl -fsSL https://bun.sh/install | bash

# 4. Dependencies (layer cached — only invalidated if package.json/bun.lock change)
COPY package.json bun.lock patches/ ./
bun install --frozen-lockfile --ignore-scripts

# 5. Source code
COPY . .

# 6. Electron binary download (skipped by --ignore-scripts)
node node_modules/electron/install.js

# 7. Native module rebuild (better-sqlite3, bcrypt, node-pty)
node scripts/postinstall.js

# 8. Build with electron-vite
bun run make
```

**Why `--ignore-scripts`?** The postinstall script (`scripts/postinstall.js`) references files not yet available during the dependency install layer. By skipping scripts during install and running them after `COPY . .`, we preserve Docker layer caching for dependencies while ensuring all build artifacts are available.

### CMD and Chromium Flags

```dockerfile
CMD ["npx", "electron", ".", "--webui", "--remote",
     "--no-sandbox", "--ozone-platform=headless",
     "--disable-gpu", "--disable-software-rasterizer"]
```

| Flag | Purpose |
|------|---------|
| `electron .` | Uses `package.json` `main` field so `app.getAppPath()` returns `/app` (not `/app/out/main`) |
| `--webui` | Starts the built-in Express + WebSocket server |
| `--remote` | Binds to `0.0.0.0` instead of `127.0.0.1` (required inside Docker) |
| `--no-sandbox` | Required when running as root — Chromium checks at native startup before JS |
| `--ozone-platform=headless` | Provides a display backend without X11/Wayland (NOT `--headless`, which triggers browser automation mode and causes auto-exit) |
| `--disable-gpu` | No GPU available in containers |
| `--disable-software-rasterizer` | Prevents fallback software rendering (unnecessary overhead) |

**Critical:** `--no-sandbox` and `--ozone-platform=headless` must be CLI arguments, not `app.commandLine.appendSwitch()` calls. Chromium reads these during native initialization before any JavaScript runs.

**Critical:** Do **not** use `--headless`. This triggers Chromium's browser automation/testing mode which auto-exits after page load. Use `--ozone-platform=headless` instead, which provides a headless display backend while keeping the Electron process alive.

**Critical:** Use `electron .` not `electron out/main/index.js`. The latter causes `app.getAppPath()` to return `/app/out/main/`, which makes the static file server look for `/app/out/main/out/renderer/index.html` (double-nested). It falls back to Vite dev server proxy, producing 502 errors.

### Health Check

```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:25808/"]
  interval: 10s
  timeout: 5s
  retries: 3
  start_period: 30s
```

The container is considered healthy when the WebUI HTTP server responds with 200. Start period of 30s allows Electron to initialize before health checks begin.

### Security

| Aspect | Configuration | Rationale |
|--------|---------------|-----------|
| User | `root` | Electron requires `--no-sandbox` as root; acceptable for v1 with Docker isolation |
| seccomp | `unconfined` | Chromium's zygote process needs `clone3` syscall, blocked by default profile |
| Network | Loopback-only port binding | `127.0.0.1:PORT:25808` — never exposed to internet |

---

## 5. TLS / HTTPS Setup

### Overview

Wildcard TLS certificate for `*.diador.ai` via Let's Encrypt DNS-01 challenge using the `certbot-dns-route53` plugin. This is the only viable approach — HTTP-01 challenges cannot issue wildcard certificates.

### Prerequisites

1. **EC2 IAM Role** with permissions on the `diador.ai` Route53 hosted zone:
   - `route53:ChangeResourceRecordSets` — creates the DNS-01 challenge TXT record
   - `route53:GetChange` — **must include** — confirms DNS propagation (commonly omitted, causes silent failures)

2. **DNS:** `*.diador.ai` wildcard A record pointing to the EC2 public IP

### Initial Certificate Issuance

```bash
sudo bash deploy/tls/setup-certbot.sh
```

This installs certbot + the Route53 plugin and issues the certificate with a 120-second DNS propagation wait (double the default, to avoid Route53 race conditions).

Certificate files:
- **Cert:** `/etc/letsencrypt/live/diador.ai/fullchain.pem`
- **Key:** `/etc/letsencrypt/live/diador.ai/privkey.pem`

### Auto-Renewal

```bash
# Install the cron job
sudo cp deploy/tls/renew-cron /etc/cron.d/diador-certbot-renew
sudo chmod 644 /etc/cron.d/diador-certbot-renew
```

The cron runs **twice daily** (2:00 AM and 2:00 PM). Certbot only actually renews when the cert is within 30 days of expiry. After renewal, Nginx is automatically reloaded via `--post-hook`.

**Do not** run hourly — failed validations are rate-limited by Let's Encrypt (5 per hour per hostname).

### Verification

```bash
# Check cert covers wildcard
openssl x509 -text -noout -in /etc/letsencrypt/live/diador.ai/cert.pem | grep DNS

# Test renewal without renewing
certbot renew --dry-run

# Check cert expiry
openssl x509 -enddate -noout -in /etc/letsencrypt/live/diador.ai/cert.pem
```

---

## 6. Critical Gotchas / Pitfalls

### Docker Build Lessons

These were discovered during iterative testing and are critical for anyone modifying the Dockerfile:

| # | Issue | Root Cause | Fix |
|---|-------|-----------|-----|
| 1 | `unzip is required to install bun` | bun's installer script needs `unzip` to extract binaries | Add `unzip` to apt-get install |
| 2 | `Couldn't find patch file` during `bun install` | `patches/` directory not available at dependency install layer | `COPY patches/ patches/` before `bun install` |
| 3 | `Cannot find module postinstall.js` | `--ignore-scripts` needed for caching, but postinstall references full source | Use `--ignore-scripts`, then run `node scripts/postinstall.js` after `COPY . .` |
| 4 | `Electron failed to install correctly` | `--ignore-scripts` also skips Electron's binary download | Run `node node_modules/electron/install.js` after `COPY . .` |
| 5 | `Running as root without --no-sandbox is not supported` | Chromium checks root at native startup before JS | Pass `--no-sandbox` as CLI arg, not `app.commandLine.appendSwitch` |
| 6 | `Missing X server or $DISPLAY` | `--ozone-platform` read during native init before JS | Pass `--ozone-platform=headless` as CLI arg |
| 7 | WebUI returns 502, proxying to Vite dev server | `electron out/main/index.js` causes wrong `getAppPath()` | Use `electron .` so `getAppPath()` returns `/app` |

### WebSocket 60-Second Idle Disconnect

Nginx's default `proxy_read_timeout` is 60 seconds. Without explicit configuration, every WebSocket connection drops at 60s of inactivity. Users see conversations "resetting" after exactly a minute.

**Fix:** `proxy_read_timeout 86400;` and `proxy_send_timeout 86400;` in the Nginx location block. Also set `proxy_buffering off;` — without it, streaming AI responses (token-by-token) are buffered and delivered in bursts.

### seccomp and Chromium

Docker's default seccomp profile blocks `clone3` and related syscalls that Chromium's zygote process requires. Electron exits within 2 seconds with no useful log output.

**Fix:** `security_opt: [seccomp:unconfined]` in docker-compose.yml. Acceptable for v1 because containers run trusted code only.

### uncaughtException Handler

The original AionUi codebase had a no-op `uncaughtException` handler in production — crashes were silently swallowed. The container would stay running but the WebUI would freeze with no log output.

**Patched in commit `26e608ae`:** Production mode now logs to stderr and calls `process.exit(1)`, allowing Docker's `restart: unless-stopped` policy to recover automatically.

---

## 7. Branding

### What Was Changed

All user-facing "AionUi" references were replaced with "Diador Technology" across 54+ touchpoints:

| Category | Files | Details |
|----------|-------|---------|
| Config | `package.json`, `electron-builder.yml` | productName, appId (`ai.diador.app`), protocol scheme |
| HTML | `src/renderer/index.html` | `<title>Diador Technology</title>` |
| UI Components | layout.tsx, Titlebar, AboutModal, ChannelConflictWarning | Sidebar, titlebar, settings dialogs |
| i18n | 24 JSON files across 6 locales | en-US, zh-CN, zh-TW, ja-JP, ko-KR, tr-TR |
| HTTP Headers | ClientFactory.ts, modelBridge.ts, fsBridge.ts | `X-Title`, `User-Agent`, `HTTP-Referer` |
| WebServer | authRoutes.ts, webserver/index.ts | QR login page title, startup message |
| Icons | resources/app.png, .ico, .icns, icon.png | Red CD monogram (all sizes) |
| SVG | logo.svg, layout.tsx inline SVG | Traced CD monogram paths |
| Login | src/renderer/assets/logos/app.png | Full "DIADOR Technology" wordmark |

### Visual Identity

- **Login page:** Full "DIADOR Technology" wordmark (navy text + red CD monogram)
- **Sidebar:** White CD monogram icon + "Diador Technology" text
- **Titlebar:** "Diador Technology"
- **App icon (dock/taskbar/favicon):** Red CD monogram on white background
- **Tray menu:** "Show Diador Technology" / "About Diador Technology"

### What Was Intentionally NOT Changed

Internal code identifiers were preserved to avoid breaking changes:

- localStorage keys (`__aionui_theme`, `__aionui_colorScheme`)
- Cookie names (`aionui-session`, `aionui-csrf-token`)
- IPC/DOM event names (`aionui-workspace-toggle`, etc.)
- Database paths and class names (`AionUIDatabase`, `aionui.db`)
- Environment variables (`AIONUI_PORT`, `AIONUI_HTTPS`)
- CSS class names (`aionui-modal`, `aionui-steps`)
- Volume mount path (`/root/.config/AionUi/`)
- Copyright/license headers in source files (reference upstream AionUi)
- GitHub URLs to upstream repo (functional links)

### Apache 2.0 Compliance

A `NOTICE` file at the repo root attributes the original AionUi authors:

```
Diador
Copyright 2025-2026 Diador (diador.ai)

This product is based on AionUi, originally developed by iOfficeAI.
Original source: https://github.com/iOfficeAI/AionUi
Licensed under the Apache License, Version 2.0.
```

---

## 8. Commit History

| Hash | Type | Message |
|------|------|---------|
| `26e608ae` | fix | `fix(main): log uncaughtException to stderr and exit in production` |
| `34c1a3b2` | feat | `feat(infra): add Docker infrastructure for headless WebUI` |
| `ddf88b51` | chore | `chore(brand): rebrand AionUi to Diador` |
| `8ab07fef` | feat | `feat(deploy): add multi-client orchestration, Nginx routing, and TLS config` |
| `92de26f3` | chore | `chore(brand): replace AionUi icons with Diador CD monogram` |
| `89ad9910` | chore | `chore(brand): use DIADOR Technology wordmark on login page` |
| `f430d95f` | chore | `chore(brand): update branding to Diador Technology with smaller login logo` |

---

## 9. Phase 3 — What's Next

Phase 3 delivers the production deployment:

### EC2 Provisioning (DEPLOY-01)

- t3.xlarge (4 vCPU / 16 GB)
- Ubuntu 22.04 LTS
- 30 GB root EBS + 100 GB data EBS mounted at `/data`
- Install: Docker Engine, Nginx, certbot
- Security group: only ports 80/443 open (loopback ports 25809-25899 NOT exposed)

### Three Clients Live (DEPLOY-02, DEPLOY-03)

```bash
# On the EC2 instance
cd /data/deploy
bash add-client.sh client1
bash add-client.sh client2
bash add-client.sh client3
```

Each client accessible at `https://clientN.diador.ai`.

### Nightly Backups (DEPLOY-04)

Cron job to archive all client volumes nightly to `/opt/backups/diador/`.

### Operations Runbooks (OPS-01, OPS-02, OPS-03)

- **Onboarding:** DNS, add-client.sh, Nginx map line, reload, smoke test
- **Updates:** Upstream sync from iOfficeAI/AionUi, image rebuild, rolling restart
- **Backup & Restore:** Backup verification, restore procedure, volume recovery

---

*Last updated: 2026-03-27*
