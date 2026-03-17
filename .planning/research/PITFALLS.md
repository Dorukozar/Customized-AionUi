# Pitfalls Research

**Domain:** Electron headless SaaS deployment — Docker + Nginx + wildcard SSL on EC2
**Researched:** 2026-03-17
**Confidence:** HIGH (confirmed against Nginx official docs, Docker Compose networking docs, certbot docs, codebase analysis, and project-specific context)

---

## Critical Pitfalls

### Pitfall 1: WebSocket Sessions Drop Every 60 Seconds

**What goes wrong:**
All active user sessions disconnect abruptly every 60 seconds. The WebUI appears to load but conversations reset, the UI reconnects repeatedly, and users cannot hold a sustained session. This is silent in Nginx logs because the connection terminates cleanly from Nginx's point of view.

**Why it happens:**
Nginx's default `proxy_read_timeout` is 60 seconds. WebSocket connections are persistent and idle between user messages. Nginx interprets silence on the connection as a stalled upstream and closes it. The AionUi WebUI uses a WebSocket for real-time communication (`window.__websocketReconnect` global, `src/adapter/browser.ts`). Without explicit timeout configuration, every connection silently dies at the 60-second mark.

**How to avoid:**
Add to every `location` block that proxies to AionUi containers:
```nginx
proxy_read_timeout 86400;
proxy_send_timeout 86400;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_buffering off;
```
`proxy_buffering off` is also mandatory — with buffering on, streaming AI responses (token-by-token) are held in Nginx's buffer and delivered in bursts rather than incrementally.

**Warning signs:**
- Browser console shows repeated WebSocket `close` and `open` events
- Users report conversations "resetting" after exactly a minute of inactivity
- Nginx access log shows frequent 101 to connection-close cycles

**Phase to address:** Docker + Nginx integration phase (before any client-facing deployment)

---

### Pitfall 2: Alpine / musl libc Silently Breaks Electron and better-sqlite3

**What goes wrong:**
The container starts, Electron launches, but crashes immediately with a cryptic error like `error while loading shared libraries: libm.so.6` or native addon load failure. Or worse: better-sqlite3 loads but silently corrupts data due to musl's different `locale` and `printf` behavior.

**Why it happens:**
Electron ships pre-built Chromium binaries linked against glibc (GNU libc). Alpine Linux uses musl libc, a different ABI-incompatible C library. There is no compatibility shim. better-sqlite3 also ships native bindings compiled for glibc. This is a fundamental incompatibility, not a configuration issue.

**How to avoid:**
Always use `debian:bookworm-slim` as the base image. Never use `alpine`, `alpine:*`, `node:*-alpine`, or any musl-based image. This is already a confirmed decision in PROJECT.md. The Dockerfile must be treated as a constraint document — base image line is not up for optimization.

**Warning signs:**
- Any Dockerfile `FROM` line containing `alpine`
- Error messages mentioning `musl`, `libm.so`, or `libstdc++`
- `npm rebuild` or `bun rebuild` failing inside the container during build

**Phase to address:** Docker image build phase (Dockerfile authoring)

---

### Pitfall 3: Electron Renderer Process Crash Due to Missing Kernel Capabilities (seccomp / clone3)

**What goes wrong:**
Electron launches but immediately crashes with exit code 1 or a segfault. In Docker logs: `SIGSYS` or `Operation not permitted` or `clone3 failed: Operation not permitted`. The Chromium sandbox process (which Electron uses even in `--no-sandbox` mode for the GPU process) requires `clone(2)` and `unshare(2)` syscalls that Docker's default seccomp profile blocks.

**Why it happens:**
Docker's default seccomp profile blocks ~44 syscalls. Among them are namespace-related calls (`clone`, `unshare`, `setns`) which Chromium's zygote process uses to create renderer process sandboxes. Even with `--no-sandbox`, Electron's GPU and utility processes still use fork/clone. The seccomp profile is stricter in newer kernels that introduce `clone3` (which is blocked by older default profiles).

