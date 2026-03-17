# Stack Research

**Domain:** Electron SaaS deployment — headless Docker + multi-tenant Nginx + EC2
**Researched:** 2026-03-17
**Confidence:** HIGH (core decisions verified from codebase source code and PROJECT.md)

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `debian:bookworm-slim` | bookworm (Debian 12) | Docker base image | glibc required by Electron's Chromium and better-sqlite3 native addon. Alpine's musl libc breaks both silently at runtime — no error, just crash. Bookworm-slim is the smallest glibc image that ships with the required shared libraries. |
| Electron (prebuilt) | 37.x (matches repo) | App runtime inside container | No recompilation needed. The Linux `deb` output from `electron-builder` is self-contained. We unpack the deb, not rebuild from source. |
| Docker + Docker Compose | Docker 26+ / Compose v2 | Container orchestration | One container per client. Compose v2 (`docker compose` not `docker-compose`) is the current standard; v1 is deprecated and removed from Docker Desktop. |
| Nginx | 1.26.x (stable) | Reverse proxy + TLS termination | `map` module for zero-boilerplate subdomain routing. `proxy_pass` to loopback ports. Only one config block needed regardless of client count. |
| Certbot + certbot-dns-route53 | certbot 2.x, dns-route53 plugin | Wildcard TLS certificate | DNS-01 challenge is the only ACME challenge type that can issue `*.diador.ai` wildcard certs. HTTP-01 cannot. Route53 plugin automates TXT record creation/deletion on AWS. |
| Ubuntu 22.04 LTS (EC2) | 22.04 (Jammy) | EC2 host OS | LTS supported until 2027. Docker Engine 26 packages available from the official Docker apt repo. Ubuntu 22.04 is the most tested EC2 AMI for Docker workloads. |

### Supporting Libraries / Tools

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `python3-certbot-dns-route53` | matches certbot version | Route53 DNS plugin for certbot | When issuing or renewing `*.diador.ai`. Install via `apt` on Ubuntu 22.04 (preferred over pip for system-managed renewal). |
| `aws-cli` v2 | 2.x | EC2 IAM role verification, manual Route53 inspection | Debugging cert issuance and verifying IAM permissions on the EC2 instance role. |
| `docker-compose-plugin` | Compose v2 | Compose v2 via `apt` on Ubuntu | Installed alongside Docker Engine — use this, not the legacy `docker-compose` binary. |
| `nginx` (apt) | 1.18+ (Ubuntu LTS) or 1.26 (nginx stable PPA) | Reverse proxy | Use the `nginx` stable PPA for Nginx 1.26 if you need `map` + WebSocket keepalive without backporting. Ubuntu 22.04's default nginx (1.18) supports all required features. Either is acceptable. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `electron-builder` (Linux deb target) | Build the deployable Linux artifact | `bun run build:linux` or similar; output is `dist/*.deb` which gets unpacked in Dockerfile. |
| `bun` (build host) | Build tool for app compilation | Only needed on build machine, not in the container. Container runs the compiled output. |
| AWS EC2 Instance Role (IAM) | Grants certbot-dns-route53 access to Route53 | Attach role with `route53:ListHostedZones`, `route53:GetChange`, `route53:ChangeResourceRecordSets` on the HostedZone for `diador.ai`. No access keys needed — role-based auth works automatically inside EC2. |

---

## Critical Finding: Electron Headless Launch Flags

**SOURCE: `src/utils/configureChromium.ts` lines 24-31 — verified from codebase, HIGH confidence.**

The `--headless` CLI flag is **WRONG** for Docker deployment. It triggers Chromium's browser-automation headless mode, which causes Electron to exit immediately after startup.

The correct approach, already implemented in the app:

```bash
# CORRECT: app code handles this automatically when --webui flag is set
# and DISPLAY is not set (which is always true inside Docker)
electron out/main/index.js --webui --remote --no-sandbox
```

The app's `configureChromium.ts` automatically appends these flags when `--webui` is passed and `process.platform === 'linux'` and `!process.env.DISPLAY`:

```
--ozone-platform=headless    # Ozone display backend, not browser automation mode
--disable-gpu                # No GPU in container
--disable-software-rasterizer
--no-sandbox                 # Required when running as root (Docker default)
```

**Do NOT** pass `--headless` on the CLI. The app detects the environment and sets the right flags internally. The minimal launch command in Docker is:

```bash
electron out/main/index.js --webui --remote
```

The `--no-sandbox` is added automatically when `getuid() === 0` (Docker default). `--disable-gpu` and `--ozone-platform=headless` are added when `DISPLAY` is unset (always true in container).

**Port configuration:** The app reads `AIONUI_PORT` env var before all other sources. Set this in each container's environment instead of passing `--port` flag. `AIONUI_ALLOW_REMOTE=1` or `--remote` switch triggers binding on `0.0.0.0`.

---

## Nginx Routing Pattern

**SOURCE: Nginx official docs (ngx_http_map_module, ngx_http_upstream_module) — verified, HIGH confidence.**

Use the `map` module to translate the incoming hostname into a backend port. One `server` block handles all subdomains:

