import { createServer } from 'node:http';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../dist');
const port = Number(process.env.PORT || 4173);
const types = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript', '.json': 'application/json', '.webp': 'image/webp', '.png': 'image/png', '.woff2': 'font/woff2', '.txt': 'text/plain' };
const server = createServer(async (request, response) => {
  try {
    const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
    if (pathname === '/simd-coin.json') {
      response.writeHead(200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      response.end(JSON.stringify({ name: 'Swarm Pepe', symbol: 'SPEPE', status: 'launching', token: null, chainName: 'Robinhood Chain', market: {} }));
      return;
    }
    if (pathname === '/') { response.writeHead(302, { Location: '/preview/' }); response.end(); return; }
    if (!pathname.startsWith('/preview/')) { response.writeHead(404); response.end('Not found'); return; }
    const file = path.resolve(root, pathname.slice('/preview/'.length) || 'index.html');
    if (file !== root && !file.startsWith(root + path.sep)) { response.writeHead(403); response.end(); return; }
    const resolved = (await stat(file)).isDirectory() ? path.join(file, 'index.html') : file;
    response.writeHead(200, { 'Content-Type': types[path.extname(resolved)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    response.end(await readFile(resolved));
  } catch {
    response.writeHead(404, { 'Content-Type': 'text/html' });
    response.end(await readFile(path.join(root, '404.html')));
  }
});
server.listen(port, '0.0.0.0', () => console.log(`Static preview: http://127.0.0.1:${port}/preview/ (local launching fixture; no market numbers)`));
