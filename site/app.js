// @ts-check
import { normalizeCoin, formatMarket } from './data.js';
import { memes, memeSvg } from './memes.js';
/** @template {HTMLElement} T @param {string} selector @returns {T} */
function find(selector) { return /** @type {T} */ (document.querySelector(selector)); }
const defaultLogo = new URL('./assets/mascot.webp', import.meta.url).href;
const canonicalUrl = 'https://swarmpepe.si-md.xyz/';
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
let userPaused = false;
let activeLogo = defaultLogo;
let token = null;
let lastSuccess = null;
let fetching = false;
let toastTimer;
const canAnimate = () => !reducedMotion.matches && !userPaused;
function notify(message) {
  clearTimeout(toastTimer);
  find('#toast').textContent = message;
  toastTimer = setTimeout(() => { find('#toast').textContent = ''; }, 7000);
}

// A disclosure navigation, not a modal: Tab stays in normal document order.
const menu = find('#main-nav');
const menuToggle = find('#main-nav').previousElementSibling;
function closeMenu(restoreFocus = false) {
  menu.classList.remove('is-open');
  menuToggle.setAttribute('aria-expanded', 'false');
  if (restoreFocus) /** @type {HTMLElement} */ (menuToggle).focus();
}
menuToggle.addEventListener('click', () => {
  const open = menu.classList.toggle('is-open');
  menuToggle.setAttribute('aria-expanded', String(open));
});
menu.querySelectorAll('a').forEach(link => link.addEventListener('click', () => closeMenu()));
document.addEventListener('keydown', event => { if (event.key === 'Escape' && menu.classList.contains('is-open')) closeMenu(true); });
document.addEventListener('click', event => { if (!/** @type {Element} */(event.target).closest('.site-header')) closeMenu(); });
matchMedia('(min-width: 851px)').addEventListener('change', () => closeMenu());

const motionButton = find('#motion-toggle');
function updateMotion() {
  const paused = userPaused || reducedMotion.matches;
  document.documentElement.classList.toggle('motion-paused', paused);
  motionButton.setAttribute('aria-pressed', String(paused));
  motionButton.textContent = reducedMotion.matches ? 'Reduced motion on' : paused ? 'Play motion ▷' : 'Pause motion Ⅱ';
  motionButton.title = reducedMotion.matches ? 'Your device’s reduced-motion preference is respected.' : '';
  const compact = find('.motion-control');
  compact.textContent = paused ? '▷' : 'Ⅱ';
  compact.setAttribute('aria-label', reducedMotion.matches ? 'Reduced motion on' : paused ? 'Play motion' : 'Pause motion');
  compact.setAttribute('aria-pressed', String(paused));
  compact.title = compact.getAttribute('aria-label');
}
document.querySelectorAll('[data-motion]').forEach(button => button.addEventListener('click', () => {
  if (reducedMotion.matches) { notify('Reduced motion is enabled in your device settings.'); return; }
  userPaused = !userPaused; updateMotion();
}));
reducedMotion.addEventListener('change', updateMotion);
updateMotion();

function revealContent() {
  if (!('IntersectionObserver' in window)) return;
  const observer = new IntersectionObserver(entries => entries.forEach(entry => {
    if (entry.isIntersecting) { entry.target.classList.remove('is-pending'); entry.target.classList.add('is-visible'); observer.unobserve(entry.target); }
  }), { threshold: 0.08 });
  document.querySelectorAll('.reveal').forEach((element, index) => {
    if (element.getBoundingClientRect().top > innerHeight && canAnimate()) {
      element.classList.add('is-pending');
      /** @type {HTMLElement} */(element).style.setProperty('--reveal-delay', `${index % 3 * 100}ms`);
    }
    observer.observe(element);
  });
}

