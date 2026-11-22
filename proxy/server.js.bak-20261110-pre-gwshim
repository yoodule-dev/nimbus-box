// Tiny reverse proxy in front of the dashboard (zero dependencies, runs on the dashboard image's node).
//
// Why it exists: preview/edge proxies (e.g. Upstash Box previews) terminate TLS but do not send
// X-Forwarded-Proto. The dashboard then builds its sign-in redirects as http://..., which nothing
// serves, so the page never opens. This proxy marks requests as https so redirects stay on https.
//
// env: PORT (listen, default 3000), TARGET_HOST (default 127.0.0.1), TARGET_PORT (default 7000),
//      PROXY_FORWARD_PROTO (default auto: http for localhost, https otherwise; set http for a plain-http LAN),
//      DESKTOP_PORT (noVNC, default 6080): /desktop/* (prefix stripped) and /websockify go there
const http = require('http');
const net = require('net');

const PORT = parseInt(process.env.PORT || '3000', 10);
const TARGET = { host: process.env.TARGET_HOST || '127.0.0.1', port: parseInt(process.env.TARGET_PORT || '7000', 10) };
const PROTO = process.env.PROXY_FORWARD_PROTO;   // unset = auto: http for localhost, https otherwise
const isLocalHost = (h) => /^(localhost|127\.0\.0\.1|\[::1\])(:|$)/.test(h || '');
const DESKTOP = { host: '127.0.0.1', port: parseInt(process.env.DESKTOP_PORT || '6080', 10) };

// pick upstream + rewritten path: noVNC lives under /desktop/ (and its websocket at /websockify)
const route = (url) => {
  if (url === '/desktop') return { t: DESKTOP, path: '/vnc.html' };
  if (url.startsWith('/desktop/')) return { t: DESKTOP, path: url.slice('/desktop'.length) };
  if (url.startsWith('/websockify')) return { t: DESKTOP, path: url };
  return { t: TARGET, path: url };
};

const fwd = (req) => ({
  ...req.headers,
  'x-forwarded-proto': req.headers['x-forwarded-proto'] || PROTO || (isLocalHost(req.headers.host) ? 'http' : 'https'),
  'x-forwarded-host': req.headers['x-forwarded-host'] || req.headers.host || '',
});

const server = http.createServer((req, res) => {
  const r0 = route(req.url);
  const up = http.request({ ...r0.t, method: req.method, path: r0.path, headers: fwd(req) }, (r) => {
    res.writeHead(r.statusCode, r.headers);
    r.pipe(res);
  });
  up.on('error', () => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' });
    res.end('Upstream is not reachable (is it still starting? try ./status.sh)');
  });
  req.pipe(up);
});

// websockets (VNC view etc.)
server.on('upgrade', (req, socket, head) => {
  const r0 = route(req.url);
  const up = net.connect(r0.t.port, r0.t.host, () => {
    const h = Object.entries(fwd(req)).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    up.write(`${req.method} ${r0.path} HTTP/1.1\r\n${h}\r\n\r\n`);
    up.write(head);
    up.pipe(socket);
    socket.pipe(up);
  });
  up.on('error', () => socket.destroy());
  socket.on('error', () => up.destroy());
});

server.listen(PORT, '0.0.0.0', () => console.log(`proxy listening on :${PORT} -> ${TARGET.host}:${TARGET.port} (forwarding proto ${PROTO})`));
