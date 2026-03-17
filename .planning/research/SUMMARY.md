# Project Research Summary

**Project:** Diador — AionUi Multi-Tenant SaaS Deployment
**Domain:** Single-host Docker multi-tenant SaaS — Electron WebUI served via Nginx on EC2
**Researched:** 2026-03-17
**Confidence:** HIGH

## Executive Summary

Diador is a multi-tenant SaaS deployment of AionUi (an Electron desktop app) that runs each client as an isolated Docker container on a single EC2 instance, accessed via HTTPS subdomains (`client1.diador.ai`, etc.). The deployment model is well-understood: Nginx on the host handles TLS termination and subdomain-to-port routing via its `map` module, each container binds on a unique loopback port visible only to Nginx, and per-client named Docker volumes persist SQLite data across container restarts. This pattern scales cleanly from 3 to ~15 clients on a single `t3.xlarge` without any architectural changes.

The recommended approach is a dependency-driven build sequence: get a working Docker image first, then wire up per-client Compose stacks, then configure Nginx routing, then provision TLS, then write the operations tooling. Every layer depends on the one below it — Nginx cannot be tested until containers run, and TLS cannot be provisioned until Nginx is configured. The wildcard cert (`*.diador.ai`) via certbot DNS-01 + Route53 is the correct and only viable TLS approach for this setup, requiring an IAM role on the EC2 instance rather than access keys.

Three risks dominate. First, Electron headless deployment in Docker has several known gotchas that will cause instant failures if not anticipated: using `--headless` instead of `--ozone-platform=headless`, using Alpine Linux instead of `debian:bookworm-slim`, and missing `seccomp:unconfined`. Second, the existing codebase has a known reliability flaw — the `uncaughtException` handler is a no-op in production, making crashes invisible — that must be patched before any real client data is written. Third, Nginx's default 60-second proxy timeout will disconnect every WebSocket session at idle, which is a first-connection showstopper that must be explicitly configured away.

## Key Findings

### Recommended Stack

The stack is derived entirely from hard constraints: Electron 37 requires glibc (rules out Alpine), the app already exposes a WebUI on port 25808 (configurable via `AIONUI_PORT`), and wildcard subdomains require DNS-01 challenge (rules out HTTP-01 certbot). The Nginx `map` module eliminates per-client config blocks — adding a client is one line. The entire deployment fits on one EC2 Ubuntu 22.04 LTS host with Docker Compose v2.

**Core technologies:**
- `debian:bookworm-slim`: Docker base image — glibc required by Electron 37 and better-sqlite3; Alpine silently breaks both
- Electron 37 (pre-built deb): App runtime — unpack from `dist/*.deb`; no in-container recompilation
- Docker Compose v2: Container orchestration — one service per client; Compose v1 is EOL
- Nginx 1.18+ (host, not containerized): Reverse proxy + TLS — `map` module for zero-boilerplate subdomain routing; host-resident for direct loopback access
- certbot + certbot-dns-route53: Wildcard TLS — DNS-01 is the only mechanism that can issue `*.diador.ai`; IAM role provides Route53 access automatically
- Ubuntu 22.04 LTS on EC2: Host OS — Docker Engine 26 available, LTS supported to 2027

**Critical app-specific detail:** Pass `--webui --remote` to start the container; do NOT pass `--headless`. The app's `configureChromium.ts` automatically applies `--ozone-platform=headless --disable-gpu --no-sandbox` when `DISPLAY` is unset and `getuid() === 0`. Port is configured via `AIONUI_PORT` env var (default `25808`); `AIONUI_ALLOW_REMOTE=1` binds to `0.0.0.0` inside the container.

### Expected Features

All P1 features are low-complexity operational scripts and configuration. No novel product features are required — the goal is a reliable operations layer around the existing AionUi app.

**Must have (table stakes — v1):**
- Container health check (`HEALTHCHECK` in Dockerfile) — gating readiness and driving restart decisions
- `restart: unless-stopped` on all client services — critical given the known silent crash bug
- Client provisioning script — operator must add a client in under 5 minutes without editing 6 files by hand
- Client teardown script — cleanly removes container, volume, and Nginx entry without orphans
- Nightly named volume backup via cron — SQLite conversation history is irreplaceable client data
- Wildcard SSL cert with auto-renewal — expired cert locks all clients out simultaneously
- Port registry enforcement (`port-registry.env`) — port conflicts cause silent cross-client routing failures
- Operations runbook — onboarding, update, crash recovery, backup restore procedures

