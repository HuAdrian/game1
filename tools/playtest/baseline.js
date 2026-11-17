/*
 * Fixed-answer playthrough of Case 01 for regression checks.
 *
 * Every answer comes from the case JSON (godot/cases/missing_violinist.json),
 * so the route is the same on every run and the result code it ends on can be
 * compared between builds. It drives the exported Web build in a phone-sized
 * Chromium with real taps and typing, then copies the result code from the
 * case report.
 *
 *   python3 -m http.server 8765        (from the folder holding index.html)
 *   node tools/playtest/baseline.js [url]
 *
 * MINI=1 plays a MiniGame-preset build served by tools/playtest/minigame/serve.py:
 * answers are typed through the host keyboard stand-in, every clip that plays is
 * recorded, and the result code is read from the host clipboard.
 *
 * Options for focused checks (all off by default, which plays the fixed route):
 *   ROUTE=wiretap,tail   follow only these leads        STOP=1  end after the leads
 *   TYPED='{"time":"6.15 p.m."}'  type these instead of the case's answers in the
 *                        first wiretap round; RETYPED='{...}' for the retry round
 *   TAIL_FIRST=D         send the team to this building first (reaches the retry radio)
 *   HINT=address         spend a hint on that wiretap field after the tape plays
 *   RESTART=1            reload at the end and read the word bank back; in MINI mode
 *                        Godot's own user:// storage is wiped first, so only the
 *                        host-storage copy can bring it back
 *
 * Needs Playwright with Chromium. Speech is replaced by a silent stand-in that
 * takes a realistic time per line; nothing else is stubbed.
 */
const fs = require('fs'), path = require('path');
const { chromium } = require('playwright');
const CASE = JSON.parse(fs.readFileSync(path.join(__dirname, '../../godot/cases/missing_violinist.json'), 'utf8'));
const URL = process.argv[2] || 'http://localhost:8765/index.html';
const SHOTS = process.env.SHOTS || '';
const MINI = !!process.env.MINI;

// The fixed route: every main lead, plus one optional lead so every scene type is played.
const ROUTE = process.env.ROUTE ? process.env.ROUTE.split(',') : ['wiretap', 'tail', 'interrogation', 'sales', 'forgery', 'note', 'frontdesk'];
const lead = id => CASE.leads.find(l => l.id === id).scene;
let PAGE = null;   // for a screenshot if the run fails

