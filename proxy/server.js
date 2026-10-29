// Tiny reverse proxy in front of the dashboard (zero dependencies, runs on the dashboard image's node).
//
// Why it exists: preview/edge proxies (e.g. Upstash Box previews) terminate TLS but do not send
// X-Forwarded-Proto. The dashboard then builds its sign-in redirects as http://..., which nothing
// serves, so the page never opens. This proxy marks requests as https so redirects stay on https.
//
// env: PORT (listen, default 3000), TARGET_HOST (default 127.0.0.1), TARGET_PORT (default 7000),
//      PROXY_FORWARD_PROTO (default https; set to http when serving plain http on a LAN)
const http = require('http');
const net = require('net');

const PORT = parseInt(process.env.PORT || '3000', 10);
const TARGET = { host: process.env.TARGET_HOST || '127.0.0.1', port: parseInt(process.env.TARGET_PORT || '7000', 10) };
const PROTO = process.env.PROXY_FORWARD_PROTO || 'https';

const fwd = (req) => ({
  ...req.headers,
  'x-forwarded-proto': req.headers['x-forwarded-proto'] || PROTO,
  'x-forwarded-host': req.headers['x-forwarded-host'] || req.headers.host || '',
});

const server = http.createServer((req, res) => {
  const up = http.request({ ...TARGET, method: req.method, path: req.url, headers: fwd(req) }, (r) => {
    res.writeHead(r.statusCode, r.headers);
    r.pipe(res);
  });
  up.on('error', () => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain' });
    res.end('Nimbus dashboard is not reachable (is it still starting? try ./status.sh)');
  });
  req.pipe(up);
});

// websockets (VNC view etc.)
server.on('upgrade', (req, socket, head) => {
  const up = net.connect(TARGET.port, TARGET.host, () => {
    const h = Object.entries(fwd(req)).map(([k, v]) => `${k}: ${v}`).join('\r\n');
    up.write(`${req.method} ${req.url} HTTP/1.1\r\n${h}\r\n\r\n`);
    up.write(head);
    up.pipe(socket);
    socket.pipe(up);
  });
  up.on('error', () => socket.destroy());
  socket.on('error', () => up.destroy());
});

server.listen(PORT, '0.0.0.0', () => console.log(`proxy listening on :${PORT} -> ${TARGET.host}:${TARGET.port} (forwarding proto ${PROTO})`));