**How to avoid:**
Add to `docker-compose.yml` for every AionUi service:
```yaml
security_opt:
  - seccomp:unconfined
```
Or provide a custom seccomp profile that re-allows `clone`, `clone3`, `unshare`, and `setns`. Using `seccomp:unconfined` is acceptable for this deployment because: (a) containers are isolated per client with no untrusted code execution, and (b) `--no-sandbox` is already required. Document this decision explicitly in the compose file.

**Warning signs:**
- Electron exits immediately with no useful log message
- `dmesg` or `journalctl` on the host shows `audit: type=1326` (seccomp violation)
- Container exits with code 1 within 1-2 seconds of start

**Phase to address:** Docker container build and run validation phase

---

### Pitfall 4: Certbot Wildcard Renewal Fails Silently Due to DNS Propagation Race

**What goes wrong:**
`certbot renew` runs via cron, appears to succeed (exit 0), but the new certificate is not issued. Nginx continues serving the old certificate. Three months later the cert expires and all clients lose HTTPS. Or: the renewal fails with `DNS problem: NXDOMAIN looking up TXT` because Route53 propagated the TXT record but the ACME server queried a different authoritative nameserver before propagation completed.

**Why it happens:**
DNS-01 challenges require certbot to create a `_acme-challenge.diador.ai` TXT record in Route53, wait for DNS propagation, then let Let's Encrypt validate it. The `certbot-dns-route53` plugin's default propagation wait (45 seconds) is sometimes insufficient when Route53 changes take longer to propagate globally. Additionally, Let's Encrypt enforces a Failed Validation limit of 5 per account per hostname per hour — repeated cron retries can exhaust this quota and block renewals for an hour.

**How to avoid:**
1. Set `--dns-route53-propagation-seconds 120` (double the default) in the certbot renew command
2. Use `--dry-run` to test the renewal path before the cert actually expires
3. Set the cron job to run twice daily (not hourly) so failures do not exhaust the rate limit
4. Monitor certificate expiry independently (e.g., `openssl s_client` check in a cron that alerts at 30 days remaining)
5. Verify the IAM role on the EC2 instance has `route53:ChangeResourceRecordSets` and `route53:GetChange` on the correct hosted zone — missing the `GetChange` permission causes silent failures where the record is created but certbot never confirms propagation

**Warning signs:**
- `certbot renew --dry-run` fails with `DNS problem: NXDOMAIN`
- `/var/log/letsencrypt/letsencrypt.log` shows `PluginError` around Route53
- Certificate expiry date is not advancing after cron runs
- Nginx `ssl_certificate` points to a `.pem` that is more than 60 days old

**Phase to address:** EC2 provisioning and SSL setup phase

---

### Pitfall 5: userData Volume Not Mounted — All Client Data Lost on Container Restart

**What goes wrong:**
A container restart (deployment update, EC2 reboot, OOM kill) wipes all client conversation history, settings, and AI model configurations. The client's SQLite database (`~/.config/AionUi/`) lives only inside the ephemeral container layer and is destroyed with the container.

**Why it happens:**
Docker containers have an ephemeral writable layer. Without an explicit named volume mount for `~/.config/AionUi/`, every `docker compose up` or `docker compose restart` destroys all state. This is easy to miss in development (where you recreate state constantly) but catastrophic in production.

**How to avoid:**
Every client service in `docker-compose.yml` must declare:
```yaml
volumes:
  - client1_data:/root/.config/AionUi
```
With a corresponding named volume at the compose file level. Validate this before any production data is written: stop a container, restart it, verify conversations persist. Never use bind mounts (e.g., `./data/client1:/root/.config/AionUi`) on EC2 root EBS — use the 100 GB data EBS mounted at `/data` and bind mount from there.

**Warning signs:**
- `docker inspect <container>` shows no mounts for `/root/.config`
- Conversations disappear after `docker compose restart`
- SQLite database file size stays at 0 after client use

**Phase to address:** Docker Compose orchestration phase (before any real client data)

---