(async () => {
  const b = await chromium.launch({ args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
  const ctx = await b.newContext({ viewport: { width: 390, height: 780 }, hasTouch: true, isMobile: true });
  await ctx.grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new globalThis.URL(URL).origin });
  const p = await ctx.newPage(); PAGE = p;
  const errs = [];
  p.on('pageerror', e => errs.push('PAGEERROR ' + e.message));
  p.on('response', r => { if (r.status() >= 400) errs.push(r.status() + ' ' + new globalThis.URL(r.url()).pathname); });
  let engine = null;
  p.on('console', m => { const t = m.text(); if (/^Godot Engine v/.test(t)) engine = t.split(' - ')[0]; if (/ERROR|SCRIPT/.test(t) || (m.type() === 'error' && !/Failed to load resource/.test(t))) errs.push(t.slice(0, 300)); });
  // every clip that starts playing, in order
  await p.addInitScript(() => {
    window.__voiceSeq = []; let last = '';
    setInterval(() => { try { const v = JSON.parse(window.cfTJson || '{}').voice || ''; if (v && v !== last) window.__voiceSeq.push(v); last = v; } catch (e) {} }, 40);
  });
  if (!MINI) await p.addInitScript(() => {
    class U { constructor(t) { this.text = t; } }
    window.SpeechSynthesisUtterance = U;
    const q = []; let busy = false;
    function pump() { if (busy || !q.length) return; busy = true; const u = q.shift();
      setTimeout(() => { u.onstart && u.onstart(); setTimeout(() => { busy = false; u.onend && u.onend(); pump(); }, Math.max(60, u.text.length * 12)); }, 5); }
    Object.defineProperty(window, 'speechSynthesis', { value: { speaking: false, pending: false, paused: false,
      getVoices: () => [{ name: 'Google UK English Female', lang: 'en-GB' }, { name: 'Google UK English Male', lang: 'en-GB' }],
      speak: u => { q.push(u); pump(); }, cancel() { q.length = 0; }, resume() {}, addEventListener() {} } });
  });
  await p.goto(URL + (MINI ? '' : '?cftest=1'));
  await p.waitForFunction(() => window.cfTJson, null, { timeout: 120000 });

  let n = 0;
  const shot = async name => { if (SHOTS) await p.screenshot({ path: path.join(SHOTS, String(++n).padStart(2, '0') + '-' + name + '.png') }); };
  const T = () => p.evaluate(() => JSON.parse(window.cfTJson || 'null'));
  const box = () => p.evaluate(() => { const r = document.querySelector('canvas').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; });
  const tapAt = async (it, fy = 0.5) => { const c = await box(); await p.mouse.click(c[0] + (it[0] + it[2] / 2) * c[2], c[1] + (it[1] + it[3] * fy) * c[3]); };
  const settle = async (max = 150) => {
    let quiet = 0;
    for (let i = 0; i < max; i++) {
      await p.waitForTimeout(170);
      const t = await T();
      if (t.wipe) { quiet = 0; await tapAt([0.02, 0.01, 0.08, 0.03]); await p.waitForTimeout(450); continue; }
      if (t.dlg) { quiet = 0; await tapAt([0.02, 0.01, 0.08, 0.03]); continue; }
      if (++quiet >= 6) return;
    }
    throw new Error('dialogue never ended');
  };
  // a fresh, stable reading of the published state: two consecutive frames that agree on this control
  const fresh = async id => {
    let a = await T();
    for (let i = 0; i < 40; i++) {
      await p.waitForFunction(k => window.cfTJson && JSON.parse(window.cfTJson).tick > k, a.tick, { timeout: 15000 });
      const c = await T();
      if (JSON.stringify(a.items[id]) === JSON.stringify(c.items[id]) && a.dlg === c.dlg && a.wipe === c.wipe && a.sheet === c.sheet) return c;
      a = c;
    }
    return a;
  };
  const click = async (id, inDoc = false) => {
    for (let i = 0; i < 60; i++) {
      const t = await fresh(id), it = t.items[id];
      if (t.dlg || t.wipe) { await settle(); continue; }
      if (it && !it[4]) {
        const mid = it[1] + it[3] / 2, inScroll = !inDoc || (it[1] >= t.scroll[0] - 0.001 && it[1] + it[3] <= t.scroll[1] + 0.001);
        if (mid > 0.02 && mid < 0.98 && inScroll) { await tapAt(it); await p.waitForTimeout(250); return; }
        await p.evaluate(x => window.cfShow && window.cfShow(x), id);
      }
      await p.waitForTimeout(200);
    }
    throw new Error('never found ' + id + '; on screen: ' + Object.keys((await T()).items).join(','));
  };
  const doc = id => click(id, true);
  const enabled = async id => { for (let i = 0; i < 1600; i++) { const t = await T(); if (t.items[id] && !t.items[id][4]) return; await p.waitForTimeout(150); } throw new Error('never enabled: ' + id); };
  const type = MINI
    ? async (id, text) => { await doc('field-' + id); await p.waitForFunction(() => window.__kb.open, null, { timeout: 10000 }); await p.evaluate(t => { window.__kb.type(t); window.__kb.done(); }, text); await p.waitForTimeout(200); }
    : async (id, text) => { await p.locator('#cf-' + id).tap(); await p.keyboard.type(text, { delay: 8 }); };
  const log = async label => { const t = await T(); console.log(('  ' + label).padEnd(24), t.clock.padEnd(9), 'cards:', t.evidence.join(',')); };

  // ── play ──
  await shot('home');
  await click('open-case'); await settle(); await click('proceed'); await settle();

  for (const id of ROUTE) {
    const sc = lead(id);
    await doc('lead-' + id); await settle(); await shot(id);
    if (sc.type === 'wiretap') {
      const typed = JSON.parse(process.env.TYPED || '{}'), retyped = JSON.parse(process.env.RETYPED || '{}');
      await click('tape-play');
      for (const f of sc.form.fields) await type(f.id, f.id in typed ? typed[f.id] : f.answer);
      await enabled('submit-notes'); await shot('wiretap-typed');
      if (process.env.HINT) { await click('hint'); await p.waitForTimeout(400); await click('confirm-yes'); await settle(); }
      await click('submit-notes'); await p.waitForTimeout(900); await shot('wiretap-marked'); await settle();
      if ((await T()).items['tape-play']) {   // a lead went cold: the retry call reopens only the wrong fields
        const marks = (await T()).marks.L || {};
        await click('tape-play');
        for (const f of sc.form.fields) if (marks[sc.id + '.' + f.id] && !marks[sc.id + '.' + f.id].ok) await type(f.id, f.id in retyped ? retyped[f.id] : f.answer);
        await enabled('submit-notes'); await shot('wiretap-retyped'); await click('submit-notes'); await p.waitForTimeout(900); await settle();
      }
    } else if (sc.type === 'tail') {
      await click('tape-play');
      if (process.env.TAIL_FIRST) {
        await doc('map-' + process.env.TAIL_FIRST); await enabled('send-team'); await click('send-team'); await settle();
        await click('tape-play');
      }
      await doc('map-' + sc.answer); await enabled('send-team'); await click('send-team'); await settle();
      await click('proceed'); await settle();
    } else if (sc.type === 'interrogation') {
      for (const s of sc.statements) {
        await click('v-' + s.verdict);
        if (s.verdict !== 'NG') await doc('line-' + s.proof[0]);
        await p.waitForTimeout(400); await settle();
      }
      for (const cs of sc.cardStatements) {
        if ((await T()).evidence.includes(cs.card)) { await click('present'); await p.waitForTimeout(400); await click('pick-' + cs.card); }
        else await click('pass');
        await p.waitForTimeout(300); await settle();
      }
      await settle();
    } else if (sc.type === 'chart') {
      await doc('sent-' + sc.sentences.find(s => s.false).id); await settle();
      await click('opt-' + sc.rewrite.options.findIndex(o => o.correct)); await settle();
    } else if (sc.type === 'forgery') {
      for (const s of sc.letter.paragraphs.flat().filter(s => s.error)) {
        await doc('sent-' + s.id); await p.waitForTimeout(300);
        await click('opt-' + s.error.options.findIndex(o => o.correct)); await p.waitForTimeout(400);
      }
      await settle();
    } else if (sc.type === 'torn') {
      for (const pc of sc.pieces) { await click('link-' + pc.options.indexOf(pc.answer)); await p.waitForTimeout(350); }
      await settle();
    } else if (sc.type === 'scan') {
      for (const q of sc.questions) { await doc('line-' + q.answer[0]); await p.waitForTimeout(400); await settle(); }
      await settle();
    }
    await log('after ' + id);
  }

  if (process.env.STOP) {
    const t = await T(), voice = await p.evaluate(() => window.__voiceSeq);
    console.log('CLIPS', JSON.stringify(voice));
    console.log('STOPPED', JSON.stringify({ mini: t.mini, marks: t.marks, clock: t.clock, words: t.words, consoleErrors: [...new Set(errs)] }));
    await b.close(); return;
  }

  // evidence board: every deduction the held cards allow, in the order the case lists them
  await click('hub-leave'); await p.waitForTimeout(400); if ((await T()).items['confirm-yes']) await click('confirm-yes');
  await settle(); await p.waitForTimeout(1500); await settle(); await shot('board');
  const held = (await T()).evidence, made = new Set();
  for (const d of CASE.board.deductions) {
    const key = d.same || d.id;
    if (made.has(key) || !d.cards.every(c => held.includes(c))) continue;
    await doc('card-' + d.cards[0]); await doc('card-' + d.cards[1]);
    await click('connect');
    // every connection ends with Sam saying something; the payoff plays first
    await p.waitForFunction(() => JSON.parse(window.cfTJson).dlg, null, { timeout: 15000 }); await p.waitForTimeout(500); await settle();
    made.add(key);
  }
  console.log('  deductions:', (await T()).deductions.join(','));

  // accusation: the culprit, proved by the first three strong deductions made
  await click('board-done'); await p.waitForTimeout(400); await click('confirm-yes'); await settle(); await shot('accuse');
  await doc('suspect-' + CASE.accusation.culprit);
  const strong = CASE.board.deductions.filter(d => d.strong && made.has(d.id)).slice(0, 3);
  for (const d of strong) await doc('proof-d-' + d.id);
  await click('arrest'); await p.waitForTimeout(1500);
  for (let i = 0; i < 60 && !(await T()).items['proceed']; i++) await p.waitForTimeout(200);
  await click('proceed'); await settle(); await click('proceed'); await p.waitForTimeout(900); await shot('report');

  await click('copy'); await p.waitForTimeout(300);
  const code = await p.evaluate(m => m ? window.__clipboard : navigator.clipboard.readText(), MINI);
  const t = await T();
  const sum = s => { const m = t.marks[s] || {}; const k = Object.keys(m); return k.filter(x => m[x].ok).length + '/' + k.length; };
  const voice = await p.evaluate(() => window.__voiceSeq);
  if (MINI) console.log('CLIPS', JSON.stringify(voice));
  console.log('RESULT', JSON.stringify({ engine, mini: t.mini, code, words: t.words, clipsPlayed: voice.length, ending: t.ending.verdict, clock: t.clock, deductions: t.deductions,
    firstTry: { L: sum('L'), R: sum('R'), W: sum('W') }, consoleErrors: [...new Set(errs)] }));
  if (process.env.RESTART) {
    if (MINI) await p.evaluate(async () => { for (const d of await indexedDB.databases()) indexedDB.deleteDatabase(d.name); });
    await p.reload();
    await p.waitForFunction(() => window.cfTJson, null, { timeout: 120000 });
    await p.waitForTimeout(800);
    const r = await T();
    console.log('AFTER RESTART', JSON.stringify({ words: r.words, wiped_user_storage: MINI }));
  }
  await b.close();
})().catch(async e => {
  console.error('FAILED', e.message.split('\n')[0]);
  if (PAGE && SHOTS) await PAGE.screenshot({ path: path.join(SHOTS, 'failure.png') }).catch(() => {});
  process.exit(1);
});