// Data remains absent until supplied. A failed refresh preserves and labels last-known values.
const previousValues = new Map();
const animationFrames = new Map();
function updateNumber(selector, next, isPrice = false) {
  const element = find(selector);
  const previous = previousValues.get(selector);
  cancelAnimationFrame(animationFrames.get(selector));
  previousValues.set(selector, next);
  element.setAttribute('aria-label', next === null ? 'Not available' : `${next} US dollars`);
  if (!canAnimate() || next === null || previous == null || previous === next) { element.textContent = formatMarket(next, isPrice); return; }
  const start = performance.now();
  function frame(now) {
    const progress = Math.min(1, (now - start) / 600);
    element.textContent = formatMarket(previous + (next - previous) * (1 - (1 - progress) ** 3), isPrice);
    if (progress < 1) animationFrames.set(selector, requestAnimationFrame(frame));
  }
  animationFrames.set(selector, requestAnimationFrame(frame));
}
function updateDestination(selector, url, fallback) {
  document.querySelectorAll(selector).forEach(element => {
    const link = /** @type {HTMLAnchorElement} */ (element);
    link.href = url || fallback;
    if (url) { link.target = '_blank'; link.rel = 'noopener noreferrer'; }
    else { link.removeAttribute('target'); link.removeAttribute('rel'); }
  });
}
async function updateLogo(url) {
  const wanted = url || defaultLogo;
  if (activeLogo === wanted) return;
  const image = new Image();
  image.src = wanted;
  try {
    await image.decode();
    activeLogo = wanted;
  } catch { activeLogo = defaultLogo; }
  document.querySelectorAll('img[data-logo]').forEach(img => { /** @type {HTMLImageElement} */(img).src = activeLogo; });
  renderGallery(); renderPreview();
}
async function refreshData() {
  if (fetching) return;
  fetching = true;
  const refreshButton = /** @type {HTMLButtonElement} */(find('#refresh-data'));
  refreshButton.disabled = true;
  refreshButton.textContent = 'Refreshing…';
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const response = await fetch('/simd-coin.json', { cache: 'no-store', signal: controller.signal });
    if (!response.ok) throw new Error('Launch feed unavailable');
    const data = normalizeCoin(await response.json(), location.origin);
    token = data.token;
    find('#contract-address').textContent = token || 'launching…';
    /** @type {HTMLButtonElement} */(find('#copy-contract')).disabled = !token;
    find('#contract-note').textContent = token ? 'Address supplied by the launch feed. Check it matches the coin page before swapping.' : 'The verified address and trading links will appear when the launch feed publishes them.';
    updateDestination('[data-buy]', data.coinUrl, '#buy');
    updateDestination('[data-chart]', data.chartUrl, '#stats');
    // Avoid a self-link when the guide's coin-page action is still waiting.
    if (!data.coinUrl) /** @type {HTMLAnchorElement} */(find('#step-buy')).href = '#contract';
    document.querySelectorAll('[data-chain]').forEach(element => { element.textContent = data.chainName; });
    find('#hero-status').textContent = !token ? 'Launching… the pond is warming up.' : data.coinUrl ? 'Launch address available. Check the coin page.' : 'Token deployed. Trading link pending.';
    if (data.status && ['paused', 'ended', 'failed'].includes(data.status.toLowerCase())) {
      find('#hero-status').textContent = `Launch status: ${data.status.toLowerCase()}. Check the coin page for details.`;
    }
    updateNumber('#stat-price', data.market.priceUsd, true);
    updateNumber('#stat-cap', data.market.marketCap);
    updateNumber('#stat-volume', data.market.volume24h);
    lastSuccess = new Date();
    const anyMarket = Object.values(data.market).some(value => value !== null);
    find('#data-status').textContent = anyMarket ? 'Feed updated' : token ? 'Waiting for market data' : 'Launching…';
    find('#data-footnote').textContent = `${anyMarket ? 'Updated' : 'Feed checked'} ${lastSuccess.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', second: '2-digit' })}. Refreshes every 30 seconds. ${anyMarket ? 'Market figures can change.' : 'No made-up numbers. Market data is not available yet.'}`;
    void updateLogo(data.logo);
  } catch {
    find('#data-status').textContent = lastSuccess ? 'Feed offline · last-known data' : 'Live feed unavailable';
    find('#data-footnote').textContent = lastSuccess ? `Showing the last successful update from ${lastSuccess.toLocaleTimeString('en-GB')}. Use Refresh to retry; automatic updates continue every 30 seconds.` : 'Launch data could not be loaded. Use Refresh to retry; automatic updates continue every 30 seconds.';
  } finally {
    clearTimeout(timeout); fetching = false; refreshButton.disabled = false; refreshButton.textContent = 'Refresh ↻';
  }
}
find('#refresh-data').addEventListener('click', () => void refreshData());
setInterval(() => { if (!document.hidden) void refreshData(); }, 30000);
document.addEventListener('visibilitychange', () => { if (!document.hidden) void refreshData(); });

