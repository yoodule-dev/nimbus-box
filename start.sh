#!/usr/bin/env bash
# Start Postgres, Redis, Qdrant, the gateway and the dashboard.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. lib/common.sh
[ -f "$H/.env" ] || die "run ./setup.sh first"
mkdir -p "$H/run" "$H/logs"

start_svc() {   # name port max-wait-seconds
  local name=$1 port=$2 wait=$3 pidf="$H/run/$1.pid" i
  if [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; then log "$name already running"; return 0; fi
  if port_open "$port"; then   # stale/missing pid file but the port is served: adopt the listener instead of dying (supervisor-safe)
    local lp; lp=$(ss -ltnpH "sport = :$port" 2>/dev/null | grep -o 'pid=[0-9]*' | head -1 | cut -d= -f2 || true)
    if [ -n "$lp" ]; then echo "$lp" > "$pidf"; log "$name already listening on :$port (adopted pid $lp)"; else warn "$name: :$port is in use but its pid is unknown - treating as running"; fi
    return 0
  fi
  setsid "$PWD/services/$name.sh" > "$H/logs/$name.log" 2>&1 < /dev/null &
  echo $! > "$pidf"
  for ((i = 0; i < wait; i++)); do
    if port_open "$port"; then log "$name is up (:$port)"; return 0; fi
    if ! kill -0 "$(cat "$pidf")" 2>/dev/null; then tail -15 "$H/logs/$name.log" >&2; die "$name exited during startup (log: $H/logs/$name.log)"; fi
    sleep 1
  done
  warn "$name is not listening on :$port after ${wait}s - it may still be starting (log: $H/logs/$name.log)"
}

# proxy first: the gateway image runs its own socat on :3000 (-> dashboard:7000, a docker hostname that
# does not resolve here); our https-aware proxy must own :3000 before it does.
start_svc proxy     "$PROXY_PORT"     30
start_svc postgres  "$PG_PORT"        30
start_svc redis     "$REDIS_PORT"     15
start_svc qdrant    "$QDRANT_PORT"    30
start_svc gateway   "$GATEWAY_PORT"   180
start_svc dashboard "$DASHBOARD_PORT" 180
start_svc desktop   "${DESKTOP_PORT:-6080}" 60   # noVNC desktop (needs the gateway to have created vnc_passwd)

log "Nimbus is running"
echo "   dashboard  http://localhost:$DASHBOARD_PORT   (public/preview: expose :$PROXY_PORT)"
echo "   gateway    http://localhost:$GATEWAY_PORT/mcp"
echo "   logs       $H/logs/"
