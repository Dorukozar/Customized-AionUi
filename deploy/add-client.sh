#!/usr/bin/env bash
set -euo pipefail

# Diador — provision a new client container
# Usage: ./add-client.sh <client-name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/port-registry.env"
CLIENTS_DIR="${SCRIPT_DIR}/clients"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
NGINX_CONF="${SCRIPT_DIR}/nginx/diador.conf"
PORT_MIN=25809
PORT_MAX=25899

usage() {
  echo "Usage: $0 <client-name>"
  echo ""
  echo "Provisions a new Diador client container with:"
  echo "  - Auto-allocated loopback port (${PORT_MIN}-${PORT_MAX})"
  echo "  - Isolated Docker bridge network"
  echo "  - Persistent named volume"
  echo "  - Health check and restart policy"
  echo ""
  echo "Client name must be lowercase alphanumeric (hyphens allowed)."
  exit 1
}

# Validate arguments
if [[ $# -ne 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  usage
fi

CLIENT_NAME="$1"

# Validate client name: lowercase alphanumeric + hyphens only
if ! [[ "$CLIENT_NAME" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
  echo "ERROR: Client name must be lowercase alphanumeric (hyphens allowed, cannot start with hyphen)."
  exit 1
fi

# Check if client already exists in registry
if grep -q "^${CLIENT_NAME}=" "$REGISTRY" 2>/dev/null; then
  echo "ERROR: Client '${CLIENT_NAME}' already exists in port registry."
  exit 1
fi

# Find next available port
find_next_port() {
  local port
  for port in $(seq "$PORT_MIN" "$PORT_MAX"); do
    if ! grep -q "=${port}$" "$REGISTRY" 2>/dev/null; then
      echo "$port"
      return 0
    fi
  done
  echo "ERROR: No available ports in range ${PORT_MIN}-${PORT_MAX}." >&2
  return 1
}

CLIENT_PORT=$(find_next_port)
echo "==> Provisioning client '${CLIENT_NAME}' on port ${CLIENT_PORT}"

# 1. Add to port registry
echo "${CLIENT_NAME}=${CLIENT_PORT}" >> "$REGISTRY"
echo "  [+] Added to port registry"

# 2. Create per-client .env file
mkdir -p "$CLIENTS_DIR"
ENV_FILE="${CLIENTS_DIR}/${CLIENT_NAME}.env"
cat > "$ENV_FILE" <<EOF
CLIENT_NAME=${CLIENT_NAME}
CLIENT_PORT=${CLIENT_PORT}
EOF
echo "  [+] Created ${ENV_FILE}"

# 3. Update Nginx map block
if [[ -f "$NGINX_CONF" ]]; then
  # Insert client entry before the closing } of the map $host $diador_port block
  sed -i.bak "/^map \$host \$diador_port/,/^}/ {
    /^}/ i\\
    ${CLIENT_NAME}.diador.ai      ${CLIENT_PORT};
  }" "$NGINX_CONF"
  rm -f "${NGINX_CONF}.bak"
  echo "  [+] Added to Nginx map block"

  # Reload Nginx if running
  if command -v nginx &>/dev/null && nginx -t &>/dev/null 2>&1; then
    nginx -s reload
    echo "  [+] Nginx reloaded"
  else
    echo "  [!] Nginx not available — skipping reload (update manually on EC2)"
  fi
else
  echo "  [!] Nginx config not found — skipping (update manually on EC2)"
fi

echo "  [~] Starting container diador-${CLIENT_NAME}..."
docker compose \
  -f "$COMPOSE_FILE" \
  --env-file "$ENV_FILE" \
  -p "diador-${CLIENT_NAME}" \
  up -d --build

echo "  [+] Container started"

# 4. Wait for health check
echo "  [~] Waiting for health check (up to 60s)..."
HEALTHY=false
for i in $(seq 1 12); do
  sleep 5
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' "diador-${CLIENT_NAME}-diador-1" 2>/dev/null || echo "unknown")
  if [[ "$STATUS" == "healthy" ]]; then
    HEALTHY=true
    break
  fi
  echo "      Attempt ${i}/12: status=${STATUS}"
done

if $HEALTHY; then
  echo ""
  echo "======================================"
  echo " Client '${CLIENT_NAME}' is HEALTHY"
  echo " URL: http://127.0.0.1:${CLIENT_PORT}"
  echo " Subdomain: https://${CLIENT_NAME}.diador.ai"
  echo "======================================"
else
  echo ""
  echo "WARNING: Health check did not pass within 60s."
  echo "Check logs: docker logs diador-${CLIENT_NAME}-diador-1"
  exit 1
fi
