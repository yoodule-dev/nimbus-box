#!/usr/bin/env bash
cd "$(dirname "${BASH_SOURCE[0]}")"
. lib/common.sh
rc=0
for s in postgres:$PG_PORT redis:$REDIS_PORT qdrant:$QDRANT_PORT gateway:$GATEWAY_PORT dashboard:$DASHBOARD_PORT proxy:$PROXY_PORT desktop:${DESKTOP_PORT:-6080}; do
  n=${s%%:*}; p=${s##*:}; pid="-"; [ -f "$H/run/$n.pid" ] && pid=$(cat "$H/run/$n.pid")
  if port_open "$p"; then printf '  %-10s up    :%-5s pid %s\n' "$n" "$p" "$pid"; else printf '  %-10s DOWN  :%-5s\n' "$n" "$p"; rc=1; fi
done
[ -f "$H/release/VERSION" ] && echo "  version    $(cat "$H/release/VERSION")"
exit $rc
