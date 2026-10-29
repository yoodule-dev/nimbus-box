#!/usr/bin/env bash
# Nimbus Desktop: Xvfb + fluxbox + x11vnc + noVNC (+ Chrome with CDP on :9222) from the gateway image.
# The unpacked gateway image's supervisor only runs the gateway, so the desktop the docker compose stack
# provides is started here. noVNC listens on 127.0.0.1:6080 only; proxy/server.js publishes it on :3000
# under /desktop/ (and /websockify), so one public URL serves the dashboard and the desktop.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"; load_env
R="$(img gateway)"
mkdir -p "$H/data/gateway-auth" "$H/data/gateway-home"
# x11vnc password file: the gateway normally creates it from VNC_PASSWORD; if it has not yet (fresh install,
# desktop starts right after the gateway), create it here so the desktop never depends on that timing.
if [ ! -s "$H/data/gateway-auth/vnc_passwd" ]; then
  [ -n "${VNC_PASSWORD:-}" ] || die "VNC_PASSWORD is not set in $H/.env (run ./setup.sh)"
  "$H/bin/proot" -0 -r "$R" -b /proc -b /dev -b "$H/data/gateway-auth:/app/data/auth" \
    x11vnc -storepasswd "$VNC_PASSWORD" /app/data/auth/vnc_passwd >/dev/null 2>&1
  [ -s "$H/data/gateway-auth/vnc_passwd" ] || die "could not create vnc_passwd"
fi
exec "$H/bin/proot" -0 -r "$R" -b /proc -b /dev -b /etc/resolv.conf:/etc/resolv.conf \
  -b "$H/data/gateway-auth:/app/data/auth" -b "$H/data/gateway-home:/root/.nimbus-gateway" -b "$REPO_DIR/services:/opt/nimbus-services" -w /root \
  /bin/bash -c '
    export DISPLAY=:1 HOME=/root
    rm -f /tmp/.X1-lock /tmp/.X11-unix/X1
    Xvfb :1 -screen 0 ${NIMBUS_DESKTOP_SIZE:-1440x900x24} -nolisten tcp &
    for i in $(seq 1 40); do xset -display :1 q >/dev/null 2>&1 && break; sleep 0.5; done
    fluxbox >/dev/null 2>&1 &
    x11vnc -display :1 -rfbauth /app/data/auth/vnc_passwd -rfbport 5900 -localhost -forever -shared -noxdamage -quiet >/dev/null 2>&1 &
    # Chrome for browser-mcp (it attaches to the DevTools endpoint on :9222).
    #   NIMBUS_DESKTOP_BROWSER=1 (default) on demand: services/lazy-chrome.py owns :9222, starts Chrome on the
    #                                      first connection and stops it after NIMBUS_BROWSER_IDLE_SECONDS (300) idle
    #   NIMBUS_DESKTOP_BROWSER=always      start Chrome now and keep it running
    #   NIMBUS_DESKTOP_BROWSER=0           no Chrome
    CHROME="/opt/google/chrome/google-chrome --no-sandbox --disable-gpu --disable-dev-shm-usage --no-first-run --no-restore-session --remote-debugging-address=127.0.0.1 --in-process-gpu --renderer-process-limit=1 --disable-background-networking --disable-component-update --disable-breakpad --user-data-dir=/root/.nimbus-gateway/browser-mcp-profile --disable-blink-features=AutomationControlled"
    URL="${NIMBUS_BROWSER_START_URL:-http://localhost:3000}"
    case "${NIMBUS_DESKTOP_BROWSER:-1}" in
      0) ;;
      always)
        rm -f /root/.nimbus-gateway/browser-mcp-profile/Singleton*
        $CHROME --remote-debugging-port=9222 "$URL" >/dev/null 2>&1 &
        ;;
      *)
        LAZY_PROFILE_DIR=/root/.nimbus-gateway/browser-mcp-profile LAZY_IDLE_SECONDS="${NIMBUS_BROWSER_IDLE_SECONDS:-300}" \
          python3 /opt/nimbus-services/lazy-chrome.py $CHROME --remote-debugging-port=9223 "$URL" >/dev/null 2>&1 &
        ;;
    esac
    export PYTHONPATH=/opt/novnc/utils/websockify
    exec python3 -m websockify --web /opt/novnc 127.0.0.1:6080 127.0.0.1:5900
  '
