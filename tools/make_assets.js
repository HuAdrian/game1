/*
 * Generates the artwork and sound effects in godot/assets, in one art
 * direction: ink and watercolour (deep ink blue, warm parchment, one red).
 * Every file it writes can be replaced by finished art of the same name;
 * the game loads assets by file name and never needs this script to run.
 * It also writes the mini game's loading-screen logo to the template path
 * the Godot Mini Game plugin documents for customising it.
 *
 *   node tools/make_assets.js        (needs Playwright's Chromium for the PNGs)
 */
const fs = require('fs'), path = require('path');
const OUT = path.join(__dirname, '..', 'godot', 'assets');

// The drawings come from the HTML version's art module.
global.window = { matchMedia: () => ({ matches: false }) };
global.localStorage = { getItem: () => null, setItem() {} };
window.CaseFiles = {};
require('../legacy-html/js/feel.js');
const art = window.CaseFiles.art;

const PLACES = ['unit9', 'street', 'office', 'lab', 'stagedoor', 'hall'];
const CAST = {
  sam: ['neutral', 'pleased', 'annoyed'], victor: ['neutral', 'smug', 'nervous', 'sweating', 'cracked'],
  whitlock: ['neutral'], desk: ['neutral'], nair: ['neutral', 'annoyed'],
  dominic: ['neutral', 'nervous', 'pleased', 'smug'], beatrice: ['neutral', 'pleased', 'nervous', 'smug']
};

/* ───── art direction: ink and watercolour ─────
 * Deep ink blue, warm parchment and one red. Every drawing is rendered as two
 * layers: a wash (fills only, displaced and bled, with pigment granulation and
 * darker pooled edges) under an ink layer (lines only, slightly hand-wobbled). */
const PALETTE = {
  '#1c2530': '#1e2c4a', '#c2271c': '#b3261e', '#7c150e': '#7a1712',
  '#cdd7de': '#bccbd8', '#aebbc5': '#8ea4bd', '#e9dcc0': '#ead9b4', '#d2bd94': '#cfae79', '#fcf9f0': '#f6ecd3',
  '#fff': '#fbf3df', '#fff6c8': '#f2dfa6', '#f1dc8c': '#efd28e', '#f8f3dc': '#f3e7c9', '#f6f1d8': '#f1e4c4',
  '#ebe2cf': '#eadcbd', '#e7dcc4': '#e6d6b5', '#dcd3c2': '#dacaa9', '#dfe2dc': '#e0dac6', '#e3e9ea': '#dfdfd2',
  '#dbe6ea': '#d8ddd6', '#cfd6d8': '#cdd1c8', '#c9cdc9': '#c6c7bb', '#b9b3a6': '#b3a891', '#5b6876': '#4b5d7a', '#3a4654': '#2e3f5e',
};
const INK = '#1e2c4a', PARCH = '#f1e4c6', PARCH2 = '#e6d3ab', RED = '#b3261e', WASH = '#bccbd8';

