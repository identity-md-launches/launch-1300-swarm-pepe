import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { safeUrl, marketNumber, validToken, normalizeCoin, formatMarket } from '../site/data.js';
import { memes, memeSvg } from '../site/memes.js';
const origin = 'https://swarmpepe.si-md.xyz';
test('feed URLs allow HTTPS and same-origin local previews only', () => {
  assert.equal(safeUrl('/coin', origin), origin + '/coin');
  assert.equal(safeUrl('https://example.org/chart', origin), 'https://example.org/chart');
  for (const url of ['javascript:alert(1)', 'data:text/html,test', 'file:///tmp/test', 'http://example.org', 'https://user:pass@example.org']) assert.equal(safeUrl(url, origin), null);
});
test('market values reject missing, malformed, negative, and infinite values', () => {
  for (const value of [null, undefined, '', ' ', false, {}, -1, Infinity, 'abc']) assert.equal(marketNumber(value), null);
  assert.equal(marketNumber(0), 0); assert.equal(marketNumber('123.4'), 123.4);
});
test('token addresses must be complete and nonzero; no fallback address', () => {
  for (const value of [null, '', 'launching…', '0x123', '0x' + '0'.repeat(40)]) assert.equal(validToken(value), null);
  const fixture = '0x' + 'a'.repeat(40); assert.equal(validToken(fixture), fixture);
});
test('prelaunch payload has no invented metrics, token, or trading URL', () => {
  const value = normalizeCoin({ status: 'building', token: null, market: null }, origin);
  assert.equal(value.token, null); assert.equal(value.coinUrl, null); assert.equal(value.chartUrl, null);
  assert.deepEqual(value.market, { priceUsd: null, marketCap: null, volume24h: null });
});
test('malformed feed objects are rejected and logo URL is validated', () => {
  for (const value of [null, [], {}, 'bad']) assert.throws(() => normalizeCoin(value, origin));
  assert.equal(normalizeCoin({ logo: 'javascript:alert(1)' }, origin).logo, null);
  assert.equal(normalizeCoin({ logo: '/selected.webp' }, origin).logo, origin + '/selected.webp');
});
test('real zero is distinct from missing; tiny price remains readable', () => {
  assert.equal(formatMarket(null), '—'); assert.equal(formatMarket(0), '$0');
  assert.equal(formatMarket(1200000), '$1.2M'); assert.equal(formatMarket(0.0000000012, true), '$1.20e-9');
});
test('eight distinct original SVGs escape user text and image URLs', () => {
  assert.equal(memes.length, 8);
  assert.equal(new Set(memes.map(m => m.theme)).size, 8);
  const svg = memeSvg(0, '<script>alert("x")</script>', '& < >', 'https://example.org/x" onload="x');
  assert.ok(!svg.includes('<script>')); assert.ok(svg.includes('&lt;SCRIPT&gt;'));
  assert.ok(svg.includes('&quot; onload=&quot;'));
});
test('every page includes share metadata, favicon, language, and one main', async () => {
  for (const path of ['index.html', '404.html']) {
    const html = await readFile(new URL('../dist/' + path, import.meta.url), 'utf8');
    for (const attr of ['lang="en"', '<title>', 'name="description"', 'rel="icon"', 'property="og:title"', 'property="og:image"', 'name="twitter:card"']) assert.ok(html.includes(attr), attr);
    assert.equal((html.match(/<main[ >]/g) || []).length, 1);
  }
});
