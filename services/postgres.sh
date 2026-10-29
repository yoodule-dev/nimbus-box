#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
B="$(pg_bin)"; R="$(img postgres)"
export LD_LIBRARY_PATH="$(libpath "$R")"
mkdir -p "$H/run/pg"
exec "$B/postgres" -D "$H/data/postgres" \
  -c listen_addresses=127.0.0.1 -c port="$PG_PORT" \
  -c unix_socket_directories="$H/run/pg" \
  -c shared_buffers="${PG_SHARED_BUFFERS:-256MB}"