function repaint(svg) {
  return svg.replace(/#[0-9a-fA-F]{6}\b|#fff\b/g, c => PALETTE[c.toLowerCase()] || c);
}
const FILTERS = (seed) => `
  <filter id="wash" x="-6%" y="-6%" width="112%" height="112%" color-interpolation-filters="sRGB">
    <feTurbulence type="fractalNoise" baseFrequency="0.022" numOctaves="3" seed="${seed}" result="t"/>
    <feDisplacementMap in="SourceGraphic" in2="t" scale="13" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feGaussianBlur in="d" stdDeviation="1.5" result="b"/>
    <feMorphology in="b" operator="erode" radius="2.6" result="er"/>
    <feComposite in="b" in2="er" operator="out" result="edge"/>
    <feColorMatrix in="edge" type="matrix" values="0.55 0 0 0 0  0 0.55 0 0 0  0 0 0.62 0 0  0 0 0 0.8 0" result="pool"/>
    <feTurbulence type="fractalNoise" baseFrequency="0.75" numOctaves="2" seed="${seed + 5}" result="g"/>
    <feColorMatrix in="g" type="matrix" values="0 0 0 0 1  0 0 0 0 1  0 0 0 0 1  0 0 0 -0.85 1.2" result="gran"/>
    <feComposite in="b" in2="gran" operator="in" result="granulated"/>
    <feMerge><feMergeNode in="granulated"/><feMergeNode in="pool"/></feMerge>
  </filter>
  <filter id="ink" x="-4%" y="-4%" width="108%" height="108%">
    <feTurbulence type="fractalNoise" baseFrequency="0.06" numOctaves="2" seed="${seed + 11}" result="t"/>
    <feDisplacementMap in="SourceGraphic" in2="t" scale="1.8" xChannelSelector="R" yChannelSelector="G" result="d"/>
    <feGaussianBlur in="d" stdDeviation="0.25"/>
  </filter>
  <filter id="paper" x="0" y="0" width="100%" height="100%">
    <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="${seed + 3}" result="fine"/>
    <feColorMatrix in="fine" type="matrix" values="0 0 0 0 0.42  0 0 0 0 0.31  0 0 0 0 0.16  0 0 0 0.16 0" result="fineA"/>
    <feTurbulence type="fractalNoise" baseFrequency="0.006" numOctaves="3" seed="${seed + 7}" result="stain"/>
    <feColorMatrix in="stain" type="matrix" values="0 0 0 0 0.55  0 0 0 0 0.42  0 0 0 0 0.22  0 0 0 0.9 -0.35" result="stainA"/>
    <feMerge><feMergeNode in="stainA"/><feMergeNode in="fineA"/></feMerge>
  </filter>
  <radialGradient id="vig" cx="50%" cy="48%" r="72%"><stop offset="62%" stop-color="${INK}" stop-opacity="0"/><stop offset="100%" stop-color="${INK}" stop-opacity="0.38"/></radialGradient>`;
const LAYER_CSS = `<style>
  .wash * { stroke: none !important; } .wash text { display: none; }
  .ink *:not(text) { fill: none !important; }
</style>`;

/** Turns one of the line drawings into an ink-and-watercolour picture. */
function watercolour(svg, w, h, opts) {
  const m = /viewBox="([^"]+)"/.exec(svg), vb = m[1];
  const inner = repaint(svg.replace(/^<svg[^>]*>/, '').replace(/<\/svg>\s*$/, ''));
  const seed = opts.seed || 1;
  const paper = opts.paper ? `<rect x="-20" y="-20" width="2000" height="2000" fill="${PARCH}"/>` : '';
  const grain = opts.paper ? `<rect x="-20" y="-20" width="2000" height="2000" filter="url(#paper)"/>` : '';
  const vig = opts.paper ? `<rect x="-20" y="-20" width="2000" height="2000" fill="url(#vig)"/>` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${vb}" preserveAspectRatio="xMidYMid slice">
    <defs>${FILTERS(seed)}</defs>${LAYER_CSS}${paper}
    <g class="wash" filter="url(#wash)" opacity="0.92" transform="translate(1.2 0.9)">${inner}</g>
    <g class="ink" filter="url(#ink)">${inner}</g>${grain}${vig}</svg>`;
}

/** A sheet of textured paper: parchment, stains and an ink-blue wash at the edges. */
function sheet(w, h, base, seed, extra = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}">
    <defs>${FILTERS(seed)}</defs>
    <rect width="${w}" height="${h}" fill="${base}"/>${extra}
    <rect width="${w}" height="${h}" filter="url(#paper)"/>
    <rect width="${w}" height="${h}" fill="url(#vig)" opacity="0.7"/></svg>`;
}