```nginx
# /etc/nginx/conf.d/diador.conf

map $http_host $client_port {
    hostnames;
    default          0;
    client1.diador.ai 25801;
    client2.diador.ai 25802;
    client3.diador.ai 25803;
}

server {
    listen 443 ssl;
    server_name *.diador.ai;

    ssl_certificate     /etc/letsencrypt/live/diador.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/diador.ai/privkey.pem;

    # Required: WebSocket sessions drop every 60s without this
    proxy_read_timeout 86400;
    proxy_send_timeout 86400;

    location / {
        if ($client_port = 0) { return 404; }
        proxy_pass http://127.0.0.1:$client_port;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

server {
    listen 80;
    server_name *.diador.ai;
    return 301 https://$host$request_uri;
}
```

**Adding a new client:** One line in the `map` block. No new server blocks, no reload restart.

---

## Let's Encrypt Wildcard Certificate on EC2

**SOURCE: certbot readthedocs + certbot-dns-route53 docs — MEDIUM confidence (version numbers need runtime verification).**

### IAM Permissions Required

The EC2 instance role must have this inline policy on the `diador.ai` hosted zone:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "route53:ListHostedZones",
        "route53:GetChange"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": "route53:ChangeResourceRecordSets",
      "Resource": "arn:aws:route53:::hostedzone/<HOSTED_ZONE_ID>"
    }
  ]
}
```

No access keys in files. The plugin picks up credentials from the EC2 instance metadata service automatically.

### Issuance Command

```bash
# Install on Ubuntu 22.04
apt install -y certbot python3-certbot-dns-route53

# Issue wildcard cert (DNS-01 challenge)
certbot certonly \
  --dns-route53 \
  --dns-route53-propagation-seconds 30 \
  -d "diador.ai" \
  -d "*.diador.ai" \
  --email ops@diador.ai \
  --agree-tos \
  --non-interactive
```

Certbot stores certificates at `/etc/letsencrypt/live/diador.ai/`. Auto-renewal is handled by the systemd timer (`certbot.timer`) installed with the package. Add a renewal hook to reload Nginx after renewal:

```bash
# /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
#!/bin/bash
systemctl reload nginx
```

---

## Docker Compose Pattern

```yaml
# docker-compose.yml (fragment)
services:
  client1:
    build: .
    container_name: diador-client1
    restart: unless-stopped
    ports:
      - "127.0.0.1:25801:25808"   # loopback-only; Nginx proxies from outside
    environment:
      - AIONUI_PORT=25808          # internal container port (always 25808)
      - AIONUI_ALLOW_REMOTE=1      # bind 0.0.0.0 inside container
      - JWT_SECRET=${CLIENT1_JWT_SECRET}
    volumes:
      - client1-data:/root/.config/AionUi
    networks:
      - client1-net

  client2:
    build: .
    container_name: diador-client2
    restart: unless-stopped
    ports:
      - "127.0.0.1:25802:25808"
    environment:
      - AIONUI_PORT=25808
      - AIONUI_ALLOW_REMOTE=1
      - JWT_SECRET=${CLIENT2_JWT_SECRET}
    volumes:
      - client2-data:/root/.config/AionUi
    networks:
      - client2-net

volumes:
  client1-data:
  client2-data:

networks:
  client1-net:
  client2-net:
