// @ts-check
/** Only navigate to web URLs; feed content never becomes HTML. */
export function safeUrl(value, origin = location.origin) {
  if (typeof value !== 'string' || !value.trim()) return null;
  try {
    const url = new URL(value, origin);
    if (url.username || url.password) return null;
    return url.protocol === 'https:' || (url.protocol === 'http:' && url.origin === origin) ? url.href : null;
  } catch { return null; }
}
export function marketNumber(value) {
  if (typeof value !== 'number' && typeof value !== 'string') return null;
  if (typeof value === 'string' && !value.trim()) return null;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : null;
}
export function validToken(value) {
  return typeof value === 'string' && /^0x[a-fA-F0-9]{40}$/.test(value) && !/^0x0{40}$/i.test(value) ? value : null;
}
export function normalizeCoin(value, origin) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Invalid launch feed');
  const fields = ['name', 'symbol', 'token', 'status', 'market', 'coinUrl', 'chartUrl', 'logo'];
  if (!fields.some(key => Object.hasOwn(value, key))) throw new Error('Missing launch fields');
  const market = value.market && typeof value.market === 'object' ? value.market : {};
  return {
    token: validToken(value.token),
    coinUrl: safeUrl(value.coinUrl, origin),
    chartUrl: safeUrl(value.chartUrl, origin),
    logo: safeUrl(value.logo, origin),
    chainName: typeof value.chainName === 'string' && value.chainName.length < 60 ? value.chainName : 'Robinhood Chain',
    status: typeof value.status === 'string' ? value.status.slice(0, 60) : null,
    market: { priceUsd: marketNumber(market.priceUsd), marketCap: marketNumber(market.marketCap), volume24h: marketNumber(market.volume24h) }
  };
}
export function formatMarket(value, isPrice = false) {
  if (value === null) return '—';
  if (value === 0) return '$0';
  if ((isPrice && value < 0.001) || value >= 1e15) return '$' + value.toExponential(2);
  return new Intl.NumberFormat('en-US', {
    style: 'currency', currency: 'USD',
    ...(isPrice && value < 1000 ? { maximumSignificantDigits: 3 } : { notation: 'compact', maximumFractionDigits: 2 })
  }).format(value);
}
