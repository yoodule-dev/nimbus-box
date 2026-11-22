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
    print('linkedin-patch: browser liveness probe already applied')
else:
    old = '    if _browser is not None:\n        return _browser\n'
    if s.count(old) != 1:
        raise SystemExit('linkedin-patch: expected browser code not found; refusing patch')
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
    print('linkedin-patch: browser liveness probe applied')

# The MCP server is long-lived, but its persistent Chromium must not be. Close it
# after an idle period between serialized tool calls so it cannot consume the
# Upstash Box process budget indefinitely. The middleware schedules closure only
# after a tool finishes, and cancels it when the next tool starts.
middleware = __import__('pathlib').Path(p).parents[1] / 'sequential_tool_middleware.py'
m = middleware.read_text()
marker = '# nimbus: idle browser reaper'
if marker not in m:
    old_init = '''    def __init__(self) -> None:
        self._lock = asyncio.Lock()
'''
    new_init = '''    def __init__(self) -> None:
        self._lock = asyncio.Lock()
        import os
        self._idle_timeout = max(0.0, float(os.getenv("LINKEDIN_BROWSER_IDLE_SECONDS", "120")))
        self._idle_close_task: asyncio.Task | None = None

    def _cancel_idle_close(self) -> None:
        task, self._idle_close_task = self._idle_close_task, None
        if task is not None and not task.done():
            task.cancel()

    async def _close_after_idle(self) -> None:
        try:
            await asyncio.sleep(self._idle_timeout)
            async with self._lock:
                from linkedin_mcp_server.drivers.browser import close_browser
                await close_browser()
                logger.info("LinkedIn browser closed after %.0fs idle", self._idle_timeout)
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Failed to close idle LinkedIn browser")
        finally:
            if self._idle_close_task is asyncio.current_task():
                self._idle_close_task = None
'''
    assert m.count(old_init)==1, 'middleware constructor changed; refusing patch'
    m=m.replace(old_init,new_init,1)
    lock_marker='''        async with self._lock:
            wait_seconds = time.perf_counter() - wait_started
'''
    lock_replacement='''        async with self._lock:
            self._cancel_idle_close()  # nimbus: idle browser reaper
            wait_seconds = time.perf_counter() - wait_started
'''
    assert m.count(lock_marker)==1, 'middleware lock section changed; refusing patch'
    m=m.replace(lock_marker,lock_replacement,1)
    final_marker='''                logger.debug(
                    "Released scraper lock for tool '%s' after %.3fs",
                    tool_name,
                    hold_seconds,
                )
'''
    final_replacement=final_marker+'''                if self._idle_timeout > 0:
                    self._idle_close_task = asyncio.create_task(
                        self._close_after_idle(), name="linkedin-browser-idle-close"
                    )
'''
    assert m.count(final_marker)==1, 'middleware finalizer changed; refusing patch'
    m=m.replace(final_marker,final_replacement,1)
    middleware.write_text(m)
    print('linkedin-patch: idle browser reaper applied (120s default)')
else:
    print('linkedin-patch: idle browser reaper already applied')