function emblem() {
  // the loading-screen seal: parchment disc, ink rings, a magnifier over a red wax dot
  const s = `<svg viewBox="0 0 100 100">
    <circle cx="50" cy="50" r="47" fill="#f6ecd3" stroke="#1c2530" stroke-width="3"/>
    <circle cx="50" cy="50" r="40" fill="none" stroke="#1c2530" stroke-width="1.2"/>
    <circle cx="44" cy="44" r="17" fill="#cdd7de" stroke="#1c2530" stroke-width="4"/>
    <path d="M56 56 L72 72" stroke="#1c2530" stroke-width="7" stroke-linecap="round"/>
    <circle cx="44" cy="44" r="6" fill="#c2271c"/>
    <path d="M30 80 h40" stroke="#c2271c" stroke-width="3" stroke-linecap="round"/></svg>`;
  return watercolour(s, 256, 256, { seed: 4 });
}

async function images() {
  const { chromium } = require('playwright');
  const b = await chromium.launch(), p = await b.newPage({ deviceScaleFactor: 1 });
  async function shot(file, html, w, h) {
    await p.setViewportSize({ width: w, height: h });
    await p.setContent('<body style="margin:0;background:transparent"><div id="a" style="width:' + w + 'px;height:' + h + 'px;overflow:hidden">' + html + '</div></body>');
    await p.waitForTimeout(30);
    await p.locator('#a').screenshot({ path: file.startsWith('/') ? file : path.join(OUT, file), omitBackground: true });
  }
  let seed = 1;
  // places: 960x720, the key content sits in the middle third
  for (const id of PLACES) await shot('places/' + id + '.png', watercolour(art.place(id), 960, 720, { paper: true, seed: seed++ }), 960, 720);
  // character busts: 400x480 on a transparent background
  for (const id in CAST) for (const mood of CAST[id])
    await shot('characters/' + id + '_' + mood + '.png', watercolour(art.portrait(id, mood), 400, 480, { seed: 20 }), 400, 480);
  // surfaces the documents lie on
  await shot('ui/desk.png', sheet(540, 960, PARCH, 31), 540, 960);
  await shot('ui/cork.png', sheet(540, 960, PARCH2, 33, `<rect width="540" height="960" fill="${INK}" opacity="0.10"/>`), 540, 960);
  await shot('ui/steel.png', sheet(540, 960, '#dfe1d6', 35, `<rect width="540" height="960" fill="${WASH}" opacity="0.35"/>`), 540, 960);
  await shot('ui/stone.png', sheet(540, 960, '#d8d0bb', 37, Array.from({ length: 17 }, (_, i) => `<path d="M0 ${i * 60} H540" stroke="${INK}" stroke-opacity="0.10" stroke-width="2"/>`).join('')), 540, 960);
  await shot('ui/folder.png', sheet(540, 960, '#e8cf95', 39, `<rect x="6" y="6" width="528" height="948" rx="10" fill="none" stroke="${INK}" stroke-opacity="0.55" stroke-width="3"/><rect x="0" y="120" width="540" height="14" fill="${RED}" opacity="0.75"/>`), 540, 960);
  await shot('ui/pin.png', watercolour('<svg viewBox="0 0 48 52"><circle cx="24" cy="24" r="19" fill="#c2271c" stroke="#7c150e" stroke-width="2"/><circle cx="18" cy="18" r="5" fill="#fff" opacity="0.6"/></svg>', 48, 52, { seed: 41 }), 48, 52);
  await shot('ui/tape.png', watercolour('<svg viewBox="0 0 144 40"><rect x="4" y="4" width="136" height="32" fill="#fff6c8" opacity="0.8"/></svg>', 144, 40, { seed: 43 }), 144, 40);
  await shot('ui/reel.png', watercolour('<svg viewBox="0 0 64 64"><circle cx="32" cy="32" r="27" fill="none" stroke="#fcf9f0" stroke-width="6"/><circle cx="32" cy="32" r="6" fill="#fcf9f0"/><path d="M32 8 V22 M32 42 V56 M8 32 H22 M42 32 H56" stroke="#fcf9f0" stroke-width="5"/></svg>', 64, 64, { seed: 45 }), 64, 64);
  // loading screen logo: the plugin copies this template image into the package
  await shot(path.join(__dirname, '..', 'godot', 'addons', 'godot_mini_game', 'templates', 'common', 'images', 'logo.png'), emblem(), 256, 256);
  await shot('ui/emblem.png', emblem(), 256, 256);
  await b.close();
}

