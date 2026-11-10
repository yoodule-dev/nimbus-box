#!/usr/bin/env python3
"""Patch the gateway's MCP SDK so client_secret_basic token requests do not also carry client_id in the body
(idempotent; run by gateway.sh on every start).

With token_endpoint_auth_method=client_secret_basic the SDK sends an Authorization: Basic header AND leaves client_id in
the form body. Strict authorization servers (mcp.canva.com/token) reject that as "Client must not use multiple
authentication methods" (invalid_request, HTTP 400), so the connector never finishes its OAuth token exchange.
RFC 6749 s2.3.1/s3.2.1: a client that authenticates with Basic does not need client_id in the body.
Usage: mcp-oauth-patch.py <path to site-packages/mcp/client/auth/oauth2.py>
"""
import sys

p = sys.argv[1]
s = open(p).read()
DONE = 'k not in ("client_secret", "client_id")'
if DONE in s:
    print('mcp-oauth-patch: already applied')
    sys.exit(0)
old = '''            # Don't include client_secret in body for basic auth
            data = {k: v for k, v in data.items() if k != "client_secret"}'''
if s.count(old) != 1:
    print('mcp-oauth-patch: expected code not found (mcp SDK changed?), skipping')
    sys.exit(0)
new = '''            # Don't include client_secret or client_id in body for basic auth (nimbus: strict servers such as
            # mcp.canva.com reject Basic header + client_id in body as "multiple authentication methods")
            data = {k: v for k, v in data.items() if k not in ("client_secret", "client_id")}'''
open(p, 'w').write(s.replace(old, new, 1))
print('mcp-oauth-patch: applied')
