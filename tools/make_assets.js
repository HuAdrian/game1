/*
 * Generates the PLACEHOLDER artwork and sound effects in godot/assets.
 * Every file it writes can be replaced by finished art of the same name;
 * the game loads assets by file name and never needs this script to run.
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
  whitlock: ['neutral'], desk: ['neutral'], nair: ['neutral', 'annoyed'], dominic: ['neutral', 'nervous'], beatrice: ['neutral', 'pleased']
};

async function images() {
  const { chromium } = require('playwright');
  const b = await chromium.launch(), p = await b.newPage({ deviceScaleFactor: 1 });
  async function shot(file, html, w, h) {
    await p.setViewportSize({ width: w, height: h });
    await p.setContent('<body style="margin:0;background:transparent"><div id="a" style="width:' + w + 'px;height:' + h + 'px;overflow:hidden">' + html + '</div></body>');
    await p.locator('#a').screenshot({ path: path.join(OUT, file), omitBackground: true });
  }
  for (const id of PLACES) await shot('places/' + id + '.png', art.place(id).replace('<svg ', '<svg width="960" height="720" '), 960, 720);
  for (const id in CAST) for (const mood of CAST[id])
    await shot('characters/' + id + '_' + mood + '.png', art.portrait(id, mood).replace('<svg ', '<svg width="400" height="480" '), 400, 480);
  const grain = 'repeating-linear-gradient(92deg, rgba(120,85,35,.07) 0 2px, transparent 2px 9px)';
  await shot('ui/desk.png', '<div style="width:100%;height:100%;background:' + grain + ',linear-gradient(165deg,#e6d5b0,#d8c39a 45%,#bfa574)"></div>', 540, 960);
  await shot('ui/cork.png', '<div style="width:100%;height:100%;background:radial-gradient(circle at 20% 30%, rgba(80,45,10,.28) 0 1px, transparent 2px) 0 0/13px 13px, radial-gradient(circle at 70% 65%, rgba(255,232,190,.35) 0 1px, transparent 2px) 0 0/9px 9px, #c59a63"></div>', 540, 960);
  await shot('ui/steel.png', '<div style="width:100%;height:100%;background:repeating-linear-gradient(0deg, rgba(255,255,255,.22) 0 1px, transparent 1px 4px), linear-gradient(180deg,#dbe2e4,#b9c4c8)"></div>', 540, 960);
  await shot('ui/stone.png', '<div style="width:100%;height:100%;background:repeating-linear-gradient(0deg, transparent 0 58px, rgba(28,37,48,.16) 58px 60px), repeating-linear-gradient(90deg, transparent 0 94px, rgba(28,37,48,.12) 94px 96px), #c9c7bd"></div>', 540, 960);
  await shot('ui/pin.png', '<div style="width:44px;height:44px;margin:2px;border-radius:50%;background:radial-gradient(circle at 35% 30%, #ef6a5d, #c2271c 60%, #7c150e);box-shadow:0 3px 3px rgba(0,0,0,.35)"></div>', 48, 52);
  await shot('ui/tape.png', '<div style="width:140px;height:36px;margin:2px;background:rgba(255,244,190,.78);border-left:3px dashed rgba(120,100,40,.4);border-right:3px dashed rgba(120,100,40,.4)"></div>', 144, 40);
  await shot('ui/folder.png', '<div style="width:100%;height:100%;box-sizing:border-box;padding-top:60px"><div style="position:absolute;top:0;left:0;width:230px;height:64px;background:#ecd29b;border:3px solid #9a7a35;border-bottom:0;border-radius:18px 18px 0 0;box-sizing:border-box"></div><div style="position:relative;height:100%;background:' + grain + ',#ecd29b;border:3px solid #9a7a35;border-radius:0 30px 0 0;box-sizing:border-box"></div></div>', 540, 960);
  await shot('ui/reel.png', '<div style="width:60px;height:60px;margin:2px;box-sizing:border-box;border-radius:50%;border:6px solid #f3ecda;background:conic-gradient(#f3ecda 0 12%, transparent 0 33%, #f3ecda 0 45%, transparent 0 66%, #f3ecda 0 78%, transparent 0)"></div>', 64, 64);
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
  sting: b => { [196, 233, 294].forEach((f, i) => tone(b, 'triangle', f, f, 0.9, 0.16, i * 0.07)); }
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