**Should have (v1.x — add after first 3 clients are stable 2+ weeks):**
- Per-client update script with health-gate — reduces blast radius on rolling AionUi image updates
- Disk usage alerting cron — nightly backups fill 100 GB EBS within months without rotation
- Backup rotation policy (7 daily / 4 weekly / 1 monthly)
- EC2 instance auto-recovery CloudWatch alarm — no-code hardware failure protection
- Nginx per-client access log — needed to answer basic "how often is client X using their instance" questions

**Defer (v2+ — not essential until 10+ clients):**
- Prometheus + cAdvisor + Grafana monitoring stack
- Centralized log aggregation (Loki/Papertrail)
- Automated backup validation (restore-to-temp)
- Client-facing status page

**Anti-features — explicitly out of scope:**
- Kubernetes/ECS (massive overhead for 3-5 clients)
- Self-service client portal (requires auth, billing, provisioning API)
- Horizontal auto-scaling (incompatible with SQLite named volume model)
- In-app update mechanism (Electron auto-update requires BrowserWindow; not applicable in WebUI mode)

### Architecture Approach

The architecture is a single EC2 host running Nginx + Docker. Each client is fully isolated: its own Docker container on its own user-defined bridge network, bound to a unique loopback port, backed by its own named volume. Nginx is the only component that touches multiple clients — via the `map` block mapping hostnames to loopback ports. Containers cannot reach each other (separate bridge networks). Data cannot cross clients (separate named volumes). TLS is terminated at Nginx using a single wildcard cert.

**Major components:**
1. **Nginx (host)** — TLS termination, subdomain-to-port routing via `map`, WebSocket upgrade headers, 86400s proxy timeouts; never containerized
2. **AionUi container (per client)** — Electron in WebUI mode; serves HTTP+WebSocket on internal port 25808; loopback-bound via `127.0.0.1:2580X:25808`
3. **Named volume (per client)** — persists SQLite DB, AI credentials, config at `/root/.config/AionUi`; survives container recreation and host reboots
4. **port-registry.env** — single source of truth for client-name to loopback-port mapping; both Nginx map and Compose .env derive from it
5. **certbot + Route53** — wildcard cert issuance and 90-day auto-renewal; IAM role on EC2 for keyless Route53 access
6. **Deploy scripts** — `onboard-client.sh`, `update-client.sh`, `update-all.sh` under `deploy/scripts/`

**Build dependency chain (must follow this order):**
```
Docker image → per-client Compose stack → multi-client orchestration → Nginx routing → TLS + DNS → EC2 provisioning → Operations runbooks
```

### Critical Pitfalls

1. **WebSocket 60-second disconnect** — Nginx's default `proxy_read_timeout` closes idle WebSocket connections at 60s. Fix: set `proxy_read_timeout 86400; proxy_send_timeout 86400; proxy_buffering off;` in every AionUi location block. Without `proxy_buffering off`, streaming AI responses arrive in bursts instead of token-by-token.

2. **Alpine / musl libc silently breaks Electron** — Electron 37 and better-sqlite3 are glibc-linked binaries. Alpine's musl libc causes immediate crashes with no useful error message. Use `debian:bookworm-slim` exclusively; treat the Dockerfile `FROM` line as a constraint, not an optimization target.

3. **seccomp blocks Electron renderer processes** — Docker's default seccomp profile blocks `clone3` and related syscalls that Chromium's zygote process requires. Electron exits within 2 seconds with no log output. Fix: add `security_opt: - seccomp:unconfined` to every client service in `docker-compose.yml`.

4. **Silent production crashes (uncaughtException no-op)** — `src/index.ts` explicitly no-ops the `uncaughtException` handler in production builds. Crashes are invisible: container stays running, WebUI freezes, no log output. This must be patched before any production client data is written. Fix: log to stderr and `process.exit(1)`; then `restart: unless-stopped` auto-recovers.

5. **Certbot wildcard renewal DNS propagation race** — Default propagation wait (45s) is sometimes insufficient. Route53 changes can take longer globally. IAM policy missing `route53:GetChange` causes silent failures. Fix: set `--dns-route53-propagation-seconds 120`, run renewal cron twice daily (not hourly), verify with `certbot renew --dry-run` before declaring setup complete.

6. **userData volume not mounted = data loss on container restart** — Without an explicit named volume mount for `/root/.config/AionUi`, every container restart destroys all client conversation history. Validate persistence (stop → restart → verify conversations) before writing any real client data.

## Implications for Roadmap

The architecture's dependency chain directly maps to a natural phase sequence. Each phase unblocks the next; no phase can be skipped.