```

**Key design decisions:**
- Port `25808` is always the internal container port (matches `SERVER_CONFIG.DEFAULT_PORT` from source code)
- External port is in the `2580X` range (`25801`, `25802`, ...) — matches Nginx `map` block
- Volumes are named (not bind-mounts) for portability
- Per-client isolated networks prevent cross-container communication
- `ports` uses `127.0.0.1:` prefix so the container port is NOT exposed to `0.0.0.0` on the host — Nginx is the only ingress

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| `debian:bookworm-slim` | `node:22-bookworm-slim` | Only if building from source inside the container (adds ~200MB Node.js). For running pre-built Electron binary, base debian is smaller. |
| `debian:bookworm-slim` | `ubuntu:22.04` | If you need snap/apt ecosystem consistency with the EC2 host. Adds ~30MB but otherwise equivalent for Electron. Not worth it. |
| `debian:bookworm-slim` | Alpine Linux | NEVER for Electron. musl libc breaks Electron and better-sqlite3 silently. |
| Certbot `apt` package | Certbot snap | Snap is the recommended install on Ubuntu 22.04, but `apt` from the EFF PPA works fine and is simpler in EC2 automation scripts. Either works; snap has slightly faster renewal. |
| Nginx `map` routing | Per-client `server` blocks | Use per-client blocks only if you need per-client rate limits or access control at the Nginx level. For basic routing, `map` is strictly better. |
| EC2 instance IAM role | AWS access keys in `.env` | Never use access keys on EC2. Instance roles are automatic, rotate without action, and can't be leaked in config files. |
| Docker Compose v2 | Docker Compose v1 (`docker-compose`) | Compose v1 is EOL (May 2023). No new features, no security patches. Use `docker compose` (v2 plugin). |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `--headless` Electron flag | Triggers Chromium browser-automation mode; process exits immediately after launch. Source: `src/utils/configureChromium.ts:24`. | `--webui --remote` — the app auto-applies `--ozone-platform=headless` when DISPLAY is unset |
| Alpine Linux as base image | musl libc silently breaks Electron binary loading and better-sqlite3 native addon. No error message — just a crash. Confirmed in PROJECT.md. | `debian:bookworm-slim` |
| Xvfb (X virtual framebuffer) | Adds 30MB of X11 libraries for zero benefit. Electron 37 WebUI mode never opens a BrowserWindow. | `--ozone-platform=headless` (applied automatically) |
| HTTP-01 ACME challenge | Cannot issue wildcard certificates (`*.diador.ai`). HTTP-01 only works for exact domain names. | DNS-01 with `certbot-dns-route53` |
| Binding Docker port to `0.0.0.0` on host | Exposes the container port to the public internet, bypassing Nginx auth layer. | `ports: "127.0.0.1:2580X:25808"` — loopback-only host binding |
| `docker-compose` (v1 binary) | EOL May 2023, not maintained, not in Ubuntu 24.04. | `docker compose` (v2 plugin via `docker-compose-plugin` apt package) |
| Let's Encrypt HTTP-01 wildcard attempt | Will fail silently or with confusing "authorization failed" errors. Not a misconfiguration you can debug — it's a protocol limitation. | DNS-01 only for wildcard |
| Running Nginx as container | Adds networking complexity (container-to-container routing vs. loopback). For single-EC2 model, host Nginx is simpler. | Nginx installed directly on EC2 host |

---

## Stack Patterns by Variant

**If running as non-root inside Docker:**
- The `--no-sandbox` flag is NOT automatically added by `configureChromium.ts` (it checks `getuid() === 0`)
- Use `USER nonroot` in Dockerfile and add `--no-sandbox` explicitly in the CMD, OR run as root (simpler for v1)
- Running as root is acceptable in an isolated, single-tenant container

**If adding a 4th+ client:**
- Add one line to the Nginx `map` block: `client4.diador.ai 25804;`
- Add one `docker-compose.yml` service block with port `25804`
- No SSL work required (wildcard cert covers all subdomains)
- No Nginx reload required (map changes need `nginx -s reload`)

**If scaling beyond single EC2:**
- Swap Nginx `map` for AWS ALB target groups (one target group per client)
- Swap named volumes for EFS mount points per client
- Keep certbot/Route53 setup unchanged — wildcard cert still works
- This is explicitly out of scope for v1

---

## Version Compatibility

| Package | Compatible With | Notes |
|---------|-----------------|-------|
| Electron 37 | `debian:bookworm-slim` (glibc 2.36) | Electron 37 requires glibc >= 2.17. Bookworm ships glibc 2.36. Confirmed compatible in PROJECT.md. |
| `better-sqlite3@12.x` | `debian:bookworm-slim` | Native addon requires glibc. Must be prebuilt for linux/x64 — `electron-builder` handles this via `extraResources`. |
| `certbot 2.x` + `python3-certbot-dns-route53` | Ubuntu 22.04 `apt` | Both available from standard Ubuntu repos. Use `python3-certbot-dns-route53` not the pip package on Ubuntu to get proper systemd timer integration. |
| Nginx 1.18 (Ubuntu default) | `map` module + WebSocket proxy | The `map` module is compiled in by default on all Nginx distributions. WebSocket proxy (`proxy_set_header Upgrade`) supported since 1.3.13. Both features are available in Ubuntu 22.04's default nginx. |
| Docker Compose v2 | Docker Engine 26 | Compose v2 ships as a plugin with Docker Engine. Use `docker compose` not `docker-compose`. |

---

## Sources

- `src/utils/configureChromium.ts` (codebase) — Electron headless flags, `--ozone-platform=headless` vs `--headless` distinction, `--no-sandbox` root check. HIGH confidence.
- `src/webserver/config/constants.ts` (codebase) — Default port `25808`, `DEFAULT_HOST`, `REMOTE_HOST`. HIGH confidence.
- `src/index.ts` (codebase) — `AIONUI_PORT`, `AIONUI_ALLOW_REMOTE` env var names, `--webui`/`--remote` switch detection. HIGH confidence.
- `.planning/PROJECT.md` — `debian:bookworm-slim` confirmation, Nginx `map` pattern design, DNS-01 Route53 decision, port-registry.env convention, WebSocket timeout requirement. HIGH confidence.
- Nginx official docs (`ngx_http_map_module`, `ngx_http_upstream_module`) — `map` directive syntax, `hostnames` parameter, matching priority. HIGH confidence, verified via WebFetch.
- certbot readthedocs (eff-certbot.readthedocs.io) — DNS-01 plugin confirmation, certbot-dns-route53 package reference. MEDIUM confidence (version numbers not pinned from official source).
- Training data — IAM permission set for Route53 DNS challenge, Docker Compose port binding syntax, Nginx WebSocket proxy headers. MEDIUM confidence (standard patterns, widely documented).

---
*Stack research for: Diador — Electron SaaS deployment (Docker + Nginx + EC2)*
*Researched: 2026-03-17*