async function copyText(text, message) {
  try { await navigator.clipboard.writeText(text); notify(message); }
  catch {
    find('#toast').textContent = `Copy isn’t available here. Select and copy: ${text}`;
  }
}
find('#copy-contract').addEventListener('click', () => { if (token) void copyText(token, 'SPEPE contract address copied.'); });
find('#copy-link').addEventListener('click', () => void copyText(canonicalUrl, 'Pond coordinates copied. Send them to a friend.'));

const steps = [
  { title: 'A home for your frog.', copy: 'Use an EVM-compatible wallet that supports Robinhood Chain. Follow your wallet’s official setup guide and keep your recovery phrase private. This site never asks you to connect.' },
  { title: 'Fuel up for the pond.', copy: 'Get ETH on Robinhood Chain for network fees, plus IMD for the pool’s paired currency. Use official network and wallet guidance to move funds. ETH on another network will not pay this chain’s gas.' },
  { title: 'Meet the official coin page.', copy: 'Open the launch coin page when its link is available. Check the SPEPE address, network, route and full quote. The pool uses IMD. Read the launch fee and first-hour buy cap below before approving a swap.' }
];
let stepIndex = 0;
function setStep(index) {
  stepIndex = index;
  document.querySelectorAll('[data-step]').forEach(button => {
    const active = Number(/** @type {HTMLElement} */(button).dataset.step) === index;
    button.classList.toggle('is-active', active); button.setAttribute('aria-pressed', String(active));
  });
  find('#step-number').textContent = `Step 0${index + 1} / 03`;
  find('#step-title').textContent = steps[index].title;
  find('#step-copy').textContent = steps[index].copy;
  find('#next-step').hidden = index === 2;
  find('#step-buy').hidden = index !== 2;
}
document.querySelectorAll('[data-step]').forEach(button => button.addEventListener('click', () => setStep(Number(/** @type {HTMLElement} */(button).dataset.step))));
find('#next-step').addEventListener('click', () => {
  setStep(Math.min(2, stepIndex + 1));
  if (stepIndex === 2) find('#step-buy').focus();
});

