# Architecture Research

**Domain:** Single-host Docker multi-tenant SaaS — Electron WebUI served via Nginx
**Researched:** 2026-03-17
**Confidence:** HIGH (Docker/Nginx official docs verified; Electron WebUI patterns from codebase analysis)

## Standard Architecture

### System Overview

```
Internet
    |
    | HTTPS *.diador.ai (wildcard cert, Let's Encrypt DNS-01)
    v
┌─────────────────────────────────────────────────────────────┐
│                    EC2 t3.xlarge                             │
│  Ubuntu 22.04 — 100 GB data EBS at /data                    │
│                                                              │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  Nginx (host, port 443/80)                           │   │
│  │  map $host → $upstream_port (one line per client)    │   │
│  └────────┬──────────────────────────────────────────┘  │   │
│           │ proxy_pass http://127.0.0.1:$upstream_port   │   │
│           │ (loopback only — never exposed externally)   │   │
│           v                                              │   │
│  ┌─────────────────────────────────────────────────┐    │   │
│  │           Host Loopback (127.0.0.1)              │    │   │
│  │  :25801       :25802       :25803  ...           │    │   │
│  └────┬───────────────┬────────────────┬────────────┘    │   │
│       │               │                │                 │   │
│  ┌────▼───┐      ┌────▼───┐      ┌─────▼──┐             │   │
│  │client1 │      │client2 │      │client3 │             │   │
│  │Docker  │      │Docker  │      │Docker  │             │   │
│  │network │      │network │      │network │             │   │
│  │        │      │        │      │        │             │   │
│  │ AionUi │      │ AionUi │      │ AionUi │             │   │
│  │ +WebUI │      │ +WebUI │      │ +WebUI │             │   │
│  └────┬───┘      └────┬───┘      └────┬───┘             │   │
│       │               │                │                 │   │
│  ┌────▼───┐      ┌────▼───┐      ┌─────▼──┐             │   │
│  │vol:    │      │vol:    │      │vol:    │             │   │
│  │client1 │      │client2 │      │client3 │             │   │
│  │-data   │      │-data   │      │-data   │             │   │
│  └────────┘      └────────┘      └────────┘             │   │
└─────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Responsibility | Implementation |
|-----------|---------------|----------------|
| Nginx (host) | TLS termination, subdomain → port routing, WebSocket upgrade, static header hygiene | nginx on host (not containerized), config managed via Ansible/manual |
| port-registry.env | Source of truth for client-name → loopback-port mapping | Flat key=value file; Nginx map and Compose both source from it |
| Docker bridge network (per client) | Isolate container from other client containers; internal DNS only | `docker network create client1-net` (user-defined bridge) |
| AionUi container (per client) | Run Electron in headless WebUI mode; serve HTTP+WebSocket on container port 3000 | `debian:bookworm-slim`; loopback-bound via `-p 127.0.0.1:25801:3000` |
| Named volume (per client) | Persist SQLite DB, AI credentials, config — survives container recreate | `docker volume create client1-data`; mounted at `/root/.config/AionUi` |
| Let's Encrypt wildcard cert | TLS for `*.diador.ai` | certbot + Route53 plugin; DNS-01 challenge; IAM role on EC2 |
| Docker Compose (per client) | Declare container, network, volume; reproducible deploys | One `docker-compose.yml` per client under `/data/clients/<name>/` |

---

## Recommended Project Structure

```
/data/
├── clients/
│   ├── client1/
│   │   ├── docker-compose.yml     # service def for client1
│   │   └── .env                   # CLIENT_NAME=client1, PORT=25801
│   ├── client2/
│   │   ├── docker-compose.yml
│   │   └── .env
│   └── client3/
│       ├── docker-compose.yml
│       └── .env
├── port-registry.env              # client1=25801, client2=25802 ...
└── nginx/
    ├── diador.conf                # main server block + map
    └── snippets/
        └── proxy-websocket.conf  # shared WebSocket proxy headers

/etc/nginx/
└── sites-enabled/
    └── diador.conf -> /data/nginx/diador.conf

/etc/letsencrypt/
└── live/diador.ai/               # fullchain.pem, privkey.pem

# On the build machine / repo:
deploy/
├── docker/
│   └── Dockerfile                # single image for all clients
├── compose/
│   └── docker-compose.template.yml  # template for new clients
├── nginx/
│   └── diador.conf.j2 or .template
└── scripts/
    ├── onboard-client.sh         # provision new client end-to-end
    ├── update-client.sh          # pull new image + restart one client
    └── update-all.sh             # rolling update across all clients
