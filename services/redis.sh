#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
R="$(img redis)"
export LD_LIBRARY_PATH="$(libpath "$R")"
mkdir -p "$H/data/redis"
exec "$R/usr/local/bin/redis-server" --bind 127.0.0.1 --port "$REDIS_PORT" \
  --requirepass "$REDIS_PASSWORD" --dir "$H/data/redis" --appendonly yes
