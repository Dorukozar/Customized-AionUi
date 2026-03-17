# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-03-17)

**Core value:** A client can access their own Diador AI assistant at a personal subdomain — fully isolated, persistent, and accessible from any browser — without installation.
**Current focus:** Phase 1 — Container Foundation

## Current Position

Phase: 1 of 3 (Container Foundation)
Plan: 0 of TBD in current phase
Status: Ready to plan
Last activity: 2026-03-17 — Roadmap created

Progress: [░░░░░░░░░░] 0%

## Performance Metrics

**Velocity:**
- Total plans completed: 0
- Average duration: -
- Total execution time: 0 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| - | - | - | - |

**Recent Trend:**
- Last 5 plans: -
- Trend: -

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- [Pre-phase]: `debian:bookworm-slim` is a hard constraint — never Alpine (musl breaks Electron + better-sqlite3)
- [Pre-phase]: Pass `--webui --remote` to start; do NOT pass `--headless` (app auto-applies headless flags when DISPLAY is unset)
- [Pre-phase]: All 54 branding changes must land in ONE atomic commit for clean upstream rebasing
- [Pre-phase]: DNS-01 wildcard cert via certbot + Route53 is the only viable TLS approach for `*.diador.ai`

### Pending Todos

None yet.

### Blockers/Concerns

- [Phase 1]: `uncaughtException` handler is a no-op in production (`src/index.ts`) — must patch before any real client data is written
- [Phase 1]: `seccomp:unconfined` is required for Electron renderer processes — default Docker seccomp blocks `clone3`
- [Phase 2]: certbot DNS-01 IAM policy must include `route53:GetChange` — commonly omitted, causes silent renewal failures
- [Phase 2]: Nginx `proxy_read_timeout` must be set to 86400 — without it WebSocket sessions drop at 60s idle

## Session Continuity

Last session: 2026-03-17
Stopped at: Roadmap created — ready to run /gsd:plan-phase 1
Resume file: None