```

### Structure Rationale

- **/data/clients/<name>/:** One directory per client means `docker compose -f /data/clients/client1/docker-compose.yml up -d` is self-contained; no shared Compose state between clients.
- **port-registry.env as single source of truth:** Both Nginx `map` block and Compose `.env` files derive from this file. Adding a client = one line here + one directory.
- **Nginx on host (not containerized):** Nginx needs access to the Let's Encrypt cert files at `/etc/letsencrypt/`. Running it on the host avoids volume-mount complexity; also gives direct access to loopback for `proxy_pass`.

---

## Architectural Patterns

### Pattern 1: Nginx `map` Module for Subdomain Routing

**What:** A single `map` block translates `$host` (the incoming `Host:` header) to a backend port variable. One `server` block handles all clients; adding a client requires adding one line to the map — no new `location` or `server` blocks.

**When to use:** Any time the routing key (subdomain) maps 1:1 to a backend. Scales to 50+ clients with zero configuration duplication.

**Trade-offs:** Simple and fast. Map lookups are O(1) with hash_max_size. Limitation: cannot do request-body-based routing (not needed here).

**Example:**
```nginx
# /data/nginx/diador.conf

map $host $upstream_port {
    hostnames;
    default        0;
    client1.diador.ai  25801;
    client2.diador.ai  25802;
    client3.diador.ai  25803;
}

server {
    listen 443 ssl;
    server_name *.diador.ai;

    ssl_certificate     /etc/letsencrypt/live/diador.ai/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/diador.ai/privkey.pem;

    # Return 444 (no response) for unknown subdomains
    if ($upstream_port = 0) { return 444; }

    location / {
        proxy_pass http://127.0.0.1:$upstream_port;
        include /data/nginx/snippets/proxy-websocket.conf;
    }
}
```

```nginx
# /data/nginx/snippets/proxy-websocket.conf

proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection "upgrade";
proxy_set_header Host $host;
proxy_set_header X-Real-IP $remote_addr;
proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
proxy_set_header X-Forwarded-Proto $scheme;

# WebSocket sessions stay open; without this Nginx closes idle sockets after 60s
proxy_read_timeout 86400;
proxy_send_timeout 86400;

# Disable buffering — WebSocket and SSE streams must pass through immediately
proxy_buffering off;
```

### Pattern 2: Per-Client Loopback Port Binding

**What:** Each container binds its WebUI port (`3000`) to a unique loopback address+port on the host. The port is never reachable from outside the EC2 instance — Nginx is the only consumer.

**When to use:** Single-host multi-tenant where containers should not be directly internet-accessible.

**Trade-offs:** Extremely simple; no Docker overlay network or host-mode networking needed. Port range must be tracked (port-registry.env). Hard limit: ~64K loopback ports — irrelevant for v1 scale.

**Example (Docker Compose long-form ports):**
```yaml
# /data/clients/client1/docker-compose.yml
services:
  aionui:
    image: ghcr.io/diador/aionui-custom:latest
    restart: unless-stopped
    ports:
      - target: 3000
        published: "${PORT}"       # from .env: PORT=25801
        host_ip: 127.0.0.1
        protocol: tcp
    networks:
      - client1-net
    volumes:
      - client1-data:/root/.config/AionUi
    mem_limit: 2g
    cpus: "1.0"
    environment:
      - ELECTRON_DISABLE_SECURITY_WARNINGS=true

networks:
  client1-net:
    driver: bridge

volumes:
  client1-data:
    external: true   # pre-created; prevents accidental deletion
```

### Pattern 3: Per-Client User-Defined Bridge Network

**What:** Each client container is attached to its own user-defined bridge network. Containers on different bridges cannot communicate without an explicit cross-network connection.

**When to use:** Multi-tenant scenarios where client data isolation must extend to the network layer — even on the same host.

**Trade-offs:** Slight overhead of one bridge interface per client (negligible). Docker's built-in DNS works within the network but not across. The benefit: a compromised container cannot reach another client's container via internal IP.

**Security properties (verified, Docker docs):**
- Containers on separate user-defined bridge networks have no route to each other
- The only cross-container route is through the host loopback → Nginx → different port
- Default Docker bridge (`docker0`) is avoided; it allows all containers to reach each other

### Pattern 4: Named Volumes as Client Data Stores

**What:** One named Docker volume per client (`client1-data`, `client2-data`, ...) mounted at the Electron `userData` path (`/root/.config/AionUi/`). Volume contents persist across container recreation, image updates, and host reboots.

**When to use:** Any stateful containerized app where data must survive container lifecycle events.

**Trade-offs:** Volumes are opaque directories on the host (under `/var/lib/docker/volumes/`). Backup requires `docker run --rm --volumes-from` tar pattern. Cannot use `external: true` for automatic creation — must pre-create with `docker volume create client1-data`.

**Backup pattern:**
```bash
docker run --rm \
  -v client1-data:/source:ro \
  -v /data/backups:/backup \
  debian:bookworm-slim \
  tar czf /backup/client1-$(date +%Y%m%d).tar.gz -C /source .
