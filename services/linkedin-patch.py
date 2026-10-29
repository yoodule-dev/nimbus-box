#!/usr/bin/env python3
"""Patch linkedin-mcp so it notices a browser that was closed behind its back (idempotent; run by gateway.sh on every start).

linkedin-mcp keeps one browser object for the whole session and never checks it is still alive. When a browser-mcp
request preempts linkedin's headless Chromium (services/lazy-chrome.py), the next linkedin call would fail on that
dead handle. This makes get_or_create_browser() probe the page first and open a fresh browser if the probe fails.
Usage: linkedin-patch.py <path to linkedin_mcp_server/drivers/browser.py>
"""
import sys

p = sys.argv[1]
s = open(p).read()
MARK = '# nimbus: liveness probe'
if MARK in s:
    print('linkedin-patch: already applied')
    sys.exit(0)
old = '    if _browser is not None:\n        return _browser\n'
if s.count(old) != 1:
    print('linkedin-patch: expected code not found (linkedin-mcp changed?), skipping')
    sys.exit(0)
new = '''    if _browser is not None:  # nimbus: liveness probe
        import asyncio as _aio
        try:
            await _aio.wait_for(_browser.page.evaluate("1"), 5)
            return _browser
        except Exception:
            logger.warning("Browser was closed behind our back; starting a new one")
            dead, _browser = _browser, None
            try:
                await _aio.wait_for(dead.close(), 10)
            except Exception:
                pass
'''
open(p, 'w').write(s.replace(old, new, 1))
print('linkedin-patch: applied')