### Phase 1: Docker Image
**Rationale:** Foundation of everything. Nginx cannot be tested without a running container; TLS is irrelevant without an accessible app. Most critical pitfalls live here and must be resolved before moving on.
**Delivers:** A working `debian:bookworm-slim` Docker image that launches AionUi in WebUI mode and passes a `docker run` smoke test
**Features addressed:** Container health check (HEALTHCHECK), restart policy
**Pitfalls to address:** Alpine/musl libc incompatibility, seccomp/clone3 crash, Electron `--headless` flag mistake, root user + no-sandbox, uncaughtException handler patch
**Research flag:** Standard patterns — well-documented. Skip `/gsd:research-phase`. All answers are in STACK.md and PITFALLS.md.

### Phase 2: Per-Client Docker Compose Stack
**Rationale:** With a working image, wire up the full per-client runtime: container + named volume + bridge network + loopback port binding. This is the unit that will be replicated per client.
**Delivers:** A single client (`client1`) running via Docker Compose with persistent data, isolated network, and loopback port binding; verified by stop/restart/data-persists test
**Features addressed:** Named volume backup prerequisite, port registry discipline, `restart: unless-stopped`, data volume mount
**Pitfalls to address:** userData volume not mounted, port registry drift, container ports exposed on 0.0.0.0, default docker0 bridge cross-tenant access
**Research flag:** Standard patterns. Skip `/gsd:research-phase`.

### Phase 3: Multi-Client Orchestration + Operations Scripts
**Rationale:** Generalize the single-client Compose stack into a replicable pattern. The provisioning script is the operational multiplier — it must be solid before onboarding any paying client.
**Delivers:** `onboard-client.sh` (end-to-end new client provisioning), `teardown-client.sh`, `port-registry.env` with allocation logic, per-client Compose templates under `/data/clients/<name>/`
**Features addressed:** Client provisioning script, client teardown script, port registry enforcement, Nginx reload automation
**Pitfalls to address:** Port registry drift, missing backup-before-teardown guard, provisioning without health-gate
**Research flag:** Standard patterns. Scripts are straightforward shell logic. Skip `/gsd:research-phase`.

### Phase 4: Nginx Configuration + Wildcard TLS
**Rationale:** Nginx and TLS must come after containers are running and ports are known. The wildcard cert must exist before any `*.diador.ai` subdomain is reachable. Nginx and certbot can be configured in parallel but both require the EC2 host to be provisioned.
**Delivers:** Nginx `map`-based routing for all client subdomains, `*.diador.ai` wildcard cert issued and auto-renewing, HTTPS end-to-end verified for all active clients
**Features addressed:** Wildcard SSL cert with auto-renewal, Nginx reload automation
**Pitfalls to address:** WebSocket 60-second timeout, `proxy_buffering off` for streaming, certbot DNS propagation race, Nginx wildcard cert mismatch, HTTP-01 vs DNS-01 confusion
**Research flag:** Certbot DNS-01 IAM permissions need careful verification during implementation. All patterns are in STACK.md and PITFALLS.md — consider a quick `/gsd:research-phase` only if IAM role setup is unclear.

### Phase 5: EC2 Production Provisioning
**Rationale:** Tie all components together on the actual production host. Security hardening and EC2-specific configuration (security groups, EBS layout, IAM role) belong here.
**Delivers:** Production EC2 with all components running: Docker + Nginx + certbot + all client containers; security group locking loopback ports, data EBS at `/data`, IAM role for Route53
**Features addressed:** EC2 instance auto-recovery CloudWatch alarm (v1.x), disk layout, security group hardening
**Pitfalls to address:** EC2 security group exposing loopback ports, SQLite on root EBS instead of data EBS, IAM wildcard Route53 permissions, CDP remote debugging port exposure
**Research flag:** Standard EC2 patterns. Skip `/gsd:research-phase`.

### Phase 6: Operations Runbook + Backup
**Rationale:** Operational tooling and documentation are the last dependency — they reference all preceding components. Backup must be configured before any paying client is onboarded.
**Delivers:** Operations runbook (onboarding, update, crash recovery, backup restore), nightly backup cron for all named volumes, `update-client.sh` and `update-all.sh` scripts
**Features addressed:** Operations runbook, nightly named volume backup, log access per client
**Pitfalls to address:** Data loss on container restart (backup cron as safety net), teardown without backup guard
**Research flag:** Standard patterns. Skip `/gsd:research-phase`.

### Phase 7: Observability + Reliability Hardening (v1.x)
**Rationale:** Add after first 3 clients are stable for 2+ weeks. Justified by operational pain points, not by speculative need.
**Delivers:** Per-client update script with health-gate, disk usage alerting, backup rotation policy, EC2 auto-recovery alarm, Nginx per-client access logs
**Features addressed:** All v1.x "Should Have" features from FEATURES.md
**Research flag:** Standard patterns. Skip `/gsd:research-phase`.

### Phase Ordering Rationale

