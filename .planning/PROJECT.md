# Diador — AionUi SaaS Deployment

## What This Is

A branded SaaS deployment of AionUi (open-source Electron AI chat app, Apache 2.0 licensed). Each client gets their own isolated instance running at `clientname.diador.ai`, served from a single EC2 host with per-client Docker containers and Nginx wildcard SSL routing. The product is operated by Diador Technology and positioned as a custom AI automation platform for business clients.

## Core Value

A client can access their own Diador AI assistant at their personal subdomain — fully isolated, persistent, and accessible from any browser — without any installation.

## Requirements

### Validated

- ✓ AionUi headless WebUI mode works without Xvfb — existing
- ✓ `debian:bookworm-slim` confirmed compatible with Electron + better-sqlite3 — existing
- ✓ Nginx `map` module routing pattern designed — existing
- ✓ 54 branding touchpoints catalogued — existing
- ✓ Codebase explored and mapped — existing

### Active

- [ ] Docker container builds and runs AionUi in headless WebUI mode
- [ ] Multi-client Docker Compose orchestration with isolated per-client networks
- [ ] Nginx routes `*.diador.ai` subdomains to correct client containers via wildcard SSL
- [ ] All 54 AionUi branding touchpoints updated to Diador in one atomic commit
- [ ] EC2 instance provisioned with 3 clients running (client1, client2, client3)
- [ ] Operations runbooks written for onboarding, updates, and upstream sync

### Out of Scope

- Mobile app — web-first deployment only
- Kubernetes / ECS — single-EC2 model sufficient for v1 (3-5 clients)
- Multi-region — single AWS region for v1
- Billing/payment integration — client contracts handled externally

## Context

- **Repo:** `aionui-custom` — fork of [iOfficeAI/AionUi](https://github.com/iOfficeAI/AionUi) (Apache 2.0)
- **Stack:** Electron 37, React 19, TypeScript 5.8, Bun, electron-vite, better-sqlite3
- **WebUI mode:** `electron out/main/index.js --webui --remote` (app auto-sets Ozone headless flags; `--headless` causes auto-exit; `--no-sandbox` is automatic when running as root)
- **Container runtime:** `debian:bookworm-slim` (glibc required — never Alpine)
- **userData path:** `~/.config/AionUi/` on Linux (mount as named volume per client)
- **Target EC2:** t3.xlarge (4 vCPU / 16 GB), Ubuntu 22.04, 30 GB root + 100 GB data EBS
- **DNS:** `*.diador.ai` wildcard A record → EC2 public IP
- **SSL:** Let's Encrypt wildcard cert via certbot DNS-01 (Route53 plugin, IAM role on EC2)

## Constraints

- **License:** Apache 2.0 — must include NOTICE file attributing original AionUi authors
- **Branding atomicity:** All 54 AionUi→Diador changes must land in ONE commit for clean upstream rebasing
- **No Xvfb:** Launch flags must always include `--disable-gpu --headless` (no virtual display)
- **WebSocket timeout:** Nginx `proxy_read_timeout 86400` is mandatory — without it sessions drop every 60s
- **Port allocation:** Each client gets a loopback port in the 2580X range (port-registry.env is source of truth)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Headless mode via `--disable-gpu --headless` | Electron 37 WebUI never opens BrowserWindow; Xvfb adds 30MB unnecessary X11 libs | ✓ Confirmed |
| `debian:bookworm-slim` runtime | Alpine musl libc breaks Electron + better-sqlite3 silently | ✓ Confirmed |
| Nginx `map` module routing | One server block, adding client = one line, zero duplicated blocks | ✓ Confirmed |
| DNS-01 wildcard SSL (certbot + Route53) | HTTP-01 cannot issue `*.diador.ai` wildcards | ✓ Confirmed |
| All branding in one atomic commit | Upstream rebase conflicts are trivially resolvable when all brand changes are isolated | ✓ Confirmed |
| Single EC2, named volumes per client | Simplest operational model for v1 (3-5 clients); scale to ECS later if needed | — Pending |

---
*Last updated: 2026-03-17 after initialization*
