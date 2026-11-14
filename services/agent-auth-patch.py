#!/usr/bin/env python3
"""Patch nimbus-mcp's nimbus_agent so its bridge back to the gateway authenticates (idempotent; run by gateway.sh on every start).

nimbus_agent opens a fastmcp Client to NIMBUS_GATEWAY_URL with no credentials. With GATEWAY_AUTH_MODE=required the
gateway answers 401 and every call fails with "Gateway connection failed". The nimbus-mcp process already has
NIMBUS_SERVICE_KEY (the key the gateway accepts in x-nimbus-service-key), so send it on the bridge connection.
Usage: agent-auth-patch.py <path to nimbus_mcp/agent_body.py>
"""
import sys

p = sys.argv[1]
s = open(p).read()
if 'nimbus: authenticate the gateway bridge' in s:
    print('agent-auth-patch: already applied')
    sys.exit(0)
old = '        client = Client(url)\n'
if s.count(old) != 1:
    print('agent-auth-patch: expected code not found (nimbus-mcp changed?), skipping')
    sys.exit(0)
new = '''        # nimbus: authenticate the gateway bridge (GATEWAY_AUTH_MODE=required rejects unauthenticated clients)
        _bridge_key = os.environ.get("NIMBUS_SERVICE_KEY", "").strip()
        if _bridge_key:
            from fastmcp.client.transports import StreamableHttpTransport
            client = Client(StreamableHttpTransport(url, headers={"x-nimbus-service-key": _bridge_key}))
        else:
            client = Client(url)
'''
open(p, 'w').write(s.replace(old, new, 1))
print('agent-auth-patch: applied')