// Local toy, explicitly unrelated to trading, price or visitor counts.
let ribbits = 0;
find('#ribbit').addEventListener('click', () => {
  ribbits += 1;
  const vibe = Math.min(100, ribbits * 5);
  find('#vibe-count').textContent = `${vibe}%`;
  find('#vibe-fill').style.width = `${vibe}%`;
  find('.vibe-track').setAttribute('aria-valuenow', String(vibe));
  find('.vibe-track').setAttribute('aria-valuetext', `${vibe} percent, ${ribbits} local ribbits. Just for fun.`);
  if (ribbits === 20) notify('Maximum ribbit. The collective frog brain is online.');
  else if (ribbits % 5 === 0) notify(`${ribbits} ribbits from you. Excellent pond work.`);
  if (canAnimate()) {
    const area = find('#swarm-burst');
    for (let i = 0; i < 4; i++) {
      const frog = document.createElement('img'); frog.src = activeLogo; frog.alt = ''; frog.className = 'swarm-frog';
      frog.style.left = `${15 + Math.random() * 70}%`; frog.style.bottom = '70px';
      frog.style.setProperty('--hop-x', `${Math.random() * 120 - 60}px`); frog.style.setProperty('--hop-r', `${Math.random() * 70 - 35}deg`);
      area.append(frog); setTimeout(() => frog.remove(), 1100);
    }
  }
});
function confetti(event) {
  if (!canAnimate()) return;
  const bounds = /** @type {Element} */(event.currentTarget).getBoundingClientRect();
  const x = bounds.x + bounds.width / 2, y = bounds.y + bounds.height / 2;
  for (let i = 0; i < 16; i++) {
    const bit = document.createElement('span'); bit.className = 'confetti'; bit.setAttribute('aria-hidden', 'true');
    bit.style.left = `${x}px`; bit.style.top = `${y}px`; bit.style.background = ['#a8ff00', '#bda5ff', '#f3f2df'][i % 3];
    bit.style.setProperty('--confetti-x', `${(Math.random() - .5) * 260}px`); bit.style.setProperty('--confetti-y', `${Math.random() * 180 - 120}px`); bit.style.setProperty('--confetti-r', `${Math.random() * 400}deg`);
    document.body.append(bit); setTimeout(() => bit.remove(), 900);
  }
}
document.querySelectorAll('[data-buy]').forEach(link => link.addEventListener('click', event => {
  confetti(event);
  if (!/** @type {HTMLAnchorElement} */(link).hasAttribute('target')) notify('Trading link pending. Explore the buying guide while the pond warms up.');
}));
document.querySelectorAll('.magnetic').forEach(element => {
  const button = /** @type {HTMLElement} */(element);
  button.addEventListener('pointermove', event => {
    if (!canAnimate() || event.pointerType !== 'mouse') return;
    const box = button.getBoundingClientRect();
    button.style.translate = `${(event.clientX - box.x - box.width / 2) * .08}px ${(event.clientY - box.y - box.height / 2) * .1}px`;
  });
  button.addEventListener('pointerleave', () => { button.style.translate = ''; });
});

const sticker = find('#drag-sticker');
let drag = null;
let offset = { x: 0, y: 0 };
function moveSticker(x, y) {
  const area = sticker.parentElement.getBoundingClientRect();
  offset = { x: Math.max(-area.width * .6, Math.min(5, x)), y: Math.max(-area.height * .55, Math.min(5, y)) };
  sticker.style.translate = `${offset.x}px ${offset.y}px`;
}
sticker.addEventListener('pointerdown', event => {
  drag = { x: event.clientX - offset.x, y: event.clientY - offset.y };
  sticker.setPointerCapture(event.pointerId);
});
sticker.addEventListener('pointermove', event => { if (drag) moveSticker(event.clientX - drag.x, event.clientY - drag.y); });
sticker.addEventListener('pointerup', () => { drag = null; });
sticker.addEventListener('pointercancel', () => { drag = null; });
sticker.addEventListener('lostpointercapture', () => { drag = null; });
sticker.addEventListener('keydown', event => {
  const direction = { ArrowLeft: [-14, 0], ArrowRight: [14, 0], ArrowUp: [0, -14], ArrowDown: [0, 14] }[event.key];
  if (direction) { event.preventDefault(); moveSticker(offset.x + direction[0], offset.y + direction[1]); }
  if (event.key === 'Home') { event.preventDefault(); moveSticker(0, 0); }
});
window.addEventListener('resize', () => moveSticker(offset.x, offset.y));

