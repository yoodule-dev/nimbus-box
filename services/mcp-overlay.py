#!/usr/bin/env python3
"""Apply local settings to the gateway's release mcp.json (idempotent; run by services/gateway.sh on every start).

The gateway passes an MCP server only the env block from mcp.json (not its own environment), and mcp.json is a
downloaded release file, so the settings are re-applied each start (also after setup.sh re-downloads it).

  linkedin-mcp: CHROME_PATH -> services/linkedin-chrome.py, so its own Chromium takes turns with browser-mcp's
                Chrome instead of running next to it (a small box, pids.max=512, cannot fit both).
  any server env: the compose service host "redis" (e.g. nimbus-mcp's FASTMCP_DOCKET_URL) does not resolve without
                Docker, so it is rewritten to 127.0.0.1 - otherwise the docket worker retries forever (~2 warnings/s).
  Node servers (npx/node): UV_THREADPOOL_SIZE and --v8-pool-size in NODE_OPTIONS, which cut each Node process
                by several threads. Defaults are 1; set UV_THREADPOOL_SIZE / NIMBUS_V8_POOL_SIZE in .env to raise
                them on bigger machines (0 for NIMBUS_V8_POOL_SIZE leaves NODE_OPTIONS alone).
"""
import json, os, sys

p = sys.argv[1]
d = json.load(open(p))
srv = d.get('mcpServers', d)
changed = []

if 'linkedin-mcp' in srv:
    env = srv['linkedin-mcp'].setdefault('env', {})
    want = '/opt/nimbus-services/linkedin-chrome.py'
    if env.get('CHROME_PATH') != want:
        env['CHROME_PATH'] = want
        changed.append('linkedin-mcp CHROME_PATH')

n = 0
for name, cfg in srv.items():
    env = cfg.get('env') if isinstance(cfg, dict) else None
    for k, v in (env or {}).items():
        if isinstance(v, str) and '@redis:' in v:
            env[k] = v.replace('@redis:', '@127.0.0.1:')
            n += 1
if n:
    changed.append('%d redis host(s) -> 127.0.0.1' % n)

uv = os.environ.get('UV_THREADPOOL_SIZE', '1')
v8 = os.environ.get('NIMBUS_V8_POOL_SIZE', '1')
n = 0
for name, cfg in srv.items():
    if not isinstance(cfg, dict) or cfg.get('command') not in ('npx', 'node'):
        continue
    env = cfg.setdefault('env', {})
    before = json.dumps(env, sort_keys=True)
    env['UV_THREADPOOL_SIZE'] = uv
    if v8 != '0':
        opts = [o for o in env.get('NODE_OPTIONS', '').split() if not o.startswith('--v8-pool-size')]
        opts.append('--v8-pool-size=' + v8)
        env['NODE_OPTIONS'] = ' '.join(opts)
    if json.dumps(env, sort_keys=True) != before:
        n += 1
if n:
    changed.append('%d Node servers thread limits' % n)

if changed:
    json.dump(d, open(p, 'w'), indent=2)
    print('mcp.json: ' + ', '.join(changed))
