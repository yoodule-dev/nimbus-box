# nimbus-box

Run [Nimbus](https://github.com/Yoodule/nimbus) on a machine with **no Docker and no root**
(Upstash Boxes, locked-down VMs, CI sandboxes, ...). One clone, one command:

```bash
git clone https://github.com/yoodule-dev/nimbus-box.git && cd nimbus-box
./setup.sh      # downloads + unpacks everything, generates secrets (~5-10 min, ~4.5 GB)
./start.sh      # starts the whole stack (~1 min)
```

Then open the dashboard on port **7000**; the gateway MCP endpoint is on port **8088** (`/mcp`).
Add your LLM key to `$NIMBUS_BOX_HOME/.env` (`OPENROUTER_API_KEYS=...`) and run `./stop.sh && ./start.sh`.

| command | what it does |
|---|---|
| `./setup.sh` | installs the latest release (or `NIMBUS_VERSION=v1.2.2 ./setup.sh`); safe to re-run |
| `./start.sh` / `./stop.sh` | start / stop all services (each in its own process group, no orphans) |
| `./status.sh` | shows which ports are up |

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