```

---

## Data Flow

### Request Flow (browser → AI response)

```
Browser (client1.diador.ai)
    |
    | HTTPS (TLS terminated at Nginx)
    v
Nginx (host :443)
    | map $host → $upstream_port = 25801
    | proxy_pass http://127.0.0.1:25801
    | WebSocket Upgrade headers forwarded
    v
127.0.0.1:25801 (host loopback)
    |
    | Docker port mapping: 127.0.0.1:25801 → container:3000
    v
AionUi Container (client1-net bridge)
    |
    | Express + WebSocket server (src/webserver/)
    | JWT auth validates token
    v
AionUi Main Process
    | WorkerManage → AgentManager → forked worker
    v
AI Provider API (egress from container → EC2 NAT → internet)
    |
    v
Streamed response chunks
    | worker → manager → ipcBridge.conversation.responseStream
    v
WebSocket frame → Nginx passthrough (proxy_buffering off)
    v
Browser receives streamed AI tokens
```

### WebSocket Lifecycle

```
Client connect
    → HTTP Upgrade request (Connection: Upgrade, Upgrade: websocket)
    → Nginx forwards headers (proxy_http_version 1.1, Upgrade, Connection)
    → Container WebSocket server handshake (101 Switching Protocols)
    → Tunnel established: bidirectional, stays open up to proxy_read_timeout (86400s)

Client idle (no messages)
    → AionUi WebSocket server sends ping frames periodically
    → Resets Nginx proxy_read_timeout counter
    → Connection stays alive

Container restart
    → WebSocket connection drops (client gets disconnect event)
    → Browser reconnects (AionUi renderer handles reconnect)
    → JWT re-auth if required
```

### Key Data Flows

1. **New client onboarding:** `onboard-client.sh` creates Docker volume → creates bridge network → writes `.env` + `docker-compose.yml` → adds map line to `diador.conf` → `nginx -s reload` → starts container. Zero downtime for existing clients.

2. **Image update (one client):** `docker compose pull` → `docker compose up -d --no-deps` (graceful restart). SQLite data in named volume survives. WebSocket connections drop for ~2s reconnect window.

3. **Config/data persistence:** SQLite DB at `~/.config/AionUi/data.db` inside volume. AI API keys stored in SQLite via AionUi's credential system. Credentials survive container recreation.

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1-5 clients | Current pattern — single EC2, Docker Compose per client, all on one host |
| 5-20 clients | Upgrade EC2 to m6i.2xlarge (8 vCPU / 32 GB). Add EBS IOPS provisioned volume for SQLite. Add automated backup cron. No architecture change. |
| 20-50 clients | Consider separating Nginx onto a t3.small with EIP; move containers to a fleet. Or adopt ECS Fargate with ALB per-service routing. Named volumes → EFS. |
| 50+ clients | ECS Fargate per task, ALB subdomain-based routing rules, RDS for shared data, EFS for user data. Full re-architecture. |

### Scaling Priorities

1. **First bottleneck (5-10 clients):** Memory. Each Electron + WebUI instance uses ~300-600 MB resident. t3.xlarge (16 GB) supports ~10-15 clients comfortably. Monitor with `docker stats`. Mitigation: `mem_limit: 2g` per container prevents OOM cascade.

2. **Second bottleneck (10-20 clients):** SQLite write contention is irrelevant (each client has their own DB). CPU becomes the constraint during concurrent AI streaming. `--cpus 1.0` per container prevents one client from starving others.

3. **Third bottleneck (20+ clients):** EC2 network bandwidth. t3.xlarge provides 5 Gbps bursting. At high AI token throughput (multiple clients streaming simultaneously) bandwidth can spike. Monitor `NetworkOut` CloudWatch metric.

---

## Anti-Patterns

### Anti-Pattern 1: Exposing Container Ports on All Interfaces (0.0.0.0)

**What people do:** `ports: - "25801:3000"` (no host IP specified)

**Why it's wrong:** Docker publishes on `0.0.0.0` by default, bypassing ufw/iptables. The AionUi WebUI becomes accessible directly on `ec2-ip:25801` from the internet — no TLS, no subdomain routing, authentication only as defense.

**Do this instead:** Always specify `host_ip: 127.0.0.1` in long-form ports, or `"127.0.0.1:25801:3000"` in short form. Nginx is the only entry point.

### Anti-Pattern 2: Using the Default Docker Bridge (`docker0`)

**What people do:** Start containers without `--network` or without defining a named network in Compose. All containers land on `docker0`.

**Why it's wrong:** All containers on `docker0` can reach each other by IP. Client1's container can TCP-connect to client2's container on port 3000 — full cross-tenant access.

**Do this instead:** Always define a per-client named bridge network. Containers on separate user-defined bridge networks have no route to each other.

### Anti-Pattern 3: Missing WebSocket Timeout Directive

**What people do:** Use default Nginx proxy config without `proxy_read_timeout`.

**Why it's wrong:** Nginx's default `proxy_read_timeout` is 60 seconds. Any WebSocket idle for 60s gets the connection closed with a 504. The AionUi session drops. User sees a disconnect mid-conversation.

**Do this instead:** `proxy_read_timeout 86400;` (24 hours). Also set `proxy_send_timeout 86400;`. Combined with AionUi's WebSocket ping, this prevents premature disconnection.

### Anti-Pattern 4: Shared Volume for Multiple Clients

**What people do:** Mount one large volume and use subdirectories per client.

**Why it's wrong:** A volume permission misconfiguration or a path-traversal bug in the app can expose one client's data to another. Backup/restore complexity increases. Deleting one client's data risks affecting others.

**Do this instead:** One named volume per client. `external: true` in Compose prevents accidental volume deletion. Backup each volume independently.

### Anti-Pattern 5: Running Nginx Inside a Container

**What people do:** Containerize Nginx alongside the app containers.

**Why it's wrong:** Nginx needs access to `/etc/letsencrypt/` for the wildcard cert. It also needs to proxy to `127.0.0.1:258XX` on the host. Both require complex volume mounts and `network_mode: host`. The host-resident Nginx pattern is simpler and is what Let's Encrypt certbot expects.

**Do this instead:** Run Nginx on the host. `certbot renew` hooks reload Nginx via `systemctl reload nginx`. No volume-mount gymnastics.

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Let's Encrypt / Route53 | certbot DNS-01 challenge via `certbot-dns-route53` plugin; IAM role on EC2 (no static keys) | Wildcard certs auto-renew via cron `certbot renew`; post-hook: `nginx -s reload` |
| AI providers (OpenAI, Gemini, etc.) | Egress from container through EC2 NAT → internet | Credentials stored per-client in SQLite volume; not in image or env vars |
| AWS EC2 | Host for all containers; EBS volumes for /data | Snapshot EBS data volume daily for disaster recovery |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Nginx ↔ AionUi container | HTTP/WebSocket via 127.0.0.1 loopback, mapped port | Nginx never talks to container by container name/DNS |
| AionUi Main Process ↔ Worker | Node.js fork IPC (existing AionUi internals) | No change from desktop app; worker isolation preserved in container |
| AionUi Main ↔ WebServer | Direct import (same Node process) | Express/WebSocket server is a module within the Electron main process |
| Container ↔ Named Volume | Docker bind mount at `/root/.config/AionUi` | Container user is root (Electron requires no-sandbox); volume owned by root |
| EC2 ↔ S3 (future) | IAM instance profile → S3 SDK | Needed for volume backups at scale; not required for v1 |

---

## Build Order (Phase Implications)

The architecture has a clear dependency chain that dictates implementation order:

```
1. Docker image (single buildable Electron container)
       ↓ required by
