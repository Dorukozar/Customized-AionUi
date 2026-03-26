#!/usr/bin/env bash
set -euo pipefail

# Diador — safely remove a client container
# Usage: ./remove-client.sh <client-name>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${SCRIPT_DIR}/port-registry.env"
CLIENTS_DIR="${SCRIPT_DIR}/clients"
BACKUPS_DIR="${SCRIPT_DIR}/backups"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.yml"
NGINX_CONF="${SCRIPT_DIR}/nginx/diador.conf"

usage() {
  echo "Usage: $0 <client-name>"
  echo ""
  echo "Safely removes a Diador client:"
  echo "  1. Backs up the named volume (tar archive)"
  echo "  2. Stops and removes the container"
  echo "  3. Removes the named volume"
  echo "  4. Removes the port registry entry"
  echo "  5. Removes the per-client .env file"
  echo ""
  echo "Backups are saved to deploy/backups/"
  exit 1
}

# Validate arguments
if [[ $# -ne 1 ]] || [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
  usage
fi

CLIENT_NAME="$1"

# Verify client exists in registry
if ! grep -q "^${CLIENT_NAME}=" "$REGISTRY" 2>/dev/null; then
  echo "ERROR: Client '${CLIENT_NAME}' not found in port registry."
  exit 1
fi

CLIENT_PORT=$(grep "^${CLIENT_NAME}=" "$REGISTRY" | cut -d= -f2)
VOLUME_NAME="diador-${CLIENT_NAME}_data"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUPS_DIR}/${CLIENT_NAME}-${TIMESTAMP}.tar.gz"

echo "==> Removing client '${CLIENT_NAME}' (port ${CLIENT_PORT})"
echo ""
echo "This will:"
echo "  1. Backup volume to ${BACKUP_FILE}"
echo "  2. Stop and remove the container"
echo "  3. Remove the named volume"
echo "  4. Remove from Nginx map block"
echo "  5. Remove registry and .env entries"
echo ""
read -p "Continue? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Aborted."
  exit 0
fi

# 1. Backup the named volume
echo "  [~] Backing up volume..."
mkdir -p "$BACKUPS_DIR"
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  docker run --rm \
    -v "${VOLUME_NAME}:/source:ro" \
    -v "${BACKUPS_DIR}:/backup" \
    debian:bookworm-slim \
    tar czf "/backup/${CLIENT_NAME}-${TIMESTAMP}.tar.gz" -C /source .
  echo "  [+] Backup saved: ${BACKUP_FILE}"
else
  echo "  [!] Volume '${VOLUME_NAME}' not found — skipping backup"
fi

# 2. Stop and remove the container
ENV_FILE="${CLIENTS_DIR}/${CLIENT_NAME}.env"
echo "  [~] Stopping container..."
if [[ -f "$ENV_FILE" ]]; then
  docker compose \
    -f "$COMPOSE_FILE" \
    --env-file "$ENV_FILE" \
    -p "diador-${CLIENT_NAME}" \
    down --volumes 2>/dev/null || true
  echo "  [+] Container stopped and removed"
else
  # Fallback: try to stop by project name
  docker compose -p "diador-${CLIENT_NAME}" down --volumes 2>/dev/null || true
  echo "  [+] Container stopped (no .env file found)"
fi

# 3. Remove named volume (if docker compose down --volumes didn't catch it)
if docker volume inspect "$VOLUME_NAME" &>/dev/null; then
  docker volume rm "$VOLUME_NAME" 2>/dev/null || true
  echo "  [+] Volume removed"
fi

# 4. Remove from Nginx map block
if [[ -f "$NGINX_CONF" ]]; then
  sed -i.bak "/${CLIENT_NAME}\.diador\.ai/d" "$NGINX_CONF"
  rm -f "${NGINX_CONF}.bak"
  echo "  [+] Removed from Nginx map block"

  if command -v nginx &>/dev/null && nginx -t &>/dev/null 2>&1; then
    nginx -s reload
    echo "  [+] Nginx reloaded"
  else
    echo "  [!] Nginx not available — skipping reload"
  fi
fi

# 5. Remove port registry entry
if [[ -f "$REGISTRY" ]]; then
  # Use a temp file to avoid sed -i portability issues
  grep -v "^${CLIENT_NAME}=" "$REGISTRY" > "${REGISTRY}.tmp"
  mv "${REGISTRY}.tmp" "$REGISTRY"
  echo "  [+] Removed from port registry"
fi

# 6. Remove per-client .env file
if [[ -f "$ENV_FILE" ]]; then
  rm "$ENV_FILE"
  echo "  [+] Removed ${ENV_FILE}"
fi

echo ""
echo "======================================"
echo " Client '${CLIENT_NAME}' removed"
echo " Backup: ${BACKUP_FILE}"
echo "======================================"
