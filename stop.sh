#!/usr/bin/env bash
# Stop everything. Each service runs in its own process group, so children die too.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. lib/common.sh
for name in proxy dashboard gateway qdrant redis postgres; do
  pidf="$H/run/$name.pid"; [ -f "$pidf" ] || continue
  pid=$(cat "$pidf")
  if kill -0 "$pid" 2>/dev/null; then
    log "stopping $name"
    if [ "$name" = postgres ]; then kill -INT "$pid" 2>/dev/null; else kill -TERM -- "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null; fi
    for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 1; done
  fi
  [ "$name" = postgres ] || kill -KILL -- "-$pid" 2>/dev/null   # sweep stragglers in the group
  rm -f "$pidf"
done
log "stopped"
