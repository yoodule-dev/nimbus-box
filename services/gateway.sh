#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
# The gateway image is run unpacked under proot (no Docker). It expects the env
# that docker compose would normally inject, so we provide it here.
R="$(img gateway)"
mkdir -p "$H/data/gateway-auth"
export GATEWAY_PORT DISPLAY=:1
export QDRANT_URL="http://127.0.0.1:$QDRANT_PORT"
export REDIS_URL="redis://:${REDIS_PASSWORD}@127.0.0.1:$REDIS_PORT/0"
export FASTMCP_DOCKET_URL="$REDIS_URL"
export POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:$PG_PORT/postgres"
export OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://127.0.0.1:11434/api}"
hosts='gateway:*,nimbus-desktop:*,127.0.0.1:*,localhost:*,[::1]:*'
origins='http://localhost:3000,http://127.0.0.1:3000,http://localhost:8088,http://127.0.0.1:8088'
if [ -n "${NIMBUS_PUBLIC_HOST:-}" ]; then   # e.g. gateway.example.com
  hosts="$hosts,$NIMBUS_PUBLIC_HOST"; origins="$origins,https://$NIMBUS_PUBLIC_HOST"
fi
export MCP_ALLOWED_HOSTS="$hosts" MCP_ALLOWED_ORIGINS="$origins"
exec "$H/bin/proot" -0 -r "$R" -b /proc -b /dev \
  -b /etc/resolv.conf:/etc/resolv.conf \
  -b "$H/data/gateway-auth:/app/data/auth" \
  -b "$H/release/mcp.json:/app/mcp.json" \
  -w /app /entrypoint.sh
