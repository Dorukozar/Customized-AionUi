# Feature Research

**Domain:** Multi-tenant Docker SaaS — single-host, per-client container deployment
**Researched:** 2026-03-17
**Confidence:** MEDIUM — no WebSearch available; based on training knowledge of Docker/Nginx/SaaS operations patterns, cross-referenced with PROJECT.md constraints

---

## Feature Landscape

### Table Stakes (Must Have or Clients Cannot Be Onboarded)

These are non-negotiable for v1. Missing any of them means a client either cannot be provisioned, cannot be supported, or cannot be recovered from failure.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Client provisioning script | Operators need a reproducible, single-command way to spin up a new client | LOW | Shell script: create named volume, add Docker Compose service entry, register port in port-registry.env, add Nginx map entry, reload Nginx |
| Client teardown script | Decommissioning must clean up containers, volumes, Nginx config, and DNS | LOW | Mirror of provisioning; must confirm before deleting volume data |
| Container health checks | Docker needs to know if AionUi's WebUI server is actually responding — not just that the process is running | LOW | `HEALTHCHECK` in Dockerfile: `curl -f http://localhost:258XX/` with 30s interval, 3 retries; determines when container is `healthy` vs `starting` |
| Nginx reload automation | Adding/removing a client requires Nginx to pick up the new map entry without dropping existing connections | LOW | `nginx -s reload` (graceful); integrated into provisioning script |
| Wildcard SSL cert auto-renewal | Let's Encrypt certs expire every 90 days; manual renewal will be missed | LOW | `certbot renew` cron job (certbot + Route53 plugin already chosen); test renewal works before first client |
| Named volume backup | SQLite database and AionUi config are in `~/.config/AionUi/` inside the named volume — losing this loses the client's entire conversation history | MEDIUM | Scheduled `docker run --rm -v clientname_data:/data -v /backups:/backup alpine tar czf /backup/clientname-$(date +%Y%m%d).tar.gz /data`; run nightly via cron |
| Container restart policy | Process crashes (uncaughtException is a no-op in production per CONCERNS.md) must self-heal without operator intervention | LOW | `restart: unless-stopped` in Docker Compose for every client service |
| Port registry discipline | Each client needs a unique loopback port; conflicts cause silent routing failures | LOW | `port-registry.env` is already the designated source of truth; provisioning script must allocate next free port and write to it atomically |
| Startup/readiness probe awareness | Electron takes several seconds to initialize; Nginx must not receive traffic before the WebUI is ready | LOW | Nginx `upstream` directive with `proxy_connect_timeout`; provisioning script waits for `healthy` status before adding to Nginx map |
| Operations runbook | Operator must be able to onboard a client, update containers, and recover from failure without tribal knowledge | LOW | Markdown runbook covering: new client, update image, container crash recovery, backup restore, SSL renewal |
| Log access per client | When a client reports a bug, operator must be able to inspect logs | LOW | `docker logs clientname --tail 200 --follow`; no log aggregation needed for v1 but the command must be documented |
| Secure WebUI access | Each client's `/` endpoint must not be accessible by other clients or the public without authentication | MEDIUM | AionUi WebServer already has JWT auth; ensure each client's WebUI token is unique and documented per-client |

### Differentiators (Competitive Advantage, v2+)

These provide operational leverage or client-facing value but are not blockers for onboarding 3-5 clients.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| Centralized log aggregation | Loki + Grafana or Papertrail gives operator a single pane for all client logs; speeds up cross-client incident diagnosis | MEDIUM | Docker logging driver → Loki; low cost but adds infra dependency |
| Resource usage monitoring per client | Operator can detect a client consuming runaway CPU/RAM before it impacts neighbors on the shared host | MEDIUM | Prometheus + cAdvisor as sidecar containers; exposes per-container metrics |
| Grafana dashboard | Visual overview of container health, memory, CPU, restart counts across all clients | MEDIUM | Depends on Prometheus + cAdvisor; provides at-a-glance host health |
| Automated backup validation | A backup that has never been tested is not a backup | MEDIUM | Weekly cron that restores a backup to a temp container and checks that the SQLite file is readable |
| Per-client update scheduling | Update containers one at a time with health check gate rather than all at once; reduces blast radius | LOW | Loop in update script: pull new image → stop → start → wait for healthy → proceed to next client |
| Client-facing status page | Clients can see if their instance is up without emailing operator | MEDIUM | Simple uptime page (e.g., Upptime or self-hosted Gatus pinging each subdomain) |
| Disk usage alerting | 100 GB data EBS fills up if backups accumulate or a client's SQLite grows large | LOW | Cron script: `df -h` threshold check → send alert email via SES or Mailgun |
| Nginx access log per client | Separate log file per `server_name` pattern enables per-client traffic analysis | LOW | `access_log /var/log/nginx/clientname.log` in map-matched block; standard Nginx config |
| Image version pinning per client | Allows running different AionUi versions for different clients during staged rollouts | LOW | Docker Compose `image: diador:1.2.3` per service entry rather than always `latest` |
| EC2 instance auto-recovery | AWS auto-recovery reboots the EC2 instance if the underlying hardware fails, without manual intervention | LOW | CloudWatch alarm on `StatusCheckFailed_System` → `recover` action; no code required |

