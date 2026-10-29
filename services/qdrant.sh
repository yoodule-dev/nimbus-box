#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
R="$(img qdrant)"
export LD_LIBRARY_PATH="$(libpath "$R")"
mkdir -p "$H/data/qdrant/snapshots"
cd "$R/qdrant"
export QDRANT__SERVICE__API_KEY="$QDRANT_API_KEY" QDRANT__SERVICE__HOST=127.0.0.1 \
  QDRANT__STORAGE__STORAGE_PATH="$H/data/qdrant" QDRANT__STORAGE__SNAPSHOTS_PATH="$H/data/qdrant/snapshots" \
  QDRANT__TELEMETRY_DISABLED=true
exec ./qdrant