2. Per-client Compose stack (container + network + volume)
       ↓ required by
3. Multi-client orchestration (port-registry, onboard script)
       ↓ required by
4. Nginx routing (map block needs known ports)
       ↓ required by
5. TLS + DNS (wildcard cert, A record)
       ↓ required by
6. Production EC2 provisioning (all components together)
       ↓
7. Operations runbooks (backup, update, onboard)
```

**Implication:** The Docker image must be fully working and tested before any routing or SSL work begins. Nginx config can be written in parallel but cannot be tested until containers are running.

---

## Sources

- Docker user-defined bridge network isolation: https://docs.docker.com/network/drivers/bridge/ (HIGH confidence)
- Docker Compose network isolation and per-project networks: https://docs.docker.com/compose/how-tos/networking/ (HIGH confidence)
- Docker named volumes persistence and backup: https://docs.docker.com/engine/storage/volumes/ (HIGH confidence)
- Docker loopback port binding syntax (`host_ip: 127.0.0.1`): https://docs.docker.com/compose/compose-file/05-services/#ports (HIGH confidence)
- Nginx WebSocket proxying (Upgrade, Connection headers, proxy_read_timeout): https://nginx.org/en/docs/http/websocket.html (HIGH confidence)
- Nginx map module for subdomain routing: https://nginx.org/en/docs/http/ngx_http_map_module.html (HIGH confidence)
- Docker container resource constraints (mem_limit, --cpus): https://docs.docker.com/engine/containers/resource_constraints/ (HIGH confidence)
- AionUi WebServer implementation: `src/webserver/` (codebase analysis, HIGH confidence)
- Nginx WebSocket timeout requirement: confirmed in PROJECT.md (`proxy_read_timeout 86400` flagged as mandatory)

---

*Architecture research for: Diador — AionUi single-host Docker multi-tenant SaaS*
*Researched: 2026-03-17*
