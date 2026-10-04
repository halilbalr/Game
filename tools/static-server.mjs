/**
 * Minimal static file server used by the evidence capture script.
 */
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.png': 'image/png',
  '.json': 'application/json', '.webmanifest': 'application/manifest+json', '.svg': 'image/svg+xml',
};

/**
 * @param {string} dir directory to serve
 * @param {number} port
 * @returns {Promise<http.Server>}
 */
export function serve(dir, port) {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    let file = path.join(dir, url.endsWith('/') ? `${url}index.html` : url);
    if (!file.startsWith(dir)) { res.writeHead(403); res.end(); return; }
    if (!fs.existsSync(file)) { res.writeHead(404); res.end('not found'); return; }
    if (fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
    res.writeHead(200, { 'content-type': TYPES[path.extname(file)] ?? 'application/octet-stream' });
    fs.createReadStream(file).pipe(res);
  });
  return new Promise((resolve) => server.listen(port, '127.0.0.1', () => resolve(server)));
}