### Pitfall 6: Port Registry Drift — Multiple Clients on the Same Loopback Port

**What goes wrong:**
Two client containers bind to the same loopback port (e.g., both on `127.0.0.1:25801`). The second container fails to start silently, or the first is killed. Nginx routes both subdomains to one container. One client sees another client's session.

**Why it happens:**
When client containers are added manually by editing `docker-compose.yml`, it is easy to duplicate a port number from a previous entry. There is no runtime enforcement that each loopback port is unique — Docker will raise an error only if two containers try to bind the same host port simultaneously, but the error may be lost in a long compose log.

**How to avoid:**
Treat `port-registry.env` (referenced in PROJECT.md) as the single source of truth. Before adding a new client, grep the registry for the intended port. Add a startup validation script that reads all assigned ports and asserts uniqueness before starting any container. Document port allocation as a first-class operational step in the onboarding runbook.

**Warning signs:**
- `docker compose up` exits with `address already in use`
- One client's Nginx location routes to another client's container
- A new client container immediately exits after start

**Phase to address:** Docker Compose orchestration phase and operations runbook phase

---

### Pitfall 7: Nginx Wildcard SSL Routing — Upstream Resolution and Certificate Mismatch

**What goes wrong:**
Nginx serves the correct subdomain content but always presents the same certificate to all subdomains, causing browser SSL errors. Or: the `proxy_pass` target is resolved at startup (DNS caching) and never updated, causing 502s after a container restart when the container gets a new Docker network IP.

**Why it happens:**
Two separate issues:
1. When using `map`-based routing with a single `server` block, `ssl_certificate` must reference the wildcard cert. If the cert path references a single-domain cert, non-matching subdomains get a certificate name mismatch warning.
2. Nginx resolves the `proxy_pass` upstream hostname at config load time by default. If using service names (e.g., `proxy_pass http://client1:3000`), these resolve correctly via Docker DNS. But if using loopback IPs (`proxy_pass http://127.0.0.1:25801`), a resolver directive is required for runtime re-resolution after container restarts.

**How to avoid:**
1. Use the Let's Encrypt wildcard cert path in `ssl_certificate` for the shared wildcard server block
2. For loopback port routing, add `resolver 127.0.0.1 valid=10s` and reference upstreams via variables to force runtime resolution
3. Validate with `openssl s_client -connect client2.diador.ai:443 -servername client2.diador.ai` after config changes

**Warning signs:**
- Browser shows "certificate name mismatch" on any subdomain except the first
- `nginx -t` passes but subdomains return 502 after container restarts
- Nginx error log shows upstream connection refused at a stale IP

**Phase to address:** Nginx configuration and wildcard SSL phase

---

### Pitfall 8: Electron Running as Root Disables Chromium Sandbox — Logged But Not Alerted

**What goes wrong:**
The container's default user is root. `configureChromium.ts` detects `process.getuid() === 0` and appends `--no-sandbox` automatically. This is the correct workaround for running in Docker, but it means Chromium's renderer process isolation is completely disabled. Any injection in the WebUI renderer has full main-process access to the host filesystem via Electron's Node.js integration.

