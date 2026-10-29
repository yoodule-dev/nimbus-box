#!/usr/bin/env bash
# Install Nimbus (gateway + dashboard + Postgres/pgvector + Redis + Qdrant)
# on a machine with NO Docker and NO root.   Usage:  ./setup.sh   then   ./start.sh
#
# Optional env:  NIMBUS_VERSION=v1.2.2   pin a release (default: latest)
#                NIMBUS_BOX_HOME=/path   where everything is installed
#                NIMBUS_IMPORT_ENV=file  copy keys from an existing .env (e.g. ~/.nimbus/.env)
#                NIMBUS_FORCE=1          run even if Docker is installed
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. lib/common.sh

for t in curl python3 tar sha256sum setsid; do command -v "$t" >/dev/null || die "missing required tool: $t"; done

if command -v docker >/dev/null 2>&1 && [ -z "${NIMBUS_FORCE:-}" ]; then
  log "Docker is installed - the official installer is the better choice:"
  echo "    curl -fsSL https://nimbus.yoodule.com/install.sh | bash"
  echo "  (set NIMBUS_FORCE=1 to use this Docker-free setup anyway)"
  exit 0
fi

# Postgres/Redis/Qdrant come from Debian-12 based images and run natively.
glibc=$(ldd --version 2>&1 | head -1 | grep -oE '[0-9]+\.[0-9]+$' || true)
if [ -n "$glibc" ] && [ "$(printf '%s\n2.36\n' "$glibc" | sort -V | head -1)" != "2.36" ]; then
  die "host glibc $glibc is too old (need >= 2.36: Debian 12, Ubuntu 24.04, ...)"
fi

mkdir -p "$H"/{bin,images,data,logs,run,release}
if [ -z "${NIMBUS_SKIP_DISK_CHECK:-}" ]; then
  avail=$(df -Pk "$H" | awk 'NR==2{print $4}')
  [ "$avail" -ge 5242880 ] || die "need ~5 GB free in $H (have $((avail/1024)) MB). NIMBUS_SKIP_DISK_CHECK=1 to ignore"
fi
log "installing into $H  (arch: $ARCH)"

# ---- proot (runs the gateway/dashboard images without Docker or root) ----
if ! { [ -x "$H/bin/proot" ] && "$H/bin/proot" -0 /bin/true 2>/dev/null; }; then
  log "installing proot"
  ok=
  for v in v5.3.0 v5.4.0; do
    if curl -fsSL -o "$H/bin/proot" "https://github.com/proot-me/proot/releases/download/$v/proot-$v-$PROOT_ARCH-static"; then
      chmod +x "$H/bin/proot"
      if "$H/bin/proot" -0 /bin/true 2>/dev/null; then ok=1; break; fi
    fi
  done
  [ -n "$ok" ] || die "could not install a working proot (is ptrace blocked on this host?)"
fi

