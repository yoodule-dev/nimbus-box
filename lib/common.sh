# shellcheck shell=bash
# Shared helpers, sourced by setup.sh / start.sh / stop.sh / status.sh / services/*.sh

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Where everything (images, data, logs, .env) lives. Outside the repo on purpose,
# so a git commit can never pick up secrets.
if [ -z "${NIMBUS_BOX_HOME:-}" ]; then
  if [ -d /workspace/home ] && [ -w /workspace/home ]; then
    NIMBUS_BOX_HOME=/workspace/home/nimbus-box   # Upstash Box persistent volume
  else
    NIMBUS_BOX_HOME="$HOME/nimbus-box"
  fi
fi
export NIMBUS_BOX_HOME
H="$NIMBUS_BOX_HOME"

case "$(uname -m)" in
  aarch64|arm64) ARCH=arm64; PROOT_ARCH=aarch64; TRIPLET=aarch64-linux-gnu ;;
  x86_64|amd64)  ARCH=amd64; PROOT_ARCH=x86_64;  TRIPLET=x86_64-linux-gnu ;;
  *) echo "unsupported CPU: $(uname -m)" >&2; exit 1 ;;
esac

PG_PORT=5432; REDIS_PORT=6379; QDRANT_PORT=6333; GATEWAY_PORT=8088; DASHBOARD_PORT=7000

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

img()      { echo "$H/images/$1"; }
libpath()  { echo "$1/usr/lib/$TRIPLET:$1/lib/$TRIPLET"; }
port_open(){ (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
load_env() { [ -f "$H/.env" ] || die "missing $H/.env - run ./setup.sh first"; set -a; . "$H/.env"; set +a; }
pg_bin()   {
  local d
  d=$(ls -d "$(img postgres)"/usr/lib/postgresql/*/bin 2>/dev/null | sort -V | tail -1)
  [ -n "$d" ] || die "postgres image is not unpacked - run ./setup.sh"
  echo "$d"
}
