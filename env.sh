#!/usr/bin/env bash
# Add or update variables in the Nimbus .env without hand-editing it.
#
#   ./env.sh 'KEY=value KEY2=value2 ...'      the simple way: ONE quoted string of pairs (single quotes)
#   ./env.sh KEY=value KEY2=value2            or one pair per argument
#   ./env.sh < my.env                         a whole .env-style file on stdin
#   cat my.env | ./env.sh                     ... same, piped
#   ./env.sh -f /path/to/my.env               same as stdin, from a file
#   ./env.sh --no-restart ...                 write only; restart later with ./stop.sh && ./start.sh
#   ./env.sh --list                           which keys are set / empty (never prints values)
#
# Standard .env rules are respected: blank lines and # comments are ignored, a leading `export `
# is accepted, matching "..." or '...' quotes around a value are removed, and the value is written
# back quoted only when it needs it (spaces, $, &, #, ...). The real file is sourced by bash, so
# that quoting is what keeps odd values safe. Existing keys are updated in place (order, comments
# and other lines are kept), new keys are appended, the file stays chmod 600 and the previous
# version is kept as .env.bak. Values are never printed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
. lib/common.sh

ENV_FILE="${ENV_FILE:-$H/.env}"
restart=1; list=0; src=""; args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --restart) restart=1 ;;
    --no-restart) restart=0 ;;
    --list)    list=1 ;;
    -f|--file) shift; [ $# -gt 0 ] || die "-f needs a file"; src="$1" ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)         args+=("$1") ;;
  esac
  shift
done

[ -f "$ENV_FILE" ] || die "missing $ENV_FILE - run ./setup.sh first"

if [ "$list" = 1 ]; then
  ENV_FILE="$ENV_FILE" python3 - <<'PY'
import os, re
for l in open(os.environ["ENV_FILE"]).read().splitlines():
    m = re.match(r'^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', l)
    if m:
        v = m.group(2).strip()
        print(("EMPTY  " if v in ("", "''", '""') else "set    ") + m.group(1))
PY
  exit 0
fi

# gather input: -f file, then arguments, then stdin (only when piped/redirected)
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
[ -n "$src" ] && { [ -f "$src" ] || die "no such file: $src"; cat "$src" >> "$tmp"; echo >> "$tmp"; }
if [ ${#args[@]} -gt 0 ]; then printf '%s\n' "${args[@]}" >> "$tmp"
elif [ -z "$src" ] && [ ! -t 0 ]; then cat >> "$tmp"
fi
[ -s "$tmp" ] || die "nothing to add. Usage: ./env.sh KEY=value ...   or   ./env.sh < file.env   (see --help)"

INPUT="$tmp" ENV_FILE="$ENV_FILE" python3 - <<'PY'
import os, re, shlex, shutil, sys, tempfile

PAIR = re.compile(r'^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$', re.S)

def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
        return v[1:-1]
    return v

def parse(text):
    pairs = []
    for line in text.splitlines():
        s = line.strip()
        if not s or s.startswith('#'):
            continue
        # one line holding several pairs:  A=1 B="two words" C=3
        try:
            toks = shlex.split(s)
        except ValueError:
            toks = []
        if len(toks) > 1 and all(PAIR.match(t) for t in toks):
            for t in toks:
                m = PAIR.match(t); pairs.append((m.group(1), m.group(2)))
            continue
        m = PAIR.match(s)
        if not m:
            print(f"skipped (not KEY=value): {s.split('=')[0][:40]}", file=sys.stderr)
            continue
        pairs.append((m.group(1), unquote(m.group(2))))
    return pairs

def fmt(v):
    if re.fullmatch(r'[A-Za-z0-9_@%+=:,./-]*', v):
        return v
    return "'" + v.replace("'", "'\\''") + "'"

pairs = parse(open(os.environ["INPUT"]).read())
if not pairs:
    sys.exit("error: no valid KEY=value pairs found")
new = {}
for k, v in pairs:
    new[k] = v          # last one wins

path = os.environ["ENV_FILE"]
d = os.path.dirname(path) or '.'
lines = open(path).read().splitlines()
out, seen, added, updated = [], set(), [], []
for l in lines:
    m = re.match(r'^(\s*(?:export\s+)?)([A-Za-z_][A-Za-z0-9_]*)=', l)
    if m and m.group(2) in new:
        k = m.group(2)
        if k in seen:
            continue                      # drop duplicate definitions of the same key
        seen.add(k); updated.append(k)
        out.append(f"{m.group(1)}{k}={fmt(new[k])}")
    else:
        out.append(l)
for k, v in new.items():
    if k not in seen:
        out.append(f"{k}={fmt(v)}"); added.append(k)

bak = os.path.join(d, os.path.basename(path) + '.bak')
shutil.copy2(path, bak); os.chmod(bak, 0o600)
fd, tmpf = tempfile.mkstemp(dir=d)
with os.fdopen(fd, 'w') as f:
    f.write('\n'.join(out) + '\n')
os.chmod(tmpf, 0o600)
os.replace(tmpf, path)
for k in updated: print(f"updated  {k}")
for k in added:   print(f"added    {k}")
PY

if [ "$restart" = 1 ]; then
  log "restarting so the new values take effect"
  ./stop.sh; ./start.sh
else
  echo "Not restarted. Apply with: ./stop.sh && ./start.sh"
fi