### Anti-Features (Deliberately NOT in v1)

Features that are commonly considered but create disproportionate complexity or cost relative to the v1 scale of 3-5 clients.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| Kubernetes / ECS orchestration | Perceived as "proper" container management | Massive operational overhead for a 3-5 client deployment; ECS requires ALB ($18/mo minimum), task definitions, ECR, IAM roles, VPC configuration — overkill when Docker Compose on one host solves the same problem | Single-host Docker Compose; migrate to ECS when >20 clients |
| Billing / payment integration | Automating revenue collection | Out of scope by PROJECT.md; client contracts are handled externally; building Stripe integration before product-market fit wastes weeks | External invoicing (Stripe Dashboard manually, or Wave/FreshBooks) |
| Self-service client portal | Clients sign up and provision themselves | Requires authentication, provisioning API, payment gate, and email flows — a product in itself | Operator-driven onboarding; 3-5 clients can be handled manually |
| Multi-region / geo-routing | Reduced latency for international clients | Single EC2 in one region is sufficient for v1; multi-region requires Route 53 health checks, data replication strategy, and doubled infrastructure cost | Move to CloudFront CDN for static assets if latency becomes a complaint |
| Real-time metrics streaming to clients | "Show clients their usage in a dashboard" | Each client's session data is in an isolated SQLite; aggregation requires an ETL layer; complexity far exceeds the v1 need | Provide usage summary on request via manual export |
| Horizontal auto-scaling | Automatically add EC2 instances under load | Incompatible with the single-host named volume model; SQLite is not network-accessible; scaling requires a full architecture change (Postgres, shared storage, ECS/Fargate) | Vertical scale the EC2 (t3.xlarge → t3.2xlarge) as the cheaper near-term option |
| In-app update mechanism for clients | Clients click "update" from their browser | Electron auto-update requires Squirrel; in WebUI-only mode there is no BrowserWindow; updates must be done at the container image level | Operator rebuilds Docker image and runs update script; clients get updates transparently |
| WebSocket load balancing across containers | Route a client's traffic to multiple containers | AionUi maintains in-process state (active agent workers, WebSocket sessions); sticky sessions are required; splitting across containers breaks this | One container per client already provides natural isolation; no load balancing needed |

---

## Feature Dependencies

```
[Container health checks]
    └──enables──> [Startup readiness probe awareness]
    └──enables──> [Per-client update scheduling (gated on healthy)]

[Named volume backup]
    └──requires──> [Container health checks] (backup should pause if container is unhealthy)
    └──enhances──> [Automated backup validation]

[Client provisioning script]
    └──requires──> [Port registry discipline]
    └──requires──> [Nginx reload automation]
    └──requires──> [Wildcard SSL cert auto-renewal] (cert must exist before first client)
    └──produces──> [Unique per-client JWT secret]

[Prometheus + cAdvisor]
    └──enables──> [Resource usage monitoring per client]
    └──enables──> [Grafana dashboard]

[Centralized log aggregation]
    └──enhances──> [Log access per client]

[EC2 instance auto-recovery]
    └──complements──> [Container restart policy] (process-level vs hardware-level recovery)
```

### Dependency Notes

- **Wildcard SSL cert must exist before client provisioning:** certbot DNS-01 must succeed before any `*.diador.ai` subdomain is reachable. This is a one-time pre-condition, not per-client.
- **Port registry before provisioning script:** the script reads port-registry.env to allocate ports; if the registry is wrong, two clients share a port and both silently fail.
- **Health checks before update script:** rolling per-client updates are only safe if the script can test that the newly started container reaches `healthy` before proceeding to the next client.
- **Backup before teardown:** client teardown script must check that at least one backup exists before deleting the volume; otherwise data loss is one command away.

---

## MVP Definition

### Launch With (v1)

Minimum required to onboard a paying client and keep them running reliably.

- [ ] Container health check (`HEALTHCHECK` in Dockerfile) — without this, Docker Compose cannot gate on readiness and restart policies are blind to application-level failures
- [ ] `restart: unless-stopped` on all client services — AionUi has a silent crash bug in production (CONCERNS.md: uncaughtException no-op); containers must self-heal
- [ ] Client provisioning script — operator must be able to add a client in under 5 minutes without touching 6 files by hand
- [ ] Client teardown script — must cleanly remove a client without leaving orphaned volumes or broken Nginx config
- [ ] Nightly named volume backup via cron — conversation history is irreplaceable; this is client trust
- [ ] Wildcard SSL cert with auto-renewal cron — expired cert = client locked out
- [ ] Nginx reload in provisioning script — new subdomain must go live without a full Nginx restart
- [ ] Port registry (port-registry.env) enforced in provisioning script — port conflicts cause silent failures
- [ ] Operations runbook (onboarding, update, crash recovery, backup restore) — operator cannot rely on memory for 5 clients

