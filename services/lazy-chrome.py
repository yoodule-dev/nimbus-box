#!/usr/bin/env python3
"""On-demand Chrome for browser-mcp, with a lock so other browsers can take turns.

Listens on LAZY_PORT (default 9222, where browser-mcp expects Chrome's DevTools endpoint) and forwards to a
Chrome that is started on the first connection (on LAZY_BACKEND_PORT, default 9223) and stopped after
LAZY_IDLE_SECONDS (default 300) with no open connection. Usage: lazy-chrome.py <chrome command and args...>
While nothing uses the browser, no Chrome processes exist, which keeps small boxes under their process cap.

Control port (LAZY_CONTROL_PORT, default 9224): a client that sends "LOCK\n" gets Chrome stopped, receives "OK\n",
and holds the lock for as long as it keeps the connection open. While any lock is held Chrome is not started;
CDP connections wait for the lock (LAZY_LOCK_WAIT seconds, default 0 = as long as it takes) for the lock to be released. linkedin-chrome.py
uses this so linkedin-mcp's own Chromium and this one never run together (a small box cannot fit both).
"""
import asyncio, glob, os, signal, subprocess, sys, time

PORT = int(os.environ.get('LAZY_PORT', '9222'))
BACK = int(os.environ.get('LAZY_BACKEND_PORT', '9223'))
CONTROL = int(os.environ.get('LAZY_CONTROL_PORT', '9224'))
IDLE = int(os.environ.get('LAZY_IDLE_SECONDS', '300'))
LOCK_WAIT = int(os.environ.get('LAZY_LOCK_WAIT', '0'))  # 0 = wait for the lock as long as it takes
PROFILE = os.environ.get('LAZY_PROFILE_DIR', '')
CMD = sys.argv[1:]
if not CMD:
    sys.exit('usage: lazy-chrome.py <command...>')

proc = None
conns = 0
locks = 0
holders = {}      # id -> (mode, pid) of every open LOCK; mode is 'headless' or 'headed'
last = time.time()
lock = None


def alive():
    return proc is not None and proc.poll() is None


async def stop_chrome(grace=15):
    global proc
    p = proc
    proc = None
    if p is None or p.poll() is not None:
        return

    def kill():
        try:
            os.killpg(p.pid, signal.SIGTERM)
            p.wait(timeout=grace)
        except Exception:
            pass
        try:
            os.killpg(p.pid, signal.SIGKILL)    # sweep stragglers so they do not keep eating the process cap
        except Exception:
            pass

    await asyncio.get_running_loop().run_in_executor(None, kill)


def kill_tree(pid):
    """SIGKILL pid and all its descendants (linkedin's headless Chromium)."""
    kids = {}
    for d in glob.glob('/proc/[0-9]*'):
        try:
            st = open(d + '/stat').read()
            kids.setdefault(int(st[st.rindex(')') + 2:].split()[1]), []).append(int(d[6:]))
        except Exception:
            pass
    todo, order = [pid], []
    while todo:
        q = todo.pop()
        order.append(q)
        todo.extend(kids.get(q, []))
    for q in reversed(order):
        try:
            os.kill(q, signal.SIGKILL)
        except Exception:
            pass


async def preempt_headless():
    """A browser-mcp request outranks a headless linkedin browser: close it. A headed one (login) is left alone."""
    if locks > 0 and holders and all(m == 'headless' for m, _ in holders.values()):
        for _, pid in list(holders.values()):
            kill_tree(pid)
        for _ in range(40):
            if locks == 0:
                break
            await asyncio.sleep(0.25)


async def ensure():
    global proc
    await preempt_headless()
    deadline = time.time() + LOCK_WAIT if LOCK_WAIT > 0 else float("inf")
    while locks > 0 and time.time() < deadline:
        await asyncio.sleep(0.5)
    if locks > 0:
        return False
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
            if locks > 0 or proc.poll() is not None:
                if locks > 0:
                    await stop_chrome()
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


async def control(r, w):
    global locks, last
    held = False
    try:
        line = await asyncio.wait_for(r.readline(), 5)
        parts = line.split()
        if parts and parts[0] == b'LOCK':
            hid = id(w)
            mode = parts[1].decode() if len(parts) > 1 else 'headed'
            pid = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 0
            if mode == 'headless' and pid > 1:
                holders[hid] = (mode, pid)
            else:
                holders[hid] = ('headed', 0)
            locks += 1
            held = True
            await stop_chrome(1)    # linkedin has priority: no politeness, no waiting for a Chrome that is still starting
            w.write(b'OK\n')
            await w.drain()
            await r.read()          # hold the lock until the client closes the connection
    except Exception:
        pass
    finally:
        if held:
            locks -= 1
            holders.pop(id(w), None)
        last = time.time()
        try:
            w.close()
        except Exception:
            pass


async def reaper():
    while True:
        await asyncio.sleep(10)
        if alive() and conns == 0 and locks == 0 and time.time() - last > IDLE:
            await stop_chrome()


async def main():
    global lock
    lock = asyncio.Lock()
    srv = await asyncio.start_server(handle, '127.0.0.1', PORT)
    ctl = await asyncio.start_server(control, '127.0.0.1', CONTROL)
    asyncio.create_task(reaper())
    async with srv, ctl:
        await asyncio.gather(srv.serve_forever(), ctl.serve_forever())


asyncio.run(main())
