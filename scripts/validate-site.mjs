import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createRequire } from 'node:module';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const toolRoot = process.env.SITE_TOOLS || '/tmp/swarmpepe-site-tools';
const requireTools = createRequire(path.join(toolRoot, 'package.json'));
const { chromium } = requireTools('playwright');
const axeSource = await readFile(requireTools.resolve('axe-core/axe.min.js'), 'utf8');
const port = 4174;
const url = `http://127.0.0.1:${port}/preview/`;
const evidence = path.join(root, 'test/scratch/site');
await mkdir(evidence, { recursive: true });
const report = { checks: [], viewports: [], downloads: [], accessibility: [], consoleErrors: [], resourceFailures: [] };
const server = spawn(process.execPath, ['scripts/preview-site.mjs'], { cwd: root, env: { ...process.env, PORT: String(port) }, stdio: ['ignore', 'pipe', 'inherit'] });
let browser;
function pass(name) { report.checks.push(name); console.log('PASS', name); }
try {
  await new Promise((resolve, reject) => { server.stdout.once('data', resolve); server.once('error', reject); server.once('exit', code => { if (code) reject(new Error(`Preview exited: ${code}`)); }); });
  browser = await chromium.launch({ headless: true, ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}), args: ['--no-sandbox'] });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 }, acceptDownloads: true, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await context.newPage();
  page.setDefaultTimeout(12000);
  let expectedFailure = false;
  page.on('pageerror', error => report.consoleErrors.push(error.message));
  page.on('console', message => { if (message.type() === 'error' && !expectedFailure) report.consoleErrors.push(message.text()); });
  page.on('requestfailed', request => { if (!expectedFailure) report.resourceFailures.push(`${request.failure()?.errorText}: ${request.url()}`); });
  page.on('response', response => { if (response.status() >= 400 && !expectedFailure) report.resourceFailures.push(`${response.status()} ${response.url()}`); });
  let requestCount = 0;
  let payload = { status: 'building', token: null, market: null };
  let responseStatus = 200;
  await page.route('**/simd-coin.json', route => { requestCount++; return route.fulfill({ status: responseStatus, contentType: 'application/json', body: JSON.stringify(payload) }); });
  await page.goto(url);
  await page.locator('#data-status').filter({ hasText: 'Launching…' }).waitFor();
  await page.evaluate(() => document.fonts.ready);
  assert.equal(await page.locator('#contract-address').textContent(), 'launching…');
  assert.ok(await page.locator('#copy-contract').isDisabled());
  assert.equal(await page.locator('#stat-price').textContent(), '—');
  assert.equal(await page.locator('.hero [data-buy]').getAttribute('href'), '#buy');
  pass('Prelaunch shows no invented address or market data; unavailable copy is disabled');

  for (const width of [320, 360, 375, 390, 600, 601, 768, 850, 1024, 1440, 1920]) {
    await page.setViewportSize({ width, height: 900 });
    const measure = await page.evaluate(() => ({ viewport: innerWidth, page: document.documentElement.scrollWidth }));
    assert.ok(measure.page <= width, `Horizontal overflow at ${width}: ${measure.page}`);
    report.viewports.push(measure);
  }
  pass('Home has no horizontal overflow from 320 through 1920px at 11 tested widths');
  await page.setViewportSize({ width: 390, height: 844 });
  await page.evaluate(() => scrollTo(0, 0));
  const actionBox = await page.locator('.hero [data-buy]').boundingBox();
  assert.ok(actionBox.y + actionBox.height < 844);
  assert.ok(await page.locator('h1').isVisible());
  pass('390px first screen contains product, explanation and main action');

  await page.getByRole('button', { name: 'Menu', exact: false }).click();
  assert.equal(await page.locator('.menu-toggle').getAttribute('aria-expanded'), 'true');
  await page.keyboard.press('Escape');
  assert.equal(await page.locator('.menu-toggle').getAttribute('aria-expanded'), 'false');
  assert.ok(await page.locator('.menu-toggle').evaluate(el => el === document.activeElement));
  await page.locator('.menu-toggle').click();
  await page.locator('#main-nav a[href="#memes"]').click();
  assert.equal(await page.locator('.menu-toggle').getAttribute('aria-expanded'), 'false');
  pass('Mobile navigation opens, follows anchors, closes on Escape and restores focus');

  await page.locator('[data-step="1"]').click();
  assert.equal(await page.locator('#step-title').textContent(), 'Fuel up for the pond.');
  await page.locator('#next-step').click();
  assert.ok(await page.locator('#step-buy').isVisible());
  assert.ok(await page.locator('#step-buy').evaluate(el => el === document.activeElement));
  await page.locator('.launch-rules summary').click();
  assert.ok(await page.locator('.launch-rules').evaluate(el => el.open));
  pass('Buying guide advances and moves focus to the coin action; launch rules expand');

  await page.locator('#ribbit').click({ clickCount: 3 });
  assert.equal(await page.locator('#vibe-count').textContent(), '15%');
  assert.equal(await page.locator('.vibe-track').getAttribute('aria-valuenow'), '15');
  await page.locator('#drag-sticker').focus();
  await page.keyboard.press('ArrowLeft');
  assert.ok((await page.locator('#drag-sticker').evaluate(el => el.style.translate)).startsWith('-14px'));
  await page.keyboard.press('Home');
  assert.equal(await page.locator('#drag-sticker').evaluate(el => el.style.translate), '0px');
  const stickerBox = await page.locator('#drag-sticker').boundingBox();
  await page.mouse.move(stickerBox.x + 30, stickerBox.y + 20); await page.mouse.down();
  await page.mouse.move(stickerBox.x - 30, stickerBox.y - 30, { steps: 5 }); await page.mouse.up();
  assert.notEqual(await page.locator('#drag-sticker').evaluate(el => el.style.translate), '0px');
  pass('Swarm signal counter and sticker dragging work with pointer and keyboard');

  await page.locator('#copy-link').click();
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), 'https://swarmpepe.si-md.xyz/');
  const shareUrls = await page.locator('[data-share]').evaluateAll(links => links.map(link => link.href));
  assert.equal(new Set(shareUrls).size, 3);
  assert.ok(shareUrls.every(link => new URL(link).hostname === 'x.com' && new URL(link).searchParams.get('text').includes('$SPEPE')));
  pass('Three distinct X intents and copy-site-link produce the intended share content');

  // Synthetic test data only: this address and these figures never ship as site defaults.
  payload = { status: 'live', token: '0x' + 'a'.repeat(40), coinUrl: 'https://example.org/coin', chartUrl: 'https://example.org/chart', logo: '/preview/assets/social.png', market: { priceUsd: 0.0000123, marketCap: 12300, volume24h: 4567 } };
  await page.locator('#refresh-data').click();
  await page.locator('#data-status').filter({ hasText: 'Feed updated' }).waitFor();
  assert.equal(await page.locator('#contract-address').textContent(), payload.token);
  assert.equal(await page.locator('.hero [data-buy]').getAttribute('href'), payload.coinUrl);
  assert.equal(await page.locator('.hero [data-chart]').getAttribute('href'), payload.chartUrl);
  await page.waitForFunction(() => document.querySelector('.hero-mascot').src.endsWith('/assets/social.png'));
  await page.locator('#copy-contract').click();
  assert.equal(await page.evaluate(() => navigator.clipboard.readText()), payload.token);
  assert.equal(await page.locator('#stat-cap').textContent(), '$12.3K');
  pass('Live fixture updates metrics, deployed address, clipboard, Buy/Chart URLs and selected logo');
  for (const width of [320, 390, 768, 1440]) {
    await page.setViewportSize({width, height:1000});
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), width, `Live-value overflow at ${width}`);
    assert.ok(await page.locator('#stat-price').evaluate(el => el.scrollWidth <= el.clientWidth), `Price clips at ${width}`);
  }
  pass('Long deployed address and small live price fit all four tested widths');

  const popupPromise = page.waitForEvent('popup');
  await page.route('https://example.org/**', route => route.fulfill({ contentType: 'text/html', body: '<title>Trading destination test</title>' }));
  await page.locator('.hero [data-buy]').click();
  const popup = await popupPromise; await popup.waitForLoadState();
  assert.equal(popup.url(), payload.coinUrl); await popup.close();
  pass('Primary Buy opens the actual feed destination in a new tab');

  const timerPage = await context.newPage();
  let timerRequests = 0;
  await timerPage.clock.install();
  await timerPage.route('**/simd-coin.json', route => {
    timerRequests++;
    return route.fulfill({contentType:'application/json',body:JSON.stringify({status:'building',token:null,market:{}})});
  });
  await timerPage.goto(url);
  await timerPage.locator('#data-status').filter({hasText:'Launching…'}).waitFor();
  await timerPage.locator('#refresh-data:not([disabled])').waitFor();
  const timerBefore = timerRequests;
  const timerResponse = timerPage.waitForResponse(response => response.url().endsWith('/simd-coin.json'));
  await timerPage.clock.runFor(30050);
  await timerResponse;
  assert.ok(timerRequests > timerBefore);
  await timerPage.close();
  await page.bringToFront();
  await page.locator('#refresh-data:not([disabled])').waitFor();
  pass('Automatic feed refresh runs at 30 seconds under an isolated browser virtual clock');

  expectedFailure = true; responseStatus = 503;
  await page.locator('#refresh-data').click();
  await page.locator('#data-status').filter({ hasText: 'last-known data' }).waitFor();
  assert.equal(await page.locator('#stat-cap').textContent(), '$12.3K');
  assert.equal(await page.locator('#contract-address').textContent(), payload.token);
  responseStatus = 200; payload = { status: 'building', token: null, market: null };
  await page.locator('#refresh-data').click();
  await page.locator('#data-status').filter({ hasText: 'Launching…' }).waitFor();
  expectedFailure = false;
  assert.equal(await page.locator('#stat-cap').textContent(), '—');
  assert.ok(await page.locator('#copy-contract').isDisabled());
  pass('HTTP failure labels retained values as last-known; recovery resets prelaunch state correctly');

  await page.setViewportSize({ width: 1440, height: 1000 });
  const downloadButtons = page.locator('.download-small');
  for (let i = 0; i < 8; i++) {
    const [download] = await Promise.all([page.waitForEvent('download'), downloadButtons.nth(i).click()]);
    const target = path.join(evidence, download.suggestedFilename()); await download.saveAs(target);
    const png = await readFile(target);
    assert.equal(png.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
    assert.equal(png.readUInt32BE(16), 1080); assert.equal(png.readUInt32BE(20), 1080);
    assert.ok(png.length > 50000);
    report.downloads.push({ name: download.suggestedFilename(), width: 1080, height: 1080, bytes: png.length });
  }
  await page.locator('#meme-template').selectOption('3');
  await page.locator('#meme-top').fill('<frog> & friends');
  await page.locator('#meme-bottom').fill('RIBBIT '.repeat(6));
  assert.ok((await page.locator('#meme-preview').getAttribute('aria-label')).includes('<frog> & friends'));
  const [custom] = await Promise.all([page.waitForEvent('download'), page.locator('#download-meme').click()]);
  await custom.saveAs(path.join(evidence, custom.suggestedFilename()));
  const customPng = await readFile(path.join(evidence, custom.suggestedFilename()));
  assert.equal(customPng.readUInt32BE(16), 1080);
  report.downloads.push({ name: custom.suggestedFilename(), width: 1080, height: 1080, bytes: customPng.length });
  pass('All eight gallery PNGs and custom text/template PNG export at 1080×1080');

  await page.emulateMedia({ reducedMotion: 'reduce' });
  assert.equal(await page.locator('#motion-toggle').textContent(), 'Reduced motion on');
  assert.equal(await page.locator('.frog-orbit').evaluate(el => getComputedStyle(el).animationName), 'none');
  assert.equal(await page.locator('.marquee-track').evaluate(el => getComputedStyle(el).animationName), 'none');
  await page.locator('#ribbit').click();
  assert.equal(await page.locator('.swarm-frog').count(), 0);
  pass('Reduced-motion mode disables autoplay, reveals and toy bursts without disabling controls');

  await page.goto(url); await page.locator('#data-status').filter({hasText:'Launching…'}).waitFor();
  await page.keyboard.press('Tab');
  assert.equal(await page.evaluate(() => document.activeElement.textContent), 'Skip to content');
  await page.keyboard.press('Enter');
  await page.locator('.hero [data-buy]').focus();
  const focus = await page.locator('.hero [data-buy]').evaluate(el => ({ style: getComputedStyle(el).outlineStyle, width: getComputedStyle(el).outlineWidth }));
  assert.equal(focus.style, 'solid'); assert.equal(focus.width, '3px');
  await page.screenshot({ path: path.join(evidence, 'focus.png') });
  pass('Skip link is first keyboard stop and focused primary action has a 3px outline');

  await page.addScriptTag({ content: axeSource });
  for (const width of [375, 1440]) {
    await page.setViewportSize({ width, height: 1000 });
    const scan = await page.evaluate(async () => await window.axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] } }));
    report.accessibility.push({ page: 'home', width, violations: scan.violations.map(v => ({ id: v.id, impact: v.impact, nodes: v.nodes.map(n => ({ target: n.target, summary: n.failureSummary })) })), incomplete: scan.incomplete.map(v => ({id:v.id,nodes:v.nodes.length})) });
    assert.equal(scan.violations.length, 0, JSON.stringify(report.accessibility.at(-1)));
  }
  pass('Automated axe WCAG A/AA scan reports zero violations at 375 and 1440px');
  for (const width of [375, 768, 1440]) {
    await page.setViewportSize({width, height:1000});
    await page.evaluate(() => {document.documentElement.style.fontSize='200%';});
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), width, `Enlarged text overflow at ${width}`);
    await page.evaluate(() => {document.documentElement.style.fontSize='';});
  }
  pass('200% root-text enlargement has no horizontal overflow at 375, 768 and 1440px');

  const links = await page.locator('a[href^="#"]').evaluateAll(links => links.map(link => link.getAttribute('href')));
  for (const href of links) if (href !== '#') assert.equal(await page.locator(href).count(), 1, `Missing anchor ${href}`);
  const brokenImages = await page.locator('img').evaluateAll(images => images.filter(img => img.complete && img.naturalWidth === 0).map(img => img.src));
  assert.deepEqual(brokenImages, []);
  pass('Every in-page link resolves; no broken HTML images or failed static resources');

  await page.evaluate(() => { document.querySelectorAll('.is-pending').forEach(el => el.classList.remove('is-pending')); document.activeElement.blur(); scrollTo(0,0); });
  await page.screenshot({ path: path.join(root, 'artifacts/desktop.jpg'), fullPage: true, type: 'jpeg', quality: 68 });
  await page.setViewportSize({ width: 390, height: 844 });
  await page.screenshot({ path: path.join(root, 'artifacts/mobile.jpg'), type: 'jpeg', quality: 80 });

  for (const width of [375, 1440]) {
    await page.setViewportSize({ width, height: 900 });
    await page.goto(url + '404.html');
    assert.ok(await page.getByRole('heading', { name: 'This pond is empty.' }).isVisible());
    assert.equal(await page.evaluate(() => document.documentElement.scrollWidth), width);
    await page.addScriptTag({ content: axeSource });
    const scan = await page.evaluate(async () => await window.axe.run(document, { runOnly: { type: 'tag', values: ['wcag2a', 'wcag2aa', 'wcag21aa', 'wcag22aa'] } }));
    report.accessibility.push({ page: '404', width, violations: scan.violations.map(v=>({id:v.id,impact:v.impact})), incomplete: scan.incomplete.map(v=>({id:v.id,nodes:v.nodes.length})) });
    assert.equal(scan.violations.length, 0);
    await page.locator('main a').click(); assert.equal(page.url(), url);
    await page.waitForLoadState('networkidle');
    await page.evaluate(() => document.fonts.ready);
  }
  pass('Styled 404 opens at 375 and 1440px with no overflow, no axe violations and working return link');
  assert.deepEqual(report.consoleErrors, []);
  assert.deepEqual(report.resourceFailures, []);
  pass('No unexpected console errors or failed resources in the browser run');
} catch (error) {
  report.failure = error.stack || String(error);
  console.error(report.failure); process.exitCode = 1;
} finally {
  await writeFile(path.join(root, 'artifacts/browser-results.json'), JSON.stringify(report, null, 2) + '\n');
  if (browser) await browser.close(); server.kill('SIGTERM');
}
