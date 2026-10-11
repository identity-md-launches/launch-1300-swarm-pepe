// @ts-check
export const memes = [
  { title: 'The group chat', top: 'ME: JUST ONE MEME', bottom: 'ALSO ME: THE ENTIRE SWARM', theme: 0 },
  { title: 'Frog frequency', top: 'NO THOUGHTS', bottom: 'ONLY RIBBITS', theme: 1 },
  { title: 'Pond resident', top: 'OFFICIALLY UNAVAILABLE', bottom: 'I HAVE POND DUTIES', theme: 2 },
  { title: 'Collective frog brain', top: 'ONE BRAIN CELL', bottom: 'SHARED BY THE SWARM', theme: 3 },
  { title: 'The daily briefing', top: 'THE MEETING COULD HAVE', bottom: 'BEEN A RIBBIT', theme: 4 },
  { title: 'Swarm delivery', top: 'YOU ORDERED ONE FROG', bottom: 'WE SENT THE WHOLE POND', theme: 5 },
  { title: 'Pond mode', top: 'OUT OF OFFICE', bottom: 'IN MY POND ERA', theme: 6 },
  { title: 'Group project', top: 'INDIVIDUALLY: FROG', bottom: 'TOGETHER: ALSO FROG', theme: 7 }
];
export function escapeXml(value) {
  return String(value).replace(/[<>&"']/g, char => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;', "'": '&apos;' })[char] || char);
}
/** Original vector compositions. The supplied logo is the only raster input. */
export function memeSvg(theme, top, bottom, logo) {
  const id = `m${theme}`;
  const colors = ['#21164f', '#13133e', '#a8ff00', '#6a3ce3', '#f3f2df', '#22203a', '#302454', '#a8ff00'];
  const bg = colors[theme % colors.length];
  const light = [2, 4, 7].includes(theme);
  const ink = light ? '#101020' : '#f3f2df';
  const image = (x, y, size, rotation = 0) => `<g transform="rotate(${rotation} ${x + size / 2} ${y + size / 2})"><circle cx="${x + size / 2}" cy="${y + size / 2}" r="${size / 2 + 4}" fill="${ink}"/><image href="${escapeXml(logo)}" x="${x}" y="${y}" width="${size}" height="${size}" clip-path="url(#${id}-clip)" preserveAspectRatio="xMidYMid slice"/></g>`;
  // objectBoundingBox clipping lets every copy use the same circular crop.
  let composition = '';
  if (theme === 0) composition = `<path d="M70 140h345v255H175l-65 48v-48H70z" fill="#7c52ff" stroke="#101020" stroke-width="7" transform="rotate(-7 270 270)"/>${image(45, 237, 180, -16)}${image(189, 184, 210, 8)}${image(326, 271, 165, 16)}<path d="M72 175h130m-122 26h95" stroke="#bda5ff" stroke-width="10" stroke-linecap="round"/>`;
  if (theme === 1) composition = `<g stroke="#a8ff00" fill="none" stroke-width="3"><circle cx="270" cy="270" r="196"/><circle cx="270" cy="270" r="152"/><path d="M25 270h490M270 95v350M84 84l372 372M84 456L456 84"/></g>${image(157, 157, 226)}<path d="M440 135l12-25 12 25 25 12-25 12-12 25-12-25-25-12z" fill="#a8ff00"/>`;
  if (theme === 2) composition = `<g transform="rotate(-10 270 270)"><rect x="78" y="111" width="384" height="324" rx="18" fill="#f3f2df" stroke="#101020" stroke-width="8"/><rect x="98" y="131" width="344" height="54" fill="#101020"/><text x="270" y="167" text-anchor="middle" font-family="monospace" font-size="22" fill="#f3f2df">POND RESIDENT ID</text>${image(108, 214, 148)}<path d="M290 240h120m-120 40h90m-90 40h110" stroke="#101020" stroke-width="9"/><text x="290" y="378" font-family="monospace" font-size="18" fill="#101020">100% FROG</text></g>`;
  if (theme === 3) composition = `<g stroke="#a8ff00" stroke-width="6"><path d="M270 160L125 355H415z" fill="none"/><path d="M125 355L270 275l145 80M270 160v115"/></g>${image(187, 102, 166)}${image(49, 292, 152, -16)}${image(338, 292, 152, 16)}<circle cx="270" cy="295" r="43" fill="#a8ff00" stroke="#101020" stroke-width="6"/><text x="270" y="311" text-anchor="middle" font-size="46" font-family="sans-serif" fill="#101020">✳</text>`;
  if (theme === 4) composition = `<rect x="75" y="122" width="390" height="297" rx="10" fill="#21164f" stroke="#101020" stroke-width="6"/><path d="M75 164h390" stroke="#bda5ff" stroke-width="3"/><g fill="#a8ff00"><circle cx="97" cy="144" r="7"/><circle cx="121" cy="144" r="7"/><circle cx="145" cy="144" r="7"/></g>${image(146, 185, 235, -7)}<rect x="315" y="351" width="153" height="42" rx="5" fill="#a8ff00" stroke="#101020" stroke-width="4"/><text x="392" y="379" text-anchor="middle" font-family="monospace" font-size="20" fill="#101020">ON MUTE</text>`;
  if (theme === 5) composition = `<path d="M78 251l192-95 192 95v162H78z" fill="#bda5ff" stroke="#101020" stroke-width="7"/>${image(66, 167, 160, -17)}${image(196, 123, 174)}${image(332, 183, 144, 12)}<path d="M78 286l192 82 192-82v143H78z" fill="#a8ff00" stroke="#101020" stroke-width="7"/><text x="270" y="408" text-anchor="middle" font-family="monospace" font-size="24" fill="#101020">FROGILE ↑</text>`;
  if (theme === 6) composition = `<ellipse cx="270" cy="376" rx="206" ry="61" fill="#7c52ff" stroke="#bda5ff" stroke-width="4"/><ellipse cx="270" cy="376" rx="143" ry="40" fill="#a8ff00"/>${image(163, 158, 214, -9)}<path d="M375 300V137m-93 40q94-130 190-3z" fill="#a8ff00" stroke="#101020" stroke-width="6"/><path d="M56 184l12-29 12 29 29 12-29 12-12 29-12-29-29-12z" fill="#f3f2df"/>`;
  if (theme === 7) composition = `<g stroke="#101020" stroke-width="3" fill="none"><path d="M0 135h540M0 270h540M0 405h540M135 100v340M270 100v340M405 100v340"/></g>${image(42, 135, 156, -12)}${image(322, 144, 150, 14)}${image(163, 237, 222)}<rect x="182" y="126" width="178" height="44" fill="#101020" transform="rotate(6 270 148)"/><text x="270" y="155" text-anchor="middle" fill="#f3f2df" font-family="monospace" font-size="22" transform="rotate(6 270 148)">CTRL + RIBBIT</text>`;
  const label = (text, y) => `<text x="270" y="${y}" text-anchor="middle" dominant-baseline="middle" fill="${ink}" font-family="Arial, sans-serif" font-weight="900" font-size="${text.length > 27 ? 21 : 27}" textLength="${text.length > 25 ? 465 : Math.min(460, text.length * 16)}" lengthAdjust="spacingAndGlyphs">${escapeXml(text.toUpperCase())}</text>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="540" height="540" viewBox="0 0 540 540" aria-hidden="true"><defs><clipPath id="${id}-clip" clipPathUnits="objectBoundingBox"><circle cx=".5" cy=".5" r=".49"/></clipPath><pattern id="${id}-dots" width="16" height="16" patternUnits="userSpaceOnUse"><circle cx="3" cy="3" r="1.2" fill="${ink}" opacity=".16"/></pattern></defs><rect width="540" height="540" fill="${bg}"/><rect width="540" height="540" fill="url(#${id}-dots)"/>${composition}${label(top, 62)}${label(bottom, 476)}<text x="270" y="521" text-anchor="middle" fill="${ink}" opacity=".8" font-family="monospace" font-size="12">SWARM PEPE / $SPEPE</text></svg>`;
}