function renderGallery() {
  const wall = find('#meme-wall');
  wall.replaceChildren();
  memes.forEach((meme, index) => {
    const card = document.createElement('article'); card.className = 'meme-card reveal';
    const art = document.createElement('div'); art.className = 'meme-art'; art.setAttribute('role', 'img'); art.setAttribute('aria-label', `${meme.top}. ${meme.bottom}.`);
    art.innerHTML = memeSvg(meme.theme, meme.top, meme.bottom, activeLogo);
    const caption = document.createElement('div'); caption.className = 'meme-caption';
    const title = document.createElement('h3'); title.textContent = meme.title;
    const button = document.createElement('button'); button.type = 'button'; button.className = 'download-small'; button.textContent = '↓'; button.setAttribute('aria-label', `Download ${meme.title} as PNG`);
    button.addEventListener('click', () => void downloadMeme(meme.theme, meme.top, meme.bottom, `swarm-pepe-${index + 1}.png`, button));
    caption.append(title, button); card.append(art, caption); wall.append(card);
  });
}
function renderPreview() {
  const theme = Number(/** @type {HTMLSelectElement} */(find('#meme-template')).value);
  const top = /** @type {HTMLInputElement} */(find('#meme-top')).value;
  const bottom = /** @type {HTMLInputElement} */(find('#meme-bottom')).value;
  const preview = find('#meme-preview');
  preview.innerHTML = memeSvg(theme, top, bottom, activeLogo);
  preview.setAttribute('aria-label', `Custom meme: ${top}. ${bottom}.`);
}
['#meme-template', '#meme-top', '#meme-bottom'].forEach(selector => find(selector).addEventListener('input', renderPreview));
const dataLogoCache = new Map();
async function embeddedLogo() {
  if (dataLogoCache.has(activeLogo)) return { data: dataLogoCache.get(activeLogo), fallback: false };
  let response;
  let fallback = false;
  try {
    response = await fetch(activeLogo, { signal: AbortSignal.timeout(8000) });
    if (!response.ok) throw new Error('Image unavailable');
    if (!(response.headers.get('content-type') || '').startsWith('image/')) throw new Error('Not an image');
  } catch {
    response = await fetch(defaultLogo); fallback = true;
    if (!response.ok) throw new Error('Default logo unavailable');
  }
  const blob = await response.blob();
  const data = await new Promise((resolve, reject) => {
    const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(blob);
  });
  if (!fallback) dataLogoCache.set(activeLogo, data);
  return { data, fallback };
}
/** Canvas is used only offscreen to encode PNG downloads, never to render the page. */
async function downloadMeme(theme, top, bottom, filename, button) {
  const oldText = button.textContent;
  button.disabled = true; button.textContent = '…';
  let svgUrl;
  let pngUrl;
  try {
    const logo = await embeddedLogo();
    const svg = memeSvg(theme, top, bottom, logo.data);
    svgUrl = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml;charset=utf-8' }));
    const img = new Image(); img.src = svgUrl; await img.decode();
    const canvas = document.createElement('canvas'); canvas.width = 1080; canvas.height = 1080;
    const context = canvas.getContext('2d');
    if (!context) throw new Error('PNG export is unavailable');
    context.drawImage(img, 0, 0, 1080, 1080);
    const png = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    if (!(png instanceof Blob)) throw new Error('PNG could not be encoded');
    pngUrl = URL.createObjectURL(png);
    const anchor = document.createElement('a'); anchor.href = pngUrl; anchor.download = filename; document.body.append(anchor); anchor.click(); anchor.remove();
    const message = logo.fallback ? 'PNG downloaded using the default frog: the selected logo does not permit image exports.' : 'PNG ready. Check your downloads. Go make the group chat weirder.';
    find('#download-status').textContent = message; notify(message);
  } catch {
    const message = 'PNG download failed. Check your connection and try the download again.';
    find('#download-status').textContent = message; find('#toast').textContent = message;
  } finally {
    button.disabled = false; button.textContent = oldText;
    if (svgUrl) URL.revokeObjectURL(svgUrl);
    if (pngUrl) setTimeout(() => URL.revokeObjectURL(pngUrl), 10000);
  }
}
find('#download-meme').addEventListener('click', () => void downloadMeme(
  Number(/** @type {HTMLSelectElement} */(find('#meme-template')).value),
  /** @type {HTMLInputElement} */(find('#meme-top')).value,
  /** @type {HTMLInputElement} */(find('#meme-bottom')).value,
  'my-swarm-pepe-meme.png', find('#download-meme')
));
renderGallery(); renderPreview(); revealContent(); void refreshData();
