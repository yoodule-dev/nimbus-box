#!/usr/bin/env python3
"""Browser wrapper for linkedin-mcp (set as its CHROME_PATH by services/gateway.sh).

linkedin-mcp starts its own Chromium, and a small box cannot run it next to browser-mcp's Chrome. This asks
lazy-chrome.py (control port LAZY_CONTROL_PORT, default 9224) to stop that Chrome and keep it stopped, then
replaces itself with the real Chromium. The lock connection stays open inside the Chromium process, so it is
released automatically when that browser exits. If the launcher is not running (NIMBUS_DESKTOP_BROWSER=always or
0) the browser just starts as normal.
"""
import glob, os, socket, sys

port = int(os.environ.get('LAZY_CONTROL_PORT', '9224'))
wait = float(os.environ.get('LAZY_LOCK_TIMEOUT', '60'))

base = os.environ.get('PLAYWRIGHT_BROWSERS_PATH', '')
cands = sorted(glob.glob(os.path.join(base, 'chromium-*', 'chrome-linux*', 'chrome')))
if not cands:
    sys.exit('linkedin-chrome: no chromium found under PLAYWRIGHT_BROWSERS_PATH=' + base)
exe = cands[-1]

try:
    s = socket.create_connection(('127.0.0.1', port), 2)
    s.settimeout(wait)
    mode = 'headless' if any(a.startswith('--headless') for a in sys.argv) else 'headed'
    s.sendall(('LOCK %s %d\n' % (mode, os.getpid())).encode())   # pid survives the execv below
    if s.recv(16).startswith(b'OK'):
        s.settimeout(None)
        os.set_inheritable(s.fileno(), True)
    else:
        s.close()
except OSError:
    pass

os.execv(exe, [exe] + sys.argv[1:])
