#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
R="$(img dashboard)"
export PORT="$DASHBOARD_PORT" HOSTNAME=0.0.0.0 NODE_ENV=production
export NIMBUS_GATEWAY_URL="http://127.0.0.1:$GATEWAY_PORT/mcp"
export POSTGRES_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:$PG_PORT/postgres"
export DATABASE_URL="$POSTGRES_URL"
export REDIS_URL="redis://:${REDIS_PASSWORD}@127.0.0.1:$REDIS_PORT/0"
# Public URL for sign-in. On an Upstash Box it is the preview of the proxy port (create that preview once);
# anywhere else set NIMBUS_DASHBOARD_URL in .env.
if [ -z "${NIMBUS_DASHBOARD_URL:-}" ] && [ -n "${UPSTASH_BOX_ID:-}" ]; then
  NIMBUS_DASHBOARD_URL="https://${UPSTASH_BOX_ID}-${PROXY_PORT}.preview.box.upstash.com"
fi
[ -n "${NIMBUS_DASHBOARD_URL:-}" ] && export BETTER_AUTH_URL="$NIMBUS_DASHBOARD_URL"
# VNC panel in the dashboard: noVNC is published by the proxy under /desktop/
export NEXT_PUBLIC_VNC_URL="${NIMBUS_VNC_URL:-${NIMBUS_DASHBOARD_URL:-http://localhost:$PROXY_PORT}/desktop}"
exec "$H/bin/proot" -0 -r "$R" -b /proc -b /dev -b /etc/resolv.conf:/etc/resolv.conf \
  -w /app node server.js
