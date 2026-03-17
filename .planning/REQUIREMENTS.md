# Requirements: Diador — AionUi SaaS Deployment

**Defined:** 2026-03-17
**Core Value:** A client can access their own Diador AI assistant at a personal subdomain — fully isolated, persistent, and accessible from any browser — without installation.

## v1 Requirements

### Infrastructure

- [ ] **INFRA-01**: Docker image builds and runs AionUi in headless WebUI mode (debian:bookworm-slim, non-root user, seccomp:unconfined or equivalent)
- [ ] **INFRA-02**: Named Docker volume persists client userData (`~/.config/AionUi/`) across container restarts
- [ ] **INFRA-03**: Container has working health check and `restart: unless-stopped` policy
- [ ] **INFRA-04**: uncaughtException handler patched so crashes are not silently swallowed

### Orchestration

- [ ] **ORCH-01**: Docker Compose config manages per-client container with isolated bridge network and loopback port binding
- [ ] **ORCH-02**: `port-registry.env` is the authoritative source of truth for client→port mappings
- [ ] **ORCH-03**: `add-client.sh` script provisions a new client (creates volume, .env, Compose service entry, port registry line)
- [ ] **ORCH-04**: `remove-client.sh` safely tears down a client (backup runs first, then container/volume/registry removed)

### Routing

- [ ] **ROUTE-01**: Nginx routes `*.diador.ai` subdomains to correct client containers via `map` module (one server block)
- [ ] **ROUTE-02**: WebSocket proxying works without timeout (`proxy_read_timeout 86400`, `Upgrade`/`Connection` headers set)
- [ ] **ROUTE-03**: Wildcard TLS cert for `*.diador.ai` issued via certbot DNS-01 challenge (certbot-dns-route53, IAM role on EC2)
- [ ] **ROUTE-04**: TLS cert auto-renews via cron with post-hook nginx reload; dry-run passes before production

### Branding

- [ ] **BRAND-01**: All 54 AionUi → Diador touchpoints updated (package.json, electron-builder.yml, icons, HTML titles, i18n files, Titlebar, AboutModal, CSS vars, ClientFactory HTTP-Referer)
- [ ] **BRAND-02**: All branding changes land in one atomic commit (`chore(brand): rebrand AionUi → Diador`) for clean upstream rebasing
- [ ] **BRAND-03**: `NOTICE` file created at repo root (Apache 2.0 compliance, attributing original AionUi authors)
- [ ] **BRAND-04**: i18n validation passes after branding changes (`node scripts/check-i18n.js` exits 0)

### Deployment

- [ ] **DEPLOY-01**: EC2 t3.xlarge provisioned (Ubuntu 22.04, 30 GB root + 100 GB data EBS, nginx + docker + certbot installed)
- [ ] **DEPLOY-02**: Docker image built and available on EC2 (built on host or pulled from registry)
- [ ] **DEPLOY-03**: 3 client containers running (client1, client2, client3) — each accessible at `clientN.diador.ai` via HTTPS
- [ ] **DEPLOY-04**: Nightly backup cron running (named volume archives to `/opt/backups/diador/`)

### Operations

- [ ] **OPS-01**: Client onboarding runbook documented (DNS, add-client.sh, Nginx map line, reload, smoke test)
- [ ] **OPS-02**: Update procedure runbook documented (upstream sync from iOfficeAI/AionUi, image rebuild, rolling restart)
- [ ] **OPS-03**: Backup and restore runbook documented (backup verification, restore procedure, volume recovery)

## v2 Requirements

### Observability

- **OBS-01**: Disk usage alerting (cron script emails/alerts when EBS >80% full)
- **OBS-02**: Container health dashboard (cAdvisor or Prometheus + Grafana)
- **OBS-03**: Per-client access logs with structured rotation

### Reliability

- **REL-01**: Health-gated update script (checks container health before proceeding to next)
- **REL-02**: EC2 auto-recovery alarm (CloudWatch → SNS on system status check failure)
- **REL-03**: Backup rotation with S3 offsite copy

### Scaling

- **SCALE-01**: Migration path to ECS Fargate (runbook, not implementation)
- **SCALE-02**: Multi-host Nginx routing (for when single EC2 is insufficient)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Kubernetes / ECS | Single-EC2 model sufficient for v1 (3-5 clients); architectural mismatch with SQLite |
| Self-service client portal | Manual onboarding is sufficient for v1 client count |
| Billing/payment integration | Client contracts handled externally |
| Mobile app | Web-first deployment only |
| Multi-region deployment | Single AWS region sufficient for v1 |
| Real-time monitoring dashboard | v2 concern; disk cron sufficient for v1 |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 1 | Pending |
| INFRA-04 | Phase 1 | Pending |
| BRAND-01 | Phase 1 | Pending |
| BRAND-02 | Phase 1 | Pending |
| BRAND-03 | Phase 1 | Pending |
| BRAND-04 | Phase 1 | Pending |
| ORCH-01 | Phase 2 | Pending |
| ORCH-02 | Phase 2 | Pending |
| ORCH-03 | Phase 2 | Pending |
| ORCH-04 | Phase 2 | Pending |
| ROUTE-01 | Phase 2 | Pending |
| ROUTE-02 | Phase 2 | Pending |
| ROUTE-03 | Phase 2 | Pending |
| ROUTE-04 | Phase 2 | Pending |
| DEPLOY-01 | Phase 3 | Pending |
| DEPLOY-02 | Phase 3 | Pending |
| DEPLOY-03 | Phase 3 | Pending |
| DEPLOY-04 | Phase 3 | Pending |
| OPS-01 | Phase 3 | Pending |
| OPS-02 | Phase 3 | Pending |
| OPS-03 | Phase 3 | Pending |

**Coverage:**
- v1 requirements: 23 total
- Mapped to phases: 23
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-17*
*Last updated: 2026-03-17 after roadmap creation (coarse granularity: 3 phases)*
