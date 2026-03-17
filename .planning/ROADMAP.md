# Roadmap: Diador — AionUi SaaS Deployment

## Overview

Three phases take the project from codebase to live multi-tenant SaaS. Phase 1 produces a branded, deployable Docker image. Phase 2 wires up per-client Compose stacks, Nginx routing, and wildcard TLS into a verified end-to-end path. Phase 3 provisions the production EC2, brings three clients live, and establishes the operational runbooks that make ongoing management safe.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Container Foundation** - Branded, deployable Docker image with working headless WebUI
- [ ] **Phase 2: Orchestration and Routing** - Multi-client Compose stacks, Nginx subdomain routing, and wildcard TLS end-to-end
- [ ] **Phase 3: Production Deployment and Operations** - EC2 provisioned, three clients live, operational runbooks complete

## Phase Details

### Phase 1: Container Foundation
**Goal**: A branded Diador Docker image runs AionUi in headless WebUI mode and passes smoke tests
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, BRAND-01, BRAND-02, BRAND-03, BRAND-04
**Success Criteria** (what must be TRUE):
  1. `docker run` launches the image and the WebUI is reachable at `localhost:25808` without Xvfb or a physical display
  2. Stopping and restarting the container preserves all data in the named volume (conversation history survives)
  3. Container health check reports healthy within 30 seconds of start; container restarts automatically after a simulated crash
  4. All UI surfaces (title bar, about modal, window title, app icons) show "Diador" with no "AionUi" references remaining
  5. `node scripts/check-i18n.js` exits 0 and the `NOTICE` file exists at repo root after branding commit
**Plans**: TBD

### Phase 2: Orchestration and Routing
**Goal**: Multiple isolated client containers are reachable at their `*.diador.ai` subdomains over HTTPS with persistent WebSocket sessions
**Depends on**: Phase 1
**Requirements**: ORCH-01, ORCH-02, ORCH-03, ORCH-04, ROUTE-01, ROUTE-02, ROUTE-03, ROUTE-04
**Success Criteria** (what must be TRUE):
  1. `add-client.sh <name>` provisions a new client end-to-end (volume, .env, Compose service, port registry line) without manual file editing
  2. `remove-client.sh <name>` tears down a client cleanly after taking a backup — no orphaned volumes or registry entries remain
  3. `clientN.diador.ai` resolves over HTTPS and the browser shows a valid wildcard cert (not a security warning)
  4. An AI chat session stays connected for more than 60 seconds of idle time without dropping the WebSocket
  5. `certbot renew --dry-run` exits 0 and a cron job is configured to run renewal twice daily
**Plans**: TBD

### Phase 3: Production Deployment and Operations
**Goal**: Three paying-client containers run on the production EC2 and Diador can onboard, update, and recover clients from runbooks alone
**Depends on**: Phase 2
**Requirements**: DEPLOY-01, DEPLOY-02, DEPLOY-03, DEPLOY-04, OPS-01, OPS-02, OPS-03
**Success Criteria** (what must be TRUE):
  1. `client1.diador.ai`, `client2.diador.ai`, and `client3.diador.ai` are each reachable over HTTPS and serve an isolated Diador AI session
  2. Nightly backup cron runs and produces timestamped volume archives under `/opt/backups/diador/` for all active clients
  3. The onboarding runbook can be followed by a new operator to add a fourth client without involving the original author
  4. The update runbook describes the full upstream sync + image rebuild + rolling restart procedure with verification steps
  5. A backup can be restored to a fresh container following the restore runbook with no data loss
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Container Foundation | 0/TBD | Not started | - |
| 2. Orchestration and Routing | 0/TBD | Not started | - |
| 3. Production Deployment and Operations | 0/TBD | Not started | - |