**Why it happens:**
Docker containers default to root. Electron requires `--no-sandbox` when running as root because Linux kernel namespaces (used by Chromium's sandbox) require `CAP_SYS_ADMIN` when the process is not using a user namespace. The flag is appended automatically by the code — there is no explicit awareness that the security boundary has been removed.

**How to avoid:**
1. Add a non-root user to the Dockerfile (`RUN useradd -m diador`) and run Electron as that user — this removes the need for `--no-sandbox` entirely if the seccomp profile allows `clone`
2. If running as root is required, add a visible startup warning in the main process log
3. The iframe sandbox issue in `CONCERNS.md` (`allow-scripts` combined with `allow-same-origin`) is directly escalated by `--no-sandbox` — address both together

**Warning signs:**
- `ps aux` inside container shows Electron running as `root`
- Startup log does NOT show a warning about running as root
- `configureChromium.ts` no-sandbox branch is triggered without a log statement

**Phase to address:** Docker image build phase (Dockerfile user configuration)

---

### Pitfall 9: uncaughtException Handler is Empty — Production Crashes Are Invisible

**What goes wrong:**
Any unhandled synchronous exception in the Electron main process (IPC handler crash, database error, cron job throw) is silently swallowed in production. The container stays running but the main process is in an unknown state. Users see a frozen WebUI with no error. There is no mechanism to detect, alert, or restart the process.

**Why it happens:**
`src/index.ts` lines 201-207 explicitly no-ops the `uncaughtException` handler in production builds (confirmed in CONCERNS.md). This was presumably done to prevent crash dialogs in packaged desktop builds, but in the Docker/headless deployment context it means all production crashes are invisible.

**How to avoid:**
Before deploying to production, patch `src/index.ts` to log unhandled exceptions to stderr and exit with a non-zero code:
```typescript
process.on('uncaughtException', (err) => {
  console.error('[FATAL] uncaughtException:', err);
  process.exit(1);
});
```
Then configure Docker restart policy (`restart: unless-stopped`) so the container auto-restarts on crash. This converts invisible hangs into observable restarts that show in `docker ps` uptime.

**Warning signs:**
- Container has been running for days but WebUI is unresponsive
- `docker logs <container>` shows no output after a certain timestamp
- Main process PID is alive but not responding to IPC messages

**Phase to address:** Docker container configuration phase (before production) — also requires a one-line code fix

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Running as root in container | Avoids Dockerfile user setup complexity | Chromium sandbox disabled, security boundary removed | Never for production with extension input from clients |
| `seccomp:unconfined` instead of custom seccomp profile | Works immediately, no kernel expertise needed | Broader syscall surface exposed to container processes | Acceptable for v1 with trusted code only; document explicitly |
| Hard-coded loopback ports in `docker-compose.yml` | Simple, visible | Port collision risk grows with each new client | Acceptable at 3-5 clients if port-registry.env is enforced |
| Single EC2 instance for all clients | No orchestration overhead | No HA; one reboot affects all clients | Acceptable for v1; document the ETA for ECS migration |
| Nginx `map` routing without health checks | Simple config | No automatic failover if a container is down | Acceptable with monitoring; add health check endpoint in a later phase |
| Empty `uncaughtException` handler in production | Prevents desktop crash dialogs | Production crashes are invisible | Never — this is a direct deployment blocker |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Nginx + WebSocket | Forgetting `proxy_buffering off` for streaming AI responses | Set `proxy_buffering off` in every WebUI location block |
| Nginx + WebSocket | Using HTTP/1.0 default for proxy connections | Always set `proxy_http_version 1.1` |
| certbot-dns-route53 | IAM policy missing `route53:GetChange` | Include both `ChangeResourceRecordSets` AND `GetChange` in the IAM policy |
| certbot-dns-route53 | Cron runs hourly — exhausts failed validation rate limit | Run renewal cron twice daily at most |
| Docker + Electron | Mounting userData path inside the container overlay | Mount as named volume to a persistent EBS path |
| Docker Compose | Referencing containers by IP address | Always use service names; IPs change on container restart |
| Let's Encrypt wildcard | Using `--staging` flag and forgetting to remove it | Test with staging, then re-issue with production endpoint |
| Nginx + wildcard TLS | `ssl_certificate` path pointing to a non-wildcard cert | Verify cert covers `*.diador.ai` with `openssl x509 -text` |

---

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| `proxy_buffering on` with streaming AI responses | Token-by-token output arrives in delayed bursts, poor UX | Set `proxy_buffering off` on all AionUi locations | From first client — immediate UX degradation |
| In-memory rate limiter resets on container restart | Rate limits reset every deployment; burst abuse window opens | Acceptable for v1 single-instance; document known limitation | At first client restart |
| All clients on one EC2 — shared CPU for Electron processes | One client running a heavy AI task starves others | t3.xlarge has 4 vCPU burstable — monitor CPU credit balance | At ~3-4 simultaneous heavy sessions |
| SQLite on EBS root volume instead of data volume | I/O contention on root volume; data lost on instance replacement | Mount data EBS at `/data`, place all `userData` paths there | At first instance replacement |
| Large React bundles with no code-splitting (known from CONCERNS.md) | Slow WebUI initial load on first connection | Acceptable for v1; address in a polish phase | At first client connection on slow networks |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Running Electron as root with `--no-sandbox` | Chromium renderer compromise = full host filesystem access via Node.js | Add non-root Dockerfile user; if root required, document and log at startup |
| `allow-scripts` + `allow-same-origin` iframe combo (CONCERNS.md) | Extension iframe can remove its own sandbox attribute | Remove `allow-same-origin` from extension iframes — risk is escalated in no-sandbox environments |
| Extension worker thread has full Node.js access (CONCERNS.md) | Malicious extension can access filesystem, network, child_process | For v1 with curated extensions only: document explicitly; do not install third-party extensions |
| CDP remote debugging port open on EC2 | Remote code execution via the debugging protocol | Verify `app.isPackaged` is true in production — the code auto-disables it, but confirm |
| Unsafe HTML injection without sanitization (CONCERNS.md) | Renderer script injection if AI response contains crafted HTML | Medium risk — AI responses are the source, not direct user input; treat as tech debt, not v1 blocker |
| EC2 security group too permissive | Direct access to loopback ports (2580X) from the internet | Only expose 80/443 on the security group; loopback ports must not be in inbound rules |
| IAM role with wildcard Route53 permissions | Compromise of EC2 instance = control of all Route53 records | Scope IAM policy to the specific hosted zone ID only |

---

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No WebSocket reconnect feedback in UI | User sees frozen chat, does not know if connection dropped | Add a connection status indicator; AionUi has `__websocketReconnect` — hook it to UI state |
| Session state lost on container restart | User's in-progress conversation disappears | Ensure userData volume is mounted; verify persistence after restart |
| No client-facing maintenance page | During deployments, users see raw nginx 502 error | Add a custom `error_page 502` in Nginx pointing to a branded maintenance HTML |
| Subdomain accessed before container is ready | User gets 502 during Electron startup (~3-5 second window) | Add a health check endpoint and an Nginx upstream health check, or use a retry directive |
| All branding shows "AionUi" until the atomic commit lands | First impressions are wrong if tested before branding commit | Never demo to clients before the branding atomic commit is merged |

---

## "Looks Done But Isn't" Checklist

- [ ] **WebSocket timeout:** Nginx config has `proxy_read_timeout 86400` — verify with `nginx -T | grep read_timeout`
- [ ] **Container volumes:** `docker inspect <client>` shows a mount for `/root/.config` pointing to a named volume, not the container layer
- [ ] **SSL wildcard:** `openssl x509 -text -noout -in /etc/letsencrypt/live/diador.ai/cert.pem | grep DNS` shows `DNS:*.diador.ai`
- [ ] **Certbot renewal:** `certbot renew --dry-run` succeeds without errors before declaring DNS-01 complete
- [ ] **IAM permissions:** `aws route53 change-resource-record-sets` and `get-change` both succeed from the EC2 instance role
- [ ] **No Alpine base:** `docker inspect <container> | grep -i alpine` returns nothing
- [ ] **seccomp config:** `docker inspect <container> | grep seccomp` shows `unconfined` or a custom profile
- [ ] **uncaughtException handler:** Patched to log and exit — verify by checking `src/index.ts` production handler
- [ ] **Port uniqueness:** All ports in `port-registry.env` are unique — `sort port-registry.env | uniq -d` returns nothing
- [ ] **EC2 security group:** Ports 25801-25899 (loopback range) are NOT in the inbound rules
- [ ] **Branding commit:** `grep -r "AionUi" src/renderer/ | grep -v node_modules` returns zero user-facing strings

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| WebSocket timeout drop | LOW | Update nginx.conf, `nginx -s reload` — no container restart needed |
| userData volume not mounted | HIGH | Data is already gone; restore from backup if any; re-mount volume correctly going forward |
| Let's Encrypt rate limit hit | MEDIUM | Wait 1 hour for failed-validation limit reset; use `--staging` to test without consuming quota |
| Wrong base image (Alpine) | MEDIUM | Rebuild Dockerfile from `debian:bookworm-slim`; re-push image; restart containers |
| seccomp blocking Electron | LOW | Add `seccomp:unconfined` to compose, `docker compose up -d --force-recreate` |
| Port collision | LOW | Find the duplicate in port-registry.env, reassign one port, update compose and Nginx, restart affected container |
| Silent uncaughtException causes hang | MEDIUM | Restart container (`docker compose restart client1`); apply the handler patch and redeploy |
| Certbot DNS propagation failure | LOW | Increase `--dns-route53-propagation-seconds`, re-run `certbot renew` manually |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| WebSocket 60s timeout | Nginx + SSL configuration phase | Test with 90-second idle then send a message — session must persist |
| Alpine / musl incompatibility | Docker image build phase | `docker run --rm <image> electron --version` succeeds |
| seccomp / clone3 crash | Docker image build phase | Electron starts cleanly in container; check for SIGSYS in `dmesg` |
| Certbot wildcard renewal failure | EC2 provisioning + SSL phase | `certbot renew --dry-run` passes before declaring DNS-01 complete |
| userData volume missing | Docker Compose orchestration phase | Restart container; verify conversation persists |
| Port registry drift | Docker Compose orchestration phase | Run port uniqueness check as part of onboarding runbook |
| Nginx SNI / upstream resolution | Nginx + SSL configuration phase | Test all three client subdomains with `openssl s_client` |
| Root user + no-sandbox | Docker image build phase | `docker exec <container> id` returns non-root user |
| Silent uncaughtException | Docker container config phase | Check `src/index.ts` production handler; patch before first deploy |
| EC2 security group exposure | EC2 provisioning phase | `nmap -p 25801-25899 <ec2-public-ip>` returns all ports filtered |

---

## Sources

- Nginx official docs — `proxy_read_timeout`, `proxy_buffering`, WebSocket upgrade configuration: https://nginx.org/en/docs/http/ngx_http_proxy_module.html and https://nginx.org/en/docs/http/websocket.html (MEDIUM confidence — fetched directly from official docs)
- certbot official docs — DNS-01 propagation timing, renewal automation, dry-run recommendation: https://eff-certbot.readthedocs.io/en/stable/using.html (MEDIUM confidence — fetched directly from official docs)
- Docker official docs — compose networking, container IP changes, named volumes: https://docs.docker.com/compose/networking/ (MEDIUM confidence — fetched directly from official docs)
- Docker seccomp docs — default profile syscall restrictions: https://docs.docker.com/engine/security/seccomp/ (MEDIUM confidence — fetched directly from official docs)
- AionUi codebase analysis — `src/index.ts`, `src/utils/configureChromium.ts`, `src/adapter/browser.ts`, `src/renderer/context/AuthContext.tsx` (HIGH confidence — direct source analysis)
- `.planning/codebase/CONCERNS.md` — security, reliability, and fragility audit of the codebase (HIGH confidence — authoritative project document)
- `.planning/PROJECT.md` — confirmed key decisions including debian:bookworm-slim, --no-sandbox, WebSocket timeout requirement (HIGH confidence — authoritative project document)
- Chromium Linux sandbox requirements — `clone`, `unshare`, `setns` syscall requirements: corroborated by seccomp doc findings and widely documented in Chromium's own Puppeteer deployment guides (MEDIUM confidence)
- Let's Encrypt rate limits — 5 failed validations per hour per hostname: standard LE policy documented at https://letsencrypt.org/docs/rate-limits/ (MEDIUM confidence — fetch blocked; training data aligns with official policy)

---
*Pitfalls research for: Electron headless SaaS deployment (Docker + Nginx + wildcard SSL)*
*Researched: 2026-03-17*
