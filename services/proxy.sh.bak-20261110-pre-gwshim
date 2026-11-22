#!/usr/bin/env bash
# https-aware reverse proxy in front of the dashboard (see proxy/server.js).
# Runs on the dashboard image's node, so the host needs no node install.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
R="$(img dashboard)"
export PORT="$PROXY_PORT" TARGET_PORT="$DASHBOARD_PORT"
exec "$H/bin/proot" -0 -r "$R" -b /proc -b /dev -b /etc/resolv.conf:/etc/resolv.conf \
  -b "$REPO_DIR/proxy:/proxy" -w /proxy node /proxy/server.js
