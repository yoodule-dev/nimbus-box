#!/usr/bin/env bash
# Logs who is eating the container pid budget (threads count against pids.max=512).
# Writes only when usage is high so the log stays small. Started once by start.sh.
LOG="${NIMBUS_BOX_HOME:-/workspace/home}/logs/pids.log"
THRESHOLD=${PID_LOG_THRESHOLD:-300}
mkdir -p "$(dirname "$LOG")"
while true; do
  cur=$(cat /sys/fs/cgroup/pids.current 2>/dev/null || echo 0)
  if [ "$cur" -ge "$THRESHOLD" ]; then
    {
      echo "== $(date -u +%FT%TZ) pids.current=$cur max=$(cat /sys/fs/cgroup/pids.max) events=$(tr '\n' ' ' < /sys/fs/cgroup/pids.events)"
      ps -eo nlwp,pid,comm --sort=-nlwp | head -8
      echo "chrome procs: $(pgrep -c chrome || true)"
    } >> "$LOG"
    if [ "$(stat -c %s "$LOG")" -gt 2000000 ]; then tail -c 1000000 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"; fi
  fi
  sleep 5
done