/* ───── sounds: the same little synth recipes as the HTML version, rendered to WAV ───── */
const SR = 22050;
function mk(len) { return new Float32Array(Math.ceil(len * SR)); }
function env(i, n, gain) { // fast attack, exponential decay
  const a = Math.min(1, i / (0.006 * SR)), d = Math.pow(0.0001 / gain, i / n);
  return gain * a * d;
}
function tone(buf, type, f0, f1, dur, gain, delay = 0) {
  const n = Math.floor(dur * SR), off = Math.floor(delay * SR); let ph = 0;
  for (let i = 0; i < n && off + i < buf.length; i++) {
    const f = f0 * Math.pow(Math.max(20, f1) / f0, i / n); ph += f / SR;
    const x = ph % 1, s = type === 'triangle' ? 4 * Math.abs(x - 0.5) - 1 : Math.sin(2 * Math.PI * ph);
    buf[off + i] += s * env(i, n, gain);
  }
}
function burst(buf, dur, gain, ftype, f0, f1, q = 0.8, delay = 0) {
  const n = Math.floor(dur * SR), off = Math.floor(delay * SR);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0, b0, b1, b2, a1, a2;
  for (let i = 0; i < n && off + i < buf.length; i++) {
    if (i % 32 === 0) {
      const f = f1 ? f0 * Math.pow(f1 / f0, i / n) : f0, w = 2 * Math.PI * Math.min(f, SR * 0.45) / SR, al = Math.sin(w) / (2 * q), c = Math.cos(w), a0 = 1 + al;
      if (ftype === 'lowpass') { b0 = (1 - c) / 2 / a0; b1 = (1 - c) / a0; b2 = b0; }
      else if (ftype === 'highpass') { b0 = (1 + c) / 2 / a0; b1 = -(1 + c) / a0; b2 = b0; }
      else { b0 = al / a0; b1 = 0; b2 = -al / a0; }
      a1 = -2 * c / a0; a2 = (1 - al) / a0;
    }
    const x = Math.random() * 2 - 1, y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    buf[off + i] += y * env(i, n, gain) * 2.2;
  }
}
const SOUNDS = {
  tick: b => burst(b, 0.014, 0.25, 'highpass', 2600),
  blip: b => tone(b, 'sine', 540, 420, 0.04, 0.12),
  paper: b => burst(b, 0.22, 0.3, 'bandpass', 1100, 3600, 0.7),
  wipe: b => { burst(b, 0.34, 0.32, 'bandpass', 700, 2800, 0.6); burst(b, 0.05, 0.3, 'lowpass', 500, 0, 1, 0.3); },
  open: b => burst(b, 0.26, 0.3, 'bandpass', 2400, 900, 0.7),
  pen: b => { burst(b, 0.07, 0.25, 'bandpass', 2700, 3400, 2.5); burst(b, 0.09, 0.25, 'bandpass', 3200, 2400, 2.5, 0.08); },
  key: b => burst(b, 0.012, 0.16, 'highpass', 3500),
  thud: b => { tone(b, 'sine', 120, 36, 0.28, 0.95); burst(b, 0.07, 0.5, 'lowpass', 520); burst(b, 0.2, 0.08, 'bandpass', 1500, 600, 1, 0.03); },
  thud_soft: b => { tone(b, 'sine', 150, 60, 0.16, 0.6); burst(b, 0.04, 0.3, 'lowpass', 700); },
  pin: b => { tone(b, 'triangle', 1700, 800, 0.025, 0.3); tone(b, 'sine', 170, 90, 0.07, 0.5, 0.01); },
  good: b => { tone(b, 'triangle', 660, 660, 0.09, 0.2); tone(b, 'triangle', 880, 880, 0.16, 0.2, 0.09); },
  bad: b => { tone(b, 'sine', 170, 95, 0.24, 0.6); burst(b, 0.09, 0.2, 'lowpass', 380); },
  clock: b => { [0, 0.11, 0.22].forEach((d, i) => tone(b, 'sine', i === 1 ? 1000 : 1250, i === 1 ? 1000 : 1250, 0.02, 0.35, d)); },
  ring: b => { [0, 0.5].forEach(d => { tone(b, 'sine', 400, 400, 0.38, 0.14, d); tone(b, 'sine', 450, 450, 0.38, 0.14, d); }); },
  clunk: b => { burst(b, 0.05, 0.4, 'lowpass', 900); tone(b, 'sine', 95, 70, 0.07, 0.6, 0.01); },
  static: b => burst(b, 0.18, 0.28, 'bandpass', 1900, 1500, 0.6),
  tape: b => burst(b, 0.17, 0.3, 'highpass', 3200, 900, 1.5),
  step: b => burst(b, 0.035, 0.35, 'lowpass', 420),
  gasp: b => { burst(b, 0.22, 0.22, 'bandpass', 900, 2200, 1.2); },
  sting: b => { [196, 233, 294].forEach((f, i) => tone(b, 'triangle', f, f, 0.9, 0.16, i * 0.07)); },
  deduce: b => { [262, 330, 392, 523].forEach((f, i) => tone(b, 'triangle', f, f, 0.7 - i * 0.08, 0.15, i * 0.06)); burst(b, 0.3, 0.12, 'bandpass', 3000, 6000, 0.8, 0.02); },
  hint: b => { burst(b, 0.22, 0.2, 'bandpass', 2400, 1600, 1.4); tone(b, 'sine', 988, 988, 0.5, 0.12, 0.12); tone(b, 'sine', 1319, 1319, 0.6, 0.08, 0.2); },
  heart: b => { tone(b, 'sine', 62, 48, 0.16, 0.9); tone(b, 'sine', 58, 44, 0.14, 0.65, 0.2); },
  tock: b => { tone(b, 'sine', 1900, 1900, 0.025, 0.28); burst(b, 0.02, 0.18, 'highpass', 4000); },
  crack: b => { burst(b, 0.05, 0.6, 'highpass', 2500); burst(b, 0.35, 0.3, 'bandpass', 1800, 500, 1.2, 0.04); tone(b, 'sine', 90, 40, 0.4, 0.5, 0.02); },
  card: b => { burst(b, 0.12, 0.22, 'bandpass', 1800, 3800, 0.9); },
  close: b => { burst(b, 0.16, 0.24, 'bandpass', 3200, 900, 0.8); burst(b, 0.04, 0.2, 'lowpass', 600, 0, 1, 0.12); },
  snap: b => { burst(b, 0.03, 0.4, 'highpass', 3000); tone(b, 'triangle', 420, 160, 0.12, 0.2); }
};
function wav(name, fill) {
  const b = mk(1.1); fill(b);
  let end = b.length; while (end > 1 && Math.abs(b[end - 1]) < 0.0005) end--;
  const n = end, out = Buffer.alloc(44 + n * 2);
  out.write('RIFF', 0); out.writeUInt32LE(36 + n * 2, 4); out.write('WAVEfmt ', 8); out.writeUInt32LE(16, 16); out.writeUInt16LE(1, 20); out.writeUInt16LE(1, 22);
  out.writeUInt32LE(SR, 24); out.writeUInt32LE(SR * 2, 28); out.writeUInt16LE(2, 32); out.writeUInt16LE(16, 34); out.write('data', 36); out.writeUInt32LE(n * 2, 40);
  for (let i = 0; i < n; i++) out.writeInt16LE(Math.max(-32767, Math.min(32767, Math.round(b[i] * 30000))), 44 + i * 2);
  fs.writeFileSync(path.join(OUT, 'audio', name + '.wav'), out);
}

(async () => {
  for (const d of ['places', 'characters', 'ui', 'audio']) fs.mkdirSync(path.join(OUT, d), { recursive: true });
  for (const k in SOUNDS) wav(k, SOUNDS[k]);
  await images();
  console.log('assets written to', OUT);
})();
