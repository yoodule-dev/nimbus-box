# nimbus-box

Run [Nimbus](https://github.com/Yoodule/nimbus) on a machine with **no Docker and no root**
(Upstash Boxes, locked-down VMs, CI sandboxes, ...). One clone, one command:

```bash
git clone https://github.com/yoodule-dev/nimbus-box.git && cd nimbus-box
./setup.sh      # downloads + unpacks everything, generates secrets (~5-10 min, ~4.5 GB)
./start.sh      # starts the whole stack (~1 min)
```

Then open the dashboard on port **3000** (an https-aware proxy in front of the dashboard on 7000, see below); the gateway MCP endpoint is on port **8088** (`/mcp`).
Add your LLM key to `$NIMBUS_BOX_HOME/.env` (`OPENROUTER_API_KEYS=...`) and run `./stop.sh && ./start.sh`.

| command | what it does |
|---|---|
| `./setup.sh` | installs the latest release (or `NIMBUS_VERSION=v1.2.2 ./setup.sh`); safe to re-run |
| `./start.sh` / `./stop.sh` | start / stop all services (each in its own process group, no orphans) |
| `./status.sh` | shows which ports are up |

## Public URL / Upstash Box preview (plug and play)

Expose port **3000**, not 7000. Port 3000 is a tiny zero-dependency proxy (`proxy/server.js`, started by
`./start.sh`, runs on the dashboard image's node) that fixes the "sign-in page never opens" problem behind
preview/edge proxies: they terminate TLS but do not send `X-Forwarded-Proto`, so the dashboard redirected to
`http://...`, which nothing serves.

On an Upstash Box that is all you need:

1. `./setup.sh && ./start.sh`
2. create a preview for port **3000** (Box console, API or MCP `box_preview create`)
3. open `https://<box-id>-3000.preview.box.upstash.com` and create the first (admin) account right away
   (`NIMBUS_SIGN_UP_MODE=first_user_only`: whoever registers first is admin).

`NIMBUS_DASHBOARD_URL` (sign-in base URL) is derived automatically from `UPSTASH_BOX_ID`; elsewhere set it in
`.env` to your public URL. `PROXY_PORT` changes the port; `PROXY_FORWARD_PROTO=http` if you serve plain http.

The gateway image also tries to bind :3000 itself (a `socat` to the docker-only host `dashboard`); the proxy
starts first so it wins, and that `socat` error in the gateway log is harmless.

## If you have Docker, don't use this

`setup.sh` detects Docker and points you at the official installer
(`curl -fsSL https://nimbus.yoodule.com/install.sh | bash`). This repo exists for hosts where
that cannot work. `NIMBUS_FORCE=1` overrides the check.

## What it does

| component | how it runs here |
|---|---|
| Postgres 17 + pgvector, Redis, Qdrant | official images, unpacked and run natively (they are Debian 12 builds) |
| Nimbus gateway + dashboard | official `ghcr.io/yoodule/nimbus/*` images, unpacked and run under [proot](https://proot-me.github.io/) |

* Images come straight from the registries (`lib/pull-image.py`); the gateway image is pinned to the
  digest in the release's `compose.yaml`. `compose.yaml`/`mcp.json` are checksum-verified against the release `SHA256SUMS`.
* The `nimbus` CLI binary is **not** used. (As of v1.2.2 the `linux-arm64` archive ships an x86-64 binary.)
* Everything lives in `$NIMBUS_BOX_HOME` (default `/workspace/home/nimbus-box` on Upstash Boxes,
  otherwise `~/nimbus-box`) - **outside the repo**, so `git add -A` can never commit a secret.
* Passwords/keys are generated per install. Postgres, Redis and Qdrant listen on `127.0.0.1` only.
  The gateway (8088) and dashboard (7000) listen on all interfaces - expose them deliberately.

## Options

| variable | purpose |
|---|---|
| `NIMBUS_VERSION` | pin a release, e.g. `v1.2.2` (default: latest) |
| `NIMBUS_BOX_HOME` | install location |
| `NIMBUS_IMPORT_ENV` | copy keys from an existing `.env` (e.g. `~/.nimbus/.env`) on first setup |
| `NIMBUS_PUBLIC_HOST`, `NIMBUS_DASHBOARD_URL` | set in `.env` when serving behind a proxy / preview URL |
| `PG_SHARED_BUFFERS` | Postgres memory (default `256MB`) |

## Requirements

Linux `arm64` or `amd64`; `curl python3 tar sha256sum setsid`; glibc >= 2.36 (Debian 12, Ubuntu 24.04+);
~5 GB free; outbound HTTPS to `github.com`, `ghcr.io`, `registry-1.docker.io`; **ptrace allowed**
(proot needs it - `setup.sh` checks).

## Known limitations

* proot is slower than containers; fine for dev/testing, not a production deployment.
* Needs `OPENROUTER_API_KEYS` (or another provider key) for embeddings; without it the gateway logs 401s.
* The dashboard's file storage currently supports Vercel Blob only (upstream: S3 "coming soon"), so uploads need `BLOB_READ_WRITE_TOKEN`.
* The gateway logs `Redis connection error in cancellation listener` warnings; core task queues work. Cause not yet found.
* Services do not auto-restart when the host reboots - run `./start.sh` again.
* Not affiliated with Yoodule/Nimbus. Tested on Debian 12 / aarch64 (Upstash Box).

## Desktop (VNC)

`./start.sh` also starts the Nimbus desktop (Xvfb + x11vnc + noVNC). The proxy on `:3000` publishes it at `/desktop/` (websocket at `/websockify`), so the same public URL serves the dashboard and the desktop; the dashboard VNC panel is pointed there automatically. The VNC password is `VNC_PASSWORD` in `.env`.