- **Image before Compose:** A Compose stack cannot be tested without a working image. Every pitfall in Phase 1 will manifest silently — find them with `docker run` smoke tests before introducing Compose complexity.
- **Single client before multi-client scripts:** Validate the per-client model manually first; then automate what's been validated. Don't automate unknowns.
- **Nginx after containers:** The Nginx `map` block requires known ports; ports are assigned during Compose stack creation. Test order: `docker run` → `docker compose up` → `curl localhost:25801` → wire Nginx.
- **TLS last in routing stack:** The wildcard cert can be issued independently but cannot be validated end-to-end until Nginx is routing correctly. Issue cert in Phase 4, verify in same phase.
- **Operations runbook last:** Documents the complete system; cannot be complete until all components exist.

### Research Flags

Phases needing deeper research during planning:
- **Phase 4 (Nginx + TLS):** IAM policy for certbot-dns-route53 has specific permission requirements (`route53:GetChange` is commonly omitted). Verify exact policy during implementation.

Phases with standard, well-documented patterns (skip `/gsd:research-phase`):
- **Phase 1 (Docker Image):** All Electron headless Docker patterns are fully documented in STACK.md and PITFALLS.md
- **Phase 2 (Compose Stack):** Standard Docker Compose patterns; all specifics in ARCHITECTURE.md
- **Phase 3 (Orchestration Scripts):** Shell scripting; no research needed
- **Phase 5 (EC2 Provisioning):** Standard Ubuntu + Docker setup
- **Phase 6 (Runbook + Backup):** Standard Docker volume backup patterns
- **Phase 7 (Observability):** Standard CloudWatch/cron patterns

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Core decisions (debian:bookworm-slim, Nginx map, DNS-01) verified from codebase source (`configureChromium.ts`, `constants.ts`), PROJECT.md, and official docs |
| Features | MEDIUM | Based on training knowledge of comparable self-hosted SaaS patterns; WebSearch unavailable to verify 2026 current practices; all recommendations align with PROJECT.md constraints |
| Architecture | HIGH | Docker networking, Nginx WebSocket proxy, named volumes all verified against official docs; component boundaries verified from codebase analysis |
| Pitfalls | HIGH | Most critical pitfalls verified from codebase (`src/index.ts` uncaughtException, `configureChromium.ts` flag logic, CONCERNS.md); Nginx and certbot pitfalls from official docs |

**Overall confidence:** HIGH

### Gaps to Address

- **Certbot package source:** apt vs snap on Ubuntu 22.04 — both work, but snap is the official certbot recommendation on Ubuntu 22.04. STACK.md uses apt (EFF PPA). Verify during Phase 4 that the systemd renewal timer works correctly for the chosen install method.
- **Electron startup time:** Research estimates 3-5 seconds to WebUI readiness. The actual startup time determines the health check interval and the provisioning script's wait timeout. Measure against the actual built image in Phase 1.
- **Memory baseline per container:** ARCHITECTURE.md estimates 300-600 MB per AionUi instance on t3.xlarge. Measure the actual resident memory of the production image in Phase 2 to confirm EC2 sizing for 3-5 clients.
- **uncaughtException handler patch:** This requires modifying `src/index.ts` in the AionUi codebase before building the production Docker image. Confirm this is within scope and that the change is acceptable for the upstream fork.

## Sources

### Primary (HIGH confidence)
- `src/utils/configureChromium.ts` — Electron headless flags, `--ozone-platform=headless`, `--no-sandbox` root detection
- `src/webserver/config/constants.ts` — Default port 25808, `DEFAULT_HOST`, `REMOTE_HOST`
- `src/index.ts` — `AIONUI_PORT`/`AIONUI_ALLOW_REMOTE` env var names, `--webui`/`--remote` switches, uncaughtException no-op
- `.planning/PROJECT.md` — debian:bookworm-slim confirmation, Nginx map pattern, DNS-01 Route53 decision, WebSocket timeout requirement
- `.planning/codebase/CONCERNS.md` — security and reliability audit; iframe sandbox issue, uncaughtException no-op confirmation
- Nginx official docs (ngx_http_map_module, ngx_http_proxy_module, WebSocket proxying) — map directive, proxy timeouts, WebSocket upgrade headers
- Docker official docs (bridge networking, named volumes, Compose ports, seccomp) — isolation properties, volume persistence, loopback binding

### Secondary (MEDIUM confidence)
- certbot / eff-certbot.readthedocs.io — DNS-01 propagation timing, renewal automation, rate limits
- Docker seccomp docs — default profile syscall restrictions, clone3 behavior
- Let's Encrypt rate limits documentation — 5 failed validations per hour per hostname policy
- General multi-tenant SaaS operational patterns (Gitea, Outline, Plausible) — operational baseline for feature prioritization

---
*Research completed: 2026-03-17*
*Ready for roadmap: yes*
