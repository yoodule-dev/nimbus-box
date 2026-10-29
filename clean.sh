#!/usr/bin/env bash
# Free disk space by removing only things that are re-created on demand:
#   - npm download caches (the installed MCP servers live in _npx and are left alone)
#   - Chrome component/model caches in the browser-mcp profile (skipped while that Chrome is running)
# It does not touch .env, data/, the images, the uv cache or the Playwright browsers.
#   ./clean.sh            do it
#   ./clean.sh --dry-run  only show what would be removed
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. lib/common.sh

dry=0; [ "${1:-}" = "--dry-run" ] && dry=1
G="$(img gateway)"
prof="$H/data/gateway-home/browser-mcp-profile"
start=$(df -Pk "$H" | awk 'NR==2{print $4}')

rm_() {
  local p sz
  for p in "$@"; do
    [ -e "$p" ] || continue
    sz=$(du -sh "$p" 2>/dev/null | cut -f1)
    if [ "$dry" = 1 ]; then printf "would remove  %6s  %s\n" "$sz" "$p"; else rm -rf "$p"; printf "removed       %6s  %s\n" "$sz" "$p"; fi
  done
}

rm_ "$G"/home/*/.npm/_cacache "$G"/root/.npm/_cacache

if [ -d "$prof" ]; then
  if ps -eo args | grep -q '^/opt/google/chrome/'; then
    warn "skipped Chrome caches: the browser is running (run again once it has gone idle)"
  else
    rm_ "$prof"/optimization_guide_model_store "$prof"/WasmTtsEngine "$prof/Safe Browsing" \
        "$prof"/GrShaderCache "$prof"/ShaderCache "$prof/Default/Cache" "$prof/Default/Code Cache" "$prof/Default/GPUCache"
  fi
fi

if [ "$dry" = 0 ]; then
  end=$(df -Pk "$H" | awk 'NR==2{print $4}')
  log "freed about $(( (end - start) / 1024 )) MB; $(df -h "$H" | awk 'NR==2{print $4}') free"
fi