### Add After Validation (v1.x)

Add these once the first 3 clients are running stably for 2+ weeks.

- [ ] Per-client update script with health-gate — reduces blast radius when rolling out new AionUi builds to existing clients
- [ ] Disk usage alerting cron — 100 GB EBS will fill up with nightly backups within months without rotation
- [ ] Backup rotation policy — keep 7 daily + 4 weekly + 1 monthly; delete older backups automatically
- [ ] EC2 instance auto-recovery CloudWatch alarm — no-code hardware failure protection
- [ ] Nginx access log per client — needed to answer "how often is client X using their instance?"

### Future Consideration (v2+)

Defer until client count justifies the operational complexity.

- [ ] Prometheus + cAdvisor + Grafana — justified at 10+ clients when per-container resource contention becomes a real concern
- [ ] Centralized log aggregation (Loki/Papertrail) — justified at 10+ clients when tailing logs per-container becomes painful
- [ ] Automated backup validation (restore-to-temp test) — high value but high complexity; acceptable risk at 3-5 clients with manually verified backups
- [ ] Client-facing status page (Gatus/Upptime) — reduces support noise at scale; overkill for 3-5 clients
- [ ] Image version pinning per client + staged rollouts — necessary when clients have divergent requirements or SLAs

---

## Feature Prioritization Matrix

| Feature | Operator Value | Implementation Cost | Priority |
|---------|---------------|---------------------|----------|
| Container health check | HIGH | LOW | P1 |
| restart: unless-stopped | HIGH | LOW | P1 |
| Client provisioning script | HIGH | LOW | P1 |
| Client teardown script | HIGH | LOW | P1 |
| Named volume backup (nightly cron) | HIGH | LOW | P1 |
| Wildcard SSL auto-renewal | HIGH | LOW | P1 |
| Port registry enforcement | HIGH | LOW | P1 |
| Operations runbook | HIGH | LOW | P1 |
| Nginx reload automation | MEDIUM | LOW | P1 |
| Per-client update script (health-gated) | HIGH | LOW | P2 |
| Disk usage alerting | HIGH | LOW | P2 |
| Backup rotation | MEDIUM | LOW | P2 |
| EC2 auto-recovery alarm | MEDIUM | LOW | P2 |
| Nginx access log per client | LOW | LOW | P2 |
| Prometheus + cAdvisor | MEDIUM | MEDIUM | P3 |
| Grafana dashboard | MEDIUM | MEDIUM | P3 |
| Centralized log aggregation | MEDIUM | MEDIUM | P3 |
| Automated backup validation | HIGH | MEDIUM | P3 |
| Client-facing status page | LOW | MEDIUM | P3 |

**Priority key:**
- P1: Must have for launch (v1)
- P2: Should have, add when first 3 clients are stable (v1.x)
- P3: Nice to have, add at 10+ clients or after explicit pain point (v2+)

---

## Competitor Feature Analysis

*Note: WebSearch unavailable; this section draws on training knowledge of comparable SaaS deployment patterns (e.g., Outline, Gitea, Plausible self-hosted SaaS models).*

| Feature | Typical Self-Hosted SaaS (e.g., Gitea Cloud, Outline) | Our Approach |
|---------|------------------------------------------------------|-------------|
| Health checks | Docker HEALTHCHECK + uptime monitoring | Docker HEALTHCHECK; uptime page deferred to v2 |
| Backups | Automated nightly + S3 offsite | Nightly to EBS; S3 offsite is a v1.x add |
| Client isolation | Separate DB schema or separate DB per tenant | Separate Docker container + named volume per client (stronger isolation) |
| Updates | Rolling restart with health gate | Per-client update script with health-gate (v1.x) |
| Monitoring | Prometheus + Grafana standard | Deferred to v2; too heavy for 3-5 clients |
| Onboarding | API-driven or self-service | Operator script; matches the 3-5 client scale |

---

## Sources

- PROJECT.md constraints and decisions (HIGH confidence — primary source)
- CONCERNS.md: `uncaughtException` no-op in production (HIGH confidence — confirmed bug, directly affects restart policy priority)
- ARCHITECTURE.md: WebServer JWT auth, SQLite named volume data path (HIGH confidence)
- Docker Compose documentation: `restart` policies, `HEALTHCHECK` syntax (MEDIUM confidence — training knowledge, no Context7 verification available)
- Let's Encrypt / certbot DNS-01 wildcard renewal patterns (MEDIUM confidence — training knowledge, certbot + Route53 is well-established pattern)
- General multi-tenant SaaS operational patterns for single-host deployments (MEDIUM confidence — training knowledge; WebSearch unavailable to verify 2026 current practices)

---

*Feature research for: Diador — AionUi multi-tenant Docker SaaS deployment*
*Researched: 2026-03-17*