# ---- which Nimbus release ----
VERSION="${NIMBUS_VERSION:-}"
if [ -z "$VERSION" ]; then
  loc=$(curl -fsSI https://github.com/Yoodule/nimbus/releases/latest | tr -d '\r' | awk -F': ' 'tolower($1)=="location"{print $2}')
  VERSION="${loc##*/}"
fi
printf '%s' "$VERSION" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+' || die "could not determine Nimbus version (got '$VERSION'); set NIMBUS_VERSION=vX.Y.Z"
log "Nimbus release: $VERSION"

# ---- release config files (compose.yaml, mcp.json), checksum-verified ----
# NOTE: the nimbus CLI binary in these archives is deliberately NOT used.
base="https://github.com/Yoodule/nimbus/releases/download/$VERSION"; asset="nimbus-linux-$ARCH.tar.gz"
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/$asset" "$base/$asset" && curl -fsSL -o "$tmp/SHA256SUMS" "$base/SHA256SUMS" || die "download failed from $base"
(cd "$tmp" && grep " $asset\$" SHA256SUMS | sha256sum -c - >/dev/null) || die "checksum mismatch for $asset"
tar -xzf "$tmp/$asset" -C "$H/release" --no-same-owner --exclude=nimbus --exclude='._*' 2>/dev/null || true
[ -f "$H/release/compose.yaml" ] && [ -f "$H/release/mcp.json" ] || die "release $VERSION is missing compose.yaml / mcp.json"
echo "$VERSION" > "$H/release/VERSION"

ref() { grep -E "^[[:space:]]*image:[[:space:]]*$1" "$H/release/compose.yaml" | head -1 | awk '{print $2}'; }
GATEWAY_REF=$(ref 'ghcr.io/yoodule/nimbus/gateway');  GATEWAY_REF="${GATEWAY_REF:-ghcr.io/yoodule/nimbus/gateway:$VERSION}"
DASHBOARD_REF="${NIMBUS_DASHBOARD_IMAGE:-ghcr.io/yoodule/nimbus/dashboard:$VERSION}"
PG_REF=$(ref 'pgvector/pgvector');                    PG_REF="${PG_REF:-pgvector/pgvector:pg17}"
REDIS_REF=$(ref 'redis:' | sed 's/-alpine$/-bookworm/'); REDIS_REF="${REDIS_REF:-redis:7.4.1-bookworm}"
QDRANT_REF=$(ref 'qdrant/qdrant');                    QDRANT_REF="${QDRANT_REF:-qdrant/qdrant:v1.12.4}"

# ---- unpack the images (parallel; the gateway is ~900 MB compressed) ----
names=(gateway dashboard postgres redis qdrant)
refs=("$GATEWAY_REF" "$DASHBOARD_REF" "$PG_REF" "$REDIS_REF" "$QDRANT_REF")
pids=()
log "pulling images (this takes a few minutes)"
for i in "${!names[@]}"; do
  python3 lib/pull-image.py "${refs[$i]}" "$(img "${names[$i]}")" "$ARCH" > "$H/logs/pull-${names[$i]}.log" 2>&1 &
  pids+=($!)
done
while :; do
  alive=0; for p in "${pids[@]}"; do kill -0 "$p" 2>/dev/null && alive=1; done
  [ "$alive" = 1 ] || break
  sleep 15; line=""; for n in "${names[@]}"; do line="$line $n:$(tail -1 "$H/logs/pull-$n.log" | cut -d' ' -f1)"; done; echo "   $line"
done
fail=0
for i in "${!names[@]}"; do
  if wait "${pids[$i]}"; then log "unpacked ${names[$i]}  (${refs[$i]%%@*})"
  else warn "FAILED: ${names[$i]}"; tail -5 "$H/logs/pull-${names[$i]}.log" >&2; fail=1; fi
done
[ "$fail" = 0 ] || die "image download failed; re-run ./setup.sh (finished images are skipped)"

# ---- .env with generated secrets (never inside the git repo) ----
rand() { python3 -c 'import secrets;print(secrets.token_urlsafe(24))'; }
e="$H/.env"; touch "$e"; chmod 600 "$e"
if [ -n "${NIMBUS_IMPORT_ENV:-}" ] && [ -f "$NIMBUS_IMPORT_ENV" ]; then
  log "importing keys from $NIMBUS_IMPORT_ENV"
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    k="${line%%=*}"; grep -q "^$k=" "$e" || printf '%s\n' "$line" >> "$e"
  done < "$NIMBUS_IMPORT_ENV"
fi
setdef() { grep -q "^$1=" "$e" || printf '%s=%s\n' "$1" "$2" >> "$e"; }
setdef POSTGRES_USER nimbus
setdef POSTGRES_PASSWORD "$(rand)"
setdef REDIS_PASSWORD "$(rand)"
setdef QDRANT_API_KEY "$(rand)"
setdef VNC_PASSWORD "$(rand)"
setdef BETTER_AUTH_SECRET "$(python3 -c 'import secrets;print(secrets.token_hex(32))')"
for k in OPENROUTER_API_KEYS ANTHROPIC_API_KEYS OPENAI_API_KEYS; do setdef "$k" ''; done

# ---- initialise the Postgres cluster ----
if [ ! -f "$H/data/postgres/PG_VERSION" ]; then
  log "initialising Postgres"
  load_env; B="$(pg_bin)"; pwf="$(mktemp "$H/run/pwf.XXXXXX")"
  printf '%s' "$POSTGRES_PASSWORD" > "$pwf"
  LD_LIBRARY_PATH="$(libpath "$(img postgres)")" "$B/initdb" -D "$H/data/postgres" -U "$POSTGRES_USER" \
    --pwfile="$pwf" --auth=scram-sha-256 -E UTF8 --locale=C.UTF-8 >/dev/null
  rm -f "$pwf"
fi

# ---- smoke checks ----
ls "$(img postgres)"/usr/lib/postgresql/*/lib/vector.so >/dev/null 2>&1 || die "pgvector missing from the postgres image"
LD_LIBRARY_PATH="$(libpath "$(img redis)")" "$(img redis)/usr/local/bin/redis-server" --version >/dev/null || die "redis does not run on this host"
"$H/bin/proot" -0 -r "$(img gateway)" -w / /bin/true || die "gateway image does not run under proot"
cp -n "$REPO_DIR/.env.example" "$H/.env.example" 2>/dev/null || true

log "done - Nimbus $VERSION is installed in $H"
cat <<MSG

  next:   ./start.sh          start everything (about a minute)
          ./status.sh         see what is running
          ./stop.sh           stop everything

  add your LLM key(s) to:  $H/.env   (OPENROUTER_API_KEYS=...)
  dashboard: http://localhost:$DASHBOARD_PORT   gateway MCP: http://localhost:$GATEWAY_PORT/mcp
MSG
