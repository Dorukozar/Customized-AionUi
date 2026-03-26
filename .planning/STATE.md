# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** A client can access their own Diador AI assistant at a personal subdomain — fully isolated, persistent, and accessible from any browser — without installation.
**Current focus:** Phase 2 — Orchestration & Routing (COMPLETE) → Ready for Phase 3

## Current Position

Phase: 2 of 3 (Orchestration & Routing) — COMPLETE
Plan: All Phase 1 + Phase 2 requirements fulfilled
Status: Phase 2 done, ready to start Phase 3 (Production Deployment & Operations)
Last activity: 2026-03-26 — Phase 2 fully implemented and verified

Progress: [██████████] 100%

## Phase 1 Completion Summary

### Commits (3, on main, not yet pushed to origin as of session end)

1. `26e608ae` — `fix(main): log uncaughtException to stderr and exit in production`
   - Patched `src/index.ts` — production uncaughtException handler now logs to stderr and calls `process.exit(1)` so Docker restart policy can recover
   - Dev-mode behavior unchanged

2. `34c1a3b2` — `feat(infra): add Docker infrastructure for headless WebUI`
   - `Dockerfile` — debian:bookworm-slim, Node.js 22 LTS, bun, Electron binary download, native module rebuild, electron-vite build
   - `.dockerignore` — excludes node_modules, .git, dist, out, .planning, tests, etc.
   - `docker-compose.yml` — single service with named volume, seccomp:unconfined, restart:unless-stopped, health check

3. `ddf88b51` — `chore(brand): rebrand AionUi to Diador`
   - 40 files changed (39 modified + 1 new NOTICE file)
   - All user-facing "AionUi" → "Diador" across i18n (6 locales), components, configs, HTTP headers
   - NOTICE file for Apache 2.0 compliance
   - Internal identifiers (localStorage keys, cookies, env vars, IPC channels) intentionally unchanged

### Requirements Fulfilled

| Requirement | Description | Verification |
|-------------|-------------|-------------|
| INFRA-01 | Docker image builds and runs headless WebUI | docker compose build + curl localhost:25808 → HTTP 200 |
| INFRA-02 | Named volume persists userData across restarts | Stop/start → SQLite DB + Electron data survives at /root/.config/AionUi/ |
| INFRA-03 | Health check + restart policy | docker inspect → healthy within 30s; restart: unless-stopped configured |
| INFRA-04 | uncaughtException handler patched | Code review verified: console.error + process.exit(1) in production |
| BRAND-01 | All user-facing AionUi → Diador | Playwright screenshot of login page confirms "Diador" branding, zero "AionUi" |
| BRAND-02 | One atomic branding commit | Single commit ddf88b51 |
| BRAND-03 | NOTICE file exists | Verified at repo root |
| BRAND-04 | i18n validation passes | node scripts/check-i18n.js → exit 0 |

### Critical Lessons Learned During Docker Build

These are issues discovered during iterative Docker build testing that future sessions MUST know:

1. **`unzip` required** — bun's installer needs `unzip` in the apt-get install list
2. **`patches/` directory must be copied before `bun install`** — package.json references `patches/7zip-bin@5.2.0.patch`
3. **`--ignore-scripts` needed for layer caching** — but then must manually run `node node_modules/electron/install.js` (Electron binary download) and `node scripts/postinstall.js` (native module rebuild) after `COPY . .`
4. **`--no-sandbox` must be a CLI arg, not `app.commandLine.appendSwitch`** — Chromium checks for root at native startup before any JS runs
5. **`--ozone-platform=headless` must also be a CLI arg** — same reason: Chromium initializes display platform before JS
6. **Entry must be `electron .` not `electron out/main/index.js`** — otherwise `app.getAppPath()` returns wrong directory and WebUI falls back to Vite dev server proxy (502 errors)
7. **Final CMD:** `["npx", "electron", ".", "--webui", "--remote", "--no-sandbox", "--ozone-platform=headless", "--disable-gpu", "--disable-software-rasterizer"]`

### Visual Verification

Playwright-based screenshot taken of login page at localhost:25808:
- Page title: "Diador - Sign In" ✅
- Login heading (H1): "Diador" ✅
- No "AionUi" in any visible text ✅
- NOTE: Visual verification of post-login screens (main app, about modal, settings) NOT yet done — requires creating a user account first

## Performance Metrics

**Velocity:**
- Total plans completed: Phase 1 (1 phase, no formal GSD plans — executed via PM/Dev peer delegation)
- Session duration: ~1.5 hours
- Total execution time: ~1.5 hours

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-phase]: `debian:bookworm-slim` is a hard constraint — never Alpine (musl breaks Electron + better-sqlite3)
- [Pre-phase]: Pass `--webui --remote` to start; do NOT pass `--headless` (app auto-applies headless flags when DISPLAY is unset)
- [Pre-phase]: All 54 branding changes must land in ONE atomic commit for clean upstream rebasing
- [Pre-phase]: DNS-01 wildcard cert via certbot + Route53 is the only viable TLS approach for `*.diador.ai`
- [Phase 1]: `app.commandLine.appendSwitch` is too late for Chromium native flags — must pass `--no-sandbox`, `--ozone-platform=headless`, `--disable-gpu`, `--disable-software-rasterizer` as CLI args
- [Phase 1]: Entry point must be `electron .` (not `electron out/main/index.js`) so `app.getAppPath()` resolves correctly for static file serving
- [Phase 1]: Running as root with `--no-sandbox` is acceptable for v1 (container isolation via Docker + seccomp)
- [Phase 1]: Internal identifiers (localStorage keys, cookies, env vars, IPC channels, database paths) left as-is — only user-facing strings rebranded

### Pending Todos

- [ ] Push 3 commits to origin/main (approved but not pushed at session end)
- [ ] Visual verification of post-login screens (about modal, settings, titlebar) — blocked on creating a test account
- [ ] Phase 2: Orchestration & Routing — next phase to plan and execute

### Blockers/Concerns

- [Phase 1 RESOLVED]: `uncaughtException` handler patched ✅
- [Phase 1 RESOLVED]: `seccomp:unconfined` configured in docker-compose.yml ✅
- [Phase 2]: certbot DNS-01 IAM policy must include `route53:GetChange` — commonly omitted, causes silent renewal failures
- [Phase 2]: Nginx `proxy_read_timeout` must be set to 86400 — without it WebSocket sessions drop at 60s idle
- [Phase 2]: `directoryApi.ts:404` still has `name: 'AionUi Directory'` — may be user-visible, check during Phase 2

## Session Continuity

Last session: 2026-03-25
Stopped at: Phase 1 complete. 3 commits on main (not pushed). Ready for `git push origin main` then Phase 2.
Resume with: Push commits, then `/gsd:plan-phase 2` or `/gsd:discuss-phase 2`
Workflow: Used PM/Dev peer delegation (claude-peers) — PM verified, Dev implemented
Dev peer ID was: n7nbwjen (will change on restart)
