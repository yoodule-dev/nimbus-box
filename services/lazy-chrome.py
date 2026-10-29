#!/usr/bin/env python3
"""On-demand Chrome for browser-mcp.

Listens on LAZY_PORT (default 9222, where browser-mcp expects Chrome's DevTools endpoint) and forwards to a
Chrome that is started on the first connection (on LAZY_BACKEND_PORT, default 9223) and stopped after
LAZY_IDLE_SECONDS (default 300) with no open connection. Usage: lazy-chrome.py <chrome command and args...>
While nothing uses the browser, no Chrome processes exist, which keeps small boxes under their process cap.
"""
import asyncio, glob, os, signal, subprocess, sys, time

PORT = int(os.environ.get('LAZY_PORT', '9222'))
BACK = int(os.environ.get('LAZY_BACKEND_PORT', '9223'))
IDLE = int(os.environ.get('LAZY_IDLE_SECONDS', '300'))
PROFILE = os.environ.get('LAZY_PROFILE_DIR', '')
CMD = sys.argv[1:]
if not CMD:
    sys.exit('usage: lazy-chrome.py <command...>')

proc = None
conns = 0
last = time.time()
lock = None


def alive():
    return proc is not None and proc.poll() is None


async def ensure():
    global proc
    async with lock:
        if alive():
            return True
        for f in glob.glob(os.path.join(PROFILE, 'Singleton*')) if PROFILE else []:
            try:
                os.remove(f)
            except OSError:
                pass
        proc = subprocess.Popen(CMD, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(80):
            if proc.poll() is not None:
                return False
            try:
                _, w = await asyncio.open_connection('127.0.0.1', BACK)
                w.close()
                return True
            except OSError:
                await asyncio.sleep(0.5)
        return False


async def pipe(r, w):
    try:
        while True:
            d = await r.read(65536)
            if not d:
                break
            w.write(d)
            await w.drain()
    except Exception:
        pass
    finally:
        try:
            w.close()
        except Exception:
            pass


async def handle(cr, cw):
    global conns, last
    conns += 1
    try:
        if not await ensure():
            cw.close()
            return
        br, bw = await asyncio.open_connection('127.0.0.1', BACK)
        await asyncio.gather(pipe(cr, bw), pipe(br, cw))
    except Exception:
        pass
    finally:
        conns -= 1
        last = time.time()
        try:
            cw.close()
        except Exception:
            pass


async def reaper():
    global proc
    while True:
        await asyncio.sleep(10)
        if alive() and conns == 0 and time.time() - last > IDLE:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=15)
            except Exception:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except Exception:
                    pass
            proc = None


async def main():
    global lock
    lock = asyncio.Lock()
    srv = await asyncio.start_server(handle, '127.0.0.1', PORT)
    asyncio.create_task(reaper())
    async with srv:
        await srv.serve_forever()


asyncio.run(main())
