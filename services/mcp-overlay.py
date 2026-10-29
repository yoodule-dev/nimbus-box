#!/usr/bin/env python3
"""Apply local settings to the gateway's release mcp.json (idempotent; run by services/gateway.sh on every start).

The gateway passes an MCP server only the env block from mcp.json, and mcp.json is a downloaded release file, so
the settings are re-applied each start (also after setup.sh re-downloads it).

  linkedin-mcp: CHROME_PATH -> services/linkedin-chrome.py, so its own Chromium takes turns with browser-mcp's
  Chrome instead of running next to it (a small box, pids.max=512, cannot fit both).
"""
import json, sys

p = sys.argv[1]
d = json.load(open(p))
srv = d.get('mcpServers', d)
changed = False
if 'linkedin-mcp' in srv:
    env = srv['linkedin-mcp'].setdefault('env', {})
    want = '/opt/nimbus-services/linkedin-chrome.py'
    if env.get('CHROME_PATH') != want:
        env['CHROME_PATH'] = want
        changed = True
if changed:
    json.dump(d, open(p, 'w'), indent=2)
    print('mcp.json: linkedin-mcp CHROME_PATH set')
