/*
 * CASE FILES — engine
 *
 * Knows nothing about any particular case. It provides:
 *   - the case clock (moves only on mistakes and hints)
 *   - Sam's dialogue, hints, stamps and toasts
 *   - the notebook (case notes + a word bank that persists between cases)
 *   - text-to-speech for calls, with a transcript fallback
 *   - saving, scoring, band estimates and result codes
 *   - a runner that plays a case's scenes in order
 *
 * Scene types live in scenes.js and register themselves with
 * CaseFiles.registerScene(type, async (scene, ctx) => { ... }).
 */
(function () {
  'use strict';

  var CF = (window.CaseFiles = { cases: {}, order: [], scenes: {}, docs: {} });
  CF.registerCase = function (c) { CF.cases[c.id] = c; CF.order.push(c.id); };
  CF.registerScene = function (type, fn) { CF.scenes[type] = fn; };
  CF.registerDoc = function (kind, fn) { CF.docs[kind] = fn; };

  /* ───────────── small helpers ───────────── */

  function build(el, props, kids) {
    props = props || {};
    Object.keys(props).forEach(function (k) {
      var v = props[k];
      if (v == null || v === false) return;
      if (k === 'class') el.setAttribute('class', v);
      else if (k === 'html') el.innerHTML = v;
      else if (k.slice(0, 2) === 'on') el.addEventListener(k.slice(2), v);
      else el.setAttribute(k, v === true ? '' : v);
    });
    (function add(list) {
      list.forEach(function (kid) {
        if (kid == null || kid === false) return;
        if (Array.isArray(kid)) add(kid);
        else el.appendChild(typeof kid === 'object' ? kid : document.createTextNode(String(kid)));
      });
    })(kids);
    return el;
  }
  function h(tag, props) { return build(document.createElement(tag), props, [].slice.call(arguments, 2)); }
  function svg(tag, props) { return build(document.createElementNS('http://www.w3.org/2000/svg', tag), props, [].slice.call(arguments, 2)); }
  function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;'); }
  /** Escapes text and turns *stars* into emphasis. */
  function rich(s) { return esc(s).replace(/\*([^*]+)\*/g, '<em>$1</em>'); }
  function fmt(s, vars) { return String(s).replace(/\{(\w+)\}/g, function (m, k) { return vars && vars[k] != null ? vars[k] : m; }); }
  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function $(id) { return document.getElementById(id); }
  function toMin(hhmm) { var p = hhmm.split(':'); return +p[0] * 60 + +p[1]; }
  function clockText(mins) {
    var hr = Math.floor(mins / 60) % 24, m = mins % 60;
    return ((hr + 11) % 12 + 1) + ':' + (m < 10 ? '0' : '') + m + (hr >= 12 ? ' pm' : ' am');
  }
  CF.h = h; CF.svg = svg; CF.rich = rich; CF.fmt = fmt; CF.wait = wait; CF.clockText = clockText;

  var store = {
    get: function (k, d) { try { var v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set: function (k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private mode: play on without saving */ } },
    del: function (k) { try { localStorage.removeItem(k); } catch (e) {} }
  };
  var WORDS_KEY = 'casefiles.words';
  function saveKey(id) { return 'casefiles.save.' + id; }

  /* ───────────── speech ───────────── */

  var Speech = {
    supported: typeof window.speechSynthesis !== 'undefined' && typeof window.SpeechSynthesisUtterance !== 'undefined',
    voices: [],
    keep: [],
    init: function () {
      if (!this.supported) return;
      var self = this;
      var load = function () { try { self.voices = speechSynthesis.getVoices() || []; } catch (e) {} };
      load();
      if (speechSynthesis.addEventListener) speechSynthesis.addEventListener('voiceschanged', load);
    },
    /** Picks a British voice, matching "female"/"male" when the device offers a choice. */
    pick: function (prefer) {
      var gb = this.voices.filter(function (v) { return /^en[-_]GB/i.test(v.lang); });
      var pool = gb.length ? gb : this.voices.filter(function (v) { return /^en/i.test(v.lang); });
      if (!pool.length) return null;
      var fem = /female|kate|serena|martha|hazel|susan|libby|sonia|maisie|stephanie|fiona|moira|amy|emma/i;
      var mal = /\bmale|daniel|arthur|george|oliver|ryan|thomas|malcolm|gordon|brian/i;
      var want = prefer === 'male'
        ? pool.filter(function (v) { return mal.test(v.name) && !/female/i.test(v.name); })
        : pool.filter(function (v) { return fem.test(v.name); });
      if (want.length) return want[0];
      // No named match: use different voices for different speakers if we can.
      return prefer === 'male' && pool.length > 1 ? pool[1] : pool[0];
    },
    stop: function () { try { if (this.supported) speechSynthesis.cancel(); } catch (e) {} },
    /**
     * Speaks the lines in order. Resolves true if audio played, false if the
     * device has no working voice (the caller then shows a transcript).
     */
    play: function (lines, o) {
      var self = this; o = o || {};
      return new Promise(function (resolve) {
        if (!self.supported) return resolve(false);
        var done = false, started = false, t0 = Date.now(), w1, w2;
        var chars = lines.join(' ').length;
        function finish(ok) {
          if (done) return; done = true;
          clearTimeout(w1); clearTimeout(w2); self.keep = [];
          resolve(ok);
        }
        try {
          if (speechSynthesis.speaking || speechSynthesis.pending) speechSynthesis.cancel();
          if (speechSynthesis.paused) speechSynthesis.resume();
          var voice = self.pick(o.prefer);
          // Queue every sentence inside the tap that started playback (phones
          // require that), and keep references so they are not collected early.
          self.keep = lines.map(function (text, i) {
            var u = new SpeechSynthesisUtterance(text);
            u.lang = 'en-GB';
            if (voice) u.voice = voice;
            u.rate = o.rate || 0.95; u.pitch = o.pitch || 1;
            u.onstart = function () { started = true; if (o.onLine) o.onLine(i); };
            u.onerror = function (e) {
              if (e.error === 'interrupted' || e.error === 'canceled') finish(started);
              else finish(false);
            };
            if (i === lines.length - 1) u.onend = function () {
              // A silent engine "finishes" instantly; treat that as no audio.
              finish(Date.now() - t0 > Math.min(1500, chars * 8));
            };
            return u;
          });
          self.keep.forEach(function (u) { speechSynthesis.speak(u); });
        } catch (e) { return finish(false); }
        w1 = setTimeout(function () { if (!started) { self.stop(); finish(false); } }, 5000);
        w2 = setTimeout(function () { finish(true); }, chars * 120 + 15000);
      });
    }
  };
  CF.Speech = Speech;

  /* ───────────── scoring and result codes ───────────── */

  /** Share of first-try correct answers → rough band. One short case is a small sample. */
  function bandFor(marks) {
    var got = 0, total = 0;
    Object.keys(marks || {}).forEach(function (k) { total += marks[k].w; if (marks[k].ok) got += marks[k].w; });
    if (!total) return { band: null, got: 0, total: 0 };
    var p = got / total;
    var band = p >= 0.92 ? 7 : p >= 0.8 ? 6.5 : p >= 0.66 ? 6 : p >= 0.5 ? 5.5 : p >= 0.34 ? 5 : 4.5;
    return { band: band, got: got, total: total };
  }
  CF.bandFor = bandFor;

  var ALPHA = 'ABCDEFGHJKMNPQRSTVWXYZ23456789'; // no I, L, O, U, 0, 1
  var ENDINGS = ['C', 'W', 'R'];
  function bandIdx(b) { return Math.max(0, Math.min(10, Math.round(((b || 4) - 4) * 2))); }
  /** Packs ending, three bands, hints used and minutes lost into a short code. */
  function encodeResult(c, r) {
    var n = ENDINGS.indexOf(r.ending);
    n = n * 11 + bandIdx(r.L); n = n * 11 + bandIdx(r.R); n = n * 11 + bandIdx(r.W);
    n = n * 4 + Math.min(3, r.hints); n = n * 400 + Math.min(399, r.lost);
    var body = '', sum = 0;
    for (var i = 0; i < 5; i++) { var d = n % 30; body = ALPHA[d] + body; sum += d * (i + 1); n = Math.floor(n / 30); }
    return c.code + c.number + '-' + body + ALPHA[sum % 30];
  }
  function decodeResult(text) {
    var m = /^([A-Z]+)(\d+)-([A-Z2-9]{6})$/.exec(String(text || '').trim().toUpperCase().replace(/\s+/g, ''));
    if (!m) return null;
    var n = 0, sum = 0, body = m[3];
    for (var i = 0; i < 5; i++) {
      var d = ALPHA.indexOf(body[i]); if (d < 0) return null;
      n = n * 30 + d; sum += d * (5 - i);
    }
    if (ALPHA[sum % 30] !== body[5]) return null;
    var r = { code: m[1], number: m[2] };
    r.lost = n % 400; n = Math.floor(n / 400);
    r.hints = n % 4; n = Math.floor(n / 4);
    r.W = 4 + (n % 11) / 2; n = Math.floor(n / 11);
    r.R = 4 + (n % 11) / 2; n = Math.floor(n / 11);
    r.L = 4 + (n % 11) / 2; n = Math.floor(n / 11);
    if (n > 2) return null;
    r.ending = ENDINGS[n];
    return r;
  }
  CF.encodeResult = encodeResult; CF.decodeResult = decodeResult;

  /* ───────────── word bank ───────────── */

  var WORD_GROUPS = [
    { t: 'paraphrase', title: 'Paraphrases', sub: 'What he said → what the document says' },
    { t: 'trap', title: 'Not Given traps', sub: 'Mentioned nearby, but never actually stated' },
    { t: 'chart', title: 'Chart language', sub: 'For describing data' },
    { t: 'grammar', title: 'Grammar traps', sub: 'Wrong → right' },
    { t: 'linker', title: 'Linking words', sub: 'The word → the job it does' }
  ];
  function words() { return store.get(WORDS_KEY, []); }
  function addWord(entry, caseTitle) {
    var list = words();
    var dup = list.some(function (w) { return w.t === entry.t && w.a === entry.a && w.b === entry.b; });
    if (dup) return false;
    list.push({ t: entry.t, a: entry.a, b: entry.b, n: entry.n || '', c: caseTitle });
    store.set(WORDS_KEY, list);
    return true;
  }
  function wordBankView() {
    var list = words();
    if (!list.length) return h('p', { class: 'nb-empty' }, 'Nothing here yet. Every paraphrase, linking word and grammar trap you meet in a case is saved here automatically.');
    return WORD_GROUPS.map(function (g) {
      var items = list.filter(function (w) { return w.t === g.t; });
      if (!items.length) return null;
      return h('section', { class: 'nb-group nb-' + g.t },
        h('h3', {}, g.title, h('span', {}, ' ' + items.length)),
        h('p', { class: 'nb-sub' }, g.sub),
        items.map(function (w) {
          return h('div', { class: 'nb-word' },
            h('span', { class: 'nb-a' }, w.a), h('span', { class: 'nb-arrow' }, '→'), h('span', { class: 'nb-b' }, w.b),
            w.n ? h('p', { class: 'nb-n' }, w.n) : null);
        }));
    });
  }

  /* ───────────── run state ───────────── */

  var run = null; // { c: case, s: state, hint: fn|null }

  function newState(c) {
    return { scene: 0, lost: 0, hintsLeft: c.hints, marks: {}, facts: [], evidence: [], flags: {}, ending: null };
  }
  function save() { if (run) store.set(saveKey(run.c.id), run.s); }

  /* ───────────── chrome: bar, sheet, toasts ───────────── */

  function updateBar() {
    var bar = $('bar');
    if (!run) { bar.hidden = true; return; }
    bar.hidden = false;
    var c = run.c, s = run.s, sc = c.scenes[s.scene] || c.scenes[c.scenes.length - 1];
    var now = toMin(c.clock.start) + s.lost, dead = toMin(c.clock.deadline);
    $('bar-case').textContent = 'Case ' + c.number;
    $('bar-scene').textContent = sc.title;
    $('clock-time').textContent = clockText(now);
    $('clock-sub').textContent = now > dead ? 'past ' + c.clock.deadlineName + '!' : c.clock.deadlineName + ' ' + clockText(dead).replace(' pm', '');
    $('hand-m').style.transform = 'rotate(' + now * 6 + 'deg)';
    $('hand-h').style.transform = 'rotate(' + now / 2 + 'deg)';
    $('clock').classList.toggle('late', now > dead);
    $('clock').classList.toggle('tight', now > toMin(c.clock.comfortable) && now <= dead);
    var pips = $('hint-pips'); pips.textContent = '';
    for (var i = 0; i < c.hints; i++) pips.appendChild(h('i', { class: i < s.hintsLeft ? 'on' : '' }));
    var prog = $('progress'); prog.textContent = '';
    c.scenes.forEach(function (x, i) { prog.appendChild(h('i', { class: i < s.scene ? 'done' : i === s.scene ? 'now' : '' })); });
  }

  function toast(text, cls) {
    var t = h('div', { class: 'toast ' + (cls || '') }, text);
    var box = $('toasts');
    while (box.children.length >= 2) box.firstChild.remove(); // never bury the page in messages
    box.appendChild(t);
    setTimeout(function () { t.classList.add('out'); }, 2300);
    setTimeout(function () { t.remove(); }, 2800);
  }

  /** Several notebook entries or evidence cards arriving together share one toast. */
  var queued = { note: [], ev: [] }, queueTimer = null;
  function queueToast(kind, label) {
    queued[kind].push(label);
    clearTimeout(queueTimer);
    queueTimer = setTimeout(function () {
      ['note', 'ev'].forEach(function (k) {
        var a = queued[k]; queued[k] = [];
        if (!a.length) return;
        if (k === 'note') { toast(a.length === 1 ? 'Saved to notebook: ' + a[0] : a.length + ' new entries in your notebook', 'note'); CF.Sound.play('pen'); }
        else { toast(a.length === 1 ? 'Pinned to the board: ' + a[0] : a.length + ' cards pinned to the board', 'ev'); CF.Sound.play('pin'); }
      });
    }, 80);
  }

  function openSheet(content, cls) {
    var sheet = $('sheet');
    sheet.textContent = '';
    var close = function () { sheet.hidden = true; sheet.textContent = ''; };
    var panel = h('div', { class: 'sheet-panel ' + (cls || ''), onclick: function (e) { e.stopPropagation(); } }, content);
    sheet.appendChild(panel);
    sheet.onclick = close;
    sheet.hidden = false;
    return close;
  }

  function openNotebook(tab) {
    var body = h('div', { class: 'nb-body' });
    var tabs = [];
    if (run) { tabs.push({ id: 'case', label: 'Notes' }); tabs.push({ id: 'board', label: 'Board' }); }
    tabs.push({ id: 'words', label: 'Words' });
    var tabBar = h('div', { class: 'nb-tabs' });
    function show(id) {
      [].forEach.call(tabBar.children, function (b) { b.classList.toggle('on', b.getAttribute('data-tab') === id); });
      body.textContent = ''; body.className = 'nb-body nb-' + id;
      CF.Sound.play('paper');
      if (id === 'words') { build(body, {}, [wordBankView()]); return; }
      var s = run.s, c = run.c;
      if (id === 'board') {
        // The cork board: every evidence card found so far, pinned up.
        var held = c.evidence.filter(function (e) { return s.evidence.indexOf(e.id) >= 0; });
        if (!held.length) body.appendChild(h('p', { class: 'nb-empty' }, 'The board is empty. Evidence is pinned here as you find it.'));
        held.forEach(function (e, i) {
          body.appendChild(h('div', { class: 'cork-card tilt' + (i % 3) }, h('i', { class: 'pin' }), h('b', {}, e.title), h('p', {}, e.text)));
        });
        return;
      }
      if (!s.facts.length) body.appendChild(h('p', { class: 'nb-empty' }, 'No notes yet. Facts appear here as you find them.'));
      s.facts.forEach(function (f) {
        body.appendChild(h('div', { class: 'nb-fact' }, h('h4', {}, f.title), h('p', {}, f.text)));
      });
    }
    tabs.forEach(function (t) { tabBar.appendChild(h('button', { class: 'nb-tab', 'data-tab': t.id, onclick: function () { show(t.id); } }, t.label)); });
    var close = openSheet([
      h('div', { class: 'nb-rings', 'aria-hidden': 'true' }),
      h('div', { class: 'nb-head' }, h('h2', {}, 'Notebook'), h('button', { class: 'nb-close', 'aria-label': 'Close notebook', onclick: function () { close(); } }, '×')),
      tabBar, body,
      run ? h('button', { class: 'btn ghost small nb-leave', onclick: function () { save(); Speech.stop(); location.reload(); } }, 'Leave case (progress is saved)') : null
    ], 'notebook');
    show(tab && tabs.some(function (t) { return t.id === tab; }) ? tab : tabs[0].id);
    $('btn-notebook').classList.remove('ping');
  }

  /* ───────────── dialogue ───────────── */

  function parseLine(line) {
    if (typeof line !== 'string') return line;
    var m = /^@(\w+)\s+([\s\S]*)$/.exec(line);
    return m ? { who: m[1], text: m[2] } : { who: 'sam', text: line };
  }

  /** Shows lines one at a time at the bottom of the screen; tap to continue. */
  function say(lines, vars) {
    lines = (Array.isArray(lines) ? lines : [lines]).filter(Boolean).map(parseLine);
    if (!lines.length) return Promise.resolve();
    var dlg = $('dialogue'), cast = (run && run.c.cast) || {};
    return new Promise(function (resolve) {
      var i = 0, shownAt = 0, prev = null;
      function show() {
        var l = lines[i], who = cast[l.who] || { name: l.who, initials: '?', tone: 'grey', role: '' };
        var mood = (run && run.moods[l.who]) || 'neutral';
        dlg.textContent = '';
        dlg.appendChild(h('div', { class: 'dlg-wrap' },
          CF.art.hasPortrait(l.who) ? h('div', { class: 'dlg-portrait tone-' + who.tone + (l.who !== prev ? ' enter' : ' talk'), html: CF.art.portrait(l.who, mood) }) : null,
          h('div', { class: 'dlg-box tone-' + who.tone + (l.who === 'sam' ? ' is-sam' : '') },
            h('div', { class: 'dlg-who' }, h('b', {}, who.name), h('small', {}, who.role)),
            h('p', { class: 'dlg-text', html: rich(fmt(l.text, vars)) }),
            h('span', { class: 'dlg-next' }, i < lines.length - 1 ? 'tap to continue ▸' : 'tap ▸'))));
        prev = l.who;
        if (l.who === 'sam' && run) delete run.moods.sam; // Sam's reaction shows once
        CF.Sound.play('blip');
        shownAt = Date.now();
      }
      dlg.onclick = function () {
        if (Date.now() - shownAt < 280) return; // ignore accidental double taps
        if (++i >= lines.length) { dlg.hidden = true; dlg.onclick = null; dlg.textContent = ''; resolve(); }
        else show();
      };
      dlg.hidden = false; show();
    });
  }

  /* ───────────── ctx: what scenes can do ───────────── */

  var ctx = {
    h: h, svg: svg, rich: rich, fmt: fmt, wait: wait, speech: Speech, say: say, toast: toast,
    get case() { return run.c; },
    get state() { return run.s; },
    get now() { return toMin(run.c.clock.start) + run.s.lost; },
    save: save,

    setStage: function () {
      var st = $('stage'); st.textContent = ''; st.scrollTop = 0;
      build(st, {}, [].slice.call(arguments));
      if (st.childNodes.length) {
        $('app').classList.remove('place-full');
        if (st.querySelector('.paper')) CF.Sound.play('paper');
      }
      return st;
    },
    /** Where the scene happens: an illustrated backdrop and the surface documents lie on. */
    setPlace: function (id, surface) {
      var app = $('app'), art = $('place-art');
      id = id || 'unit9';
      if (art.getAttribute('data-place') !== id) { art.setAttribute('data-place', id); art.innerHTML = CF.art.place(id); }
      app.className = app.className.replace(/\s*surface-\w+/g, '') + ' surface-' + (surface || 'wood');
    },
    /** An object standing in the scene: the tape recorder, the radio, the suspect. */
    setProp: function (node) {
      var p = $('prop'); p.textContent = '';
      if (node) p.appendChild(node);
      $('app').classList.toggle('has-prop', !!node);
    },
    /** Changes how a cast member looks the next time they are drawn. */
    mood: function (who, mood) { if (mood) run.moods[who] = mood; else delete run.moods[who]; },
    setTray: function () {
      var tr = $('tray'); tr.textContent = '';
      build(tr, {}, [].slice.call(arguments));
      tr.hidden = !tr.childNodes.length;
      return tr;
    },
    button: function (label, cls, onclick) { return h('button', { class: 'btn ' + (cls || ''), onclick: onclick }, label); },
    /** Shows one big button in the tray and waits for the tap. */
    proceed: function (label) {
      var self = this;
      return new Promise(function (resolve) {
        self.setTray(self.button(label || 'Continue', 'primary', function () { self.setTray(); resolve(); }));
      });
    },

    /** Scene change: a case folder slides over the desk, then opens on the new place. */
    titleCard: function (sc) {
      var self = this, idx = run.c.scenes.indexOf(sc), wipe = $('wipe');
      this.setHint(null); this.setTray();
      wipe.textContent = '';
      wipe.appendChild(h('div', { class: 'wipe-folder' },
        h('span', { class: 'wipe-tab' }, 'Scene ' + (idx + 1) + ' of ' + run.c.scenes.length),
        h('h1', {}, sc.title),
        h('p', { class: 'wipe-skill' }, sc.skill || ''),
        sc.blurb ? h('p', { class: 'wipe-blurb' }, sc.blurb) : null,
        h('span', { class: 'wipe-tap' }, 'tap to open')));
      wipe.className = 'in'; wipe.hidden = false;
      CF.Sound.play('wipe');
      return wait(340).then(function () {
        self.setStage(); self.setProp(null);
        self.setPlace(sc.place, sc.surface);
        $('app').classList.add('place-full');
        return new Promise(function (resolve) {
          var t = setTimeout(go, 1800);
          function go() { clearTimeout(t); wipe.onclick = null; resolve(); }
          wipe.onclick = go;
        });
      }).then(function () {
        wipe.className = 'out'; CF.Sound.play('open');
        return wait(330);
      }).then(function () { wipe.hidden = true; wipe.className = ''; });
    },

    /** The case clock: the only pressure in the game. */
    lose: function (mins) {
      if (!mins) return;
      var c = run.c, before = this.now;
      run.s.lost += mins; save(); updateBar();
      var clock = $('clock'); clock.classList.remove('hit'); void clock.offsetWidth; clock.classList.add('hit');
      toast('+' + mins + ' min on the case clock', 'bad');
      CF.fx.feedback('wrong'); CF.Sound.play('clock');
      run.moods.sam = 'annoyed';
      var dead = toMin(c.clock.deadline);
      if (before <= dead && this.now > dead) toast('Past ' + c.clock.deadlineName + ' time. Keep going!', 'bad');
    },

    /** Records a first-try result for the band estimate. First write wins. */
    mark: function (skill, id, ok, weight) {
      var m = run.s.marks[skill] || (run.s.marks[skill] = {});
      if (m[id]) return;
      m[id] = { ok: !!ok, w: weight || 1 }; save();
    },
    word: function (entry) {
      if (!entry) return;
      if (addWord(entry, run.c.title)) {
        queueToast('note', entry.t === 'grammar' ? entry.b : entry.a);
        $('btn-notebook').classList.add('ping');
      }
    },
    fact: function (f) {
      if (run.s.facts.some(function (x) { return x.title === f.title; })) return;
      run.s.facts.push(f); save();
      $('btn-notebook').classList.add('ping');
    },
    evidence: function (id) {
      if (run.s.evidence.indexOf(id) >= 0) return;
      run.s.evidence.push(id); save();
      var e = run.c.evidence.filter(function (x) { return x.id === id; })[0];
      if (e) queueToast('ev', e.title);
    },
    flag: function (k, v) { if (arguments.length > 1) { run.s.flags[k] = v; save(); } return run.s.flags[k]; },

    /** Scenes hand the engine a function that gives a hint for the current step. */
    setHint: function (fn, whyNot) { run.hint = fn || null; run.hintWhy = whyNot || ''; },

    /** A rubber stamp. Red stamps are the big moments: slam, thud, shake, ink flecks. */
    stamp: function (text, tone) {
      var layer = $('stamp-layer'), big = !tone || tone === 'red';
      var el = h('div', { class: 'stamp big ' + (tone || 'red') + (big ? ' heavy' : '') }, h('span', {}, text));
      layer.appendChild(el);
      run.moods.sam = 'pleased';
      setTimeout(function () { CF.fx.feedback(big ? 'large' : 'medium'); CF.fx.splat(el); }, big ? 210 : 150);
      return wait(1300).then(function () { el.classList.add('out'); return wait(300); }).then(function () { el.remove(); });
    },

    /**
     * Plays a list of story beats: dialogue lines, documents to read,
     * notebook facts, evidence cards and clock losses.
     */
    play: async function (beats, vars) {
      beats = beats || [];
      var talk = [];
      for (var i = 0; i < beats.length; i++) {
        var b = beats[i];
        if (typeof b === 'string' || (b && b.who)) { talk.push(b); continue; }
        if (talk.length) { await say(talk, vars); talk = []; }
        if (b.doc) {
          var render = CF.docs[b.doc.kind];
          this.setStage(render ? render(b.doc, this) : h('pre', {}, JSON.stringify(b.doc)));
          await this.proceed(b.button);
        } else if (b.fact) this.fact(b.fact);
        else if (b.evidence) this.evidence(b.evidence);
        else if (b.word) this.word(b.word);
        else if (b.lose) this.lose(b.lose);
      }
      if (talk.length) await say(talk, vars);
    }
  };

  async function askHint() {
    if (!run) return;
    var c = run.c, s = run.s;
    if (!run.hint) { toast(run.hintWhy || 'Nothing to ask Sam about right now.'); return; }
    if (s.hintsLeft <= 0) { await say(['No hints left. All I’ve got now is biscuits, and you can’t have those.']); return; }
    var ok = await new Promise(function (resolve) {
      var close = openSheet([
        h('h2', {}, 'Ask Sam?'),
        h('p', {}, 'Sam will show you where to look, not what the answer is. It costs ' + c.hintCost + ' minutes on the case clock.'),
        h('p', { class: 'muted' }, s.hintsLeft + ' of ' + c.hints + ' hints left.'),
        h('div', { class: 'row' },
          h('button', { class: 'btn ghost', onclick: function () { close(); resolve(false); } }, 'Not yet'),
          h('button', { class: 'btn primary', onclick: function () { close(); resolve(true); } }, 'Ask Sam'))
      ], 'confirm');
      $('sheet').onclick = function () { close(); resolve(false); };
    });
    if (!ok) return;
    var fn = run.hint;
    var used = await fn();
    if (used === false) return; // nothing useful to say here: no charge
    s.hintsLeft--; ctx.lose(c.hintCost); updateBar(); save();
  }

  /* ───────────── runner ───────────── */

  async function runCase(c, state) {
    run = { c: c, s: state, hint: null, moods: {} };
    document.body.classList.add('in-case');
    updateBar();
    while (state.scene < c.scenes.length) {
      var sc = c.scenes[state.scene];
      var fn = CF.scenes[sc.type];
      updateBar();
      if (!fn) throw new Error('Unknown scene type: ' + sc.type);
      await fn(sc, ctx);
      state.scene++; save();
    }
  }
  CF.restart = function () { if (run) store.del(saveKey(run.c.id)); Speech.stop(); location.reload(); };

  /* ───────────── home screen ───────────── */

  function home() {
    run = null; updateBar();
    document.body.classList.remove('in-case');
    $('app').classList.remove('place-full');
    function toggle(label, get, set) {
      var b = h('button', { class: 'btn ghost small' });
      function draw() { b.textContent = label + ': ' + (get() ? 'on' : 'off'); }
      b.onclick = function () { set(!get()); draw(); CF.Sound.unlock(); CF.Sound.play('good'); };
      draw(); return b;
    }
    var stage = ctx.setStage(
      h('div', { class: 'home' },
        h('div', { class: 'home-head' },
          h('span', { class: 'home-unit' }, 'Unit 9 · Language Crimes'),
          h('h1', {}, 'Case', h('br'), 'Files'),
          h('p', {}, 'Detective work where the evidence is English. Every answer you give does a job in the case.')),
        CF.order.map(function (id) {
          var c = CF.cases[id], saved = store.get(saveKey(id), null);
          var resume = saved && saved.scene > 0 && saved.scene < c.scenes.length;
          return h('article', { class: 'folder' },
            h('span', { class: 'folder-tab' }, 'Case ' + c.number),
            h('h2', {}, c.title),
            h('p', {}, c.tagline),
            h('p', { class: 'folder-meta' }, 'About ' + c.minutes + ' minutes · ' + c.skills.join(' · ')),
            h('button', { class: 'btn primary', onclick: function () { start(c, resume ? saved : newState(c)); } }, resume ? 'Continue the case' : 'Open the case'),
            resume ? h('button', { class: 'btn ghost small', onclick: function () { store.del(saveKey(id)); start(c, newState(c)); } }, 'Start again from the beginning') : null);
        }),
        h('div', { class: 'home-tools' },
          h('button', { class: 'btn ghost', onclick: soundCheck }, 'Sound check'),
          h('button', { class: 'btn ghost', onclick: function () { openNotebook('words'); } }, 'My word bank')),
        h('div', { class: 'home-tools' },
          toggle('Sound effects', function () { return CF.Sound.on; }, function (v) { CF.Sound.setOn(v); }),
          toggle('Screen shake', function () { return CF.fx.shakeOn; }, function (v) { CF.fx.setShake(v); })),
        h('p', { class: 'home-note' }, 'Calls and radio messages are spoken aloud. Turn your sound on, or use headphones.')));
    ctx.setTray();
    return stage;
  }

  async function soundCheck() {
    var c = CF.cases[CF.order[0]];
    toast('Playing a test message…');
    var ok = await Speech.play([c.soundCheck || 'This is a sound check.'], { prefer: 'female' });
    toast(ok ? 'If you heard a voice, you’re ready.' : 'No voice found on this device. Calls will be shown as text instead.', ok ? '' : 'bad');
  }

  function start(c, state) {
    runCase(c, state).catch(function (err) {
      console.error(err);
      toast('Something went wrong. Your progress is saved; reload to continue.', 'bad');
    });
  }

  CF.boot = function () {
    Speech.init();
    document.addEventListener('pointerdown', function (e) {
      CF.Sound.unlock();
      if (e.target.closest && e.target.closest('button, [role=button]')) CF.Sound.play('tick');
    }, true);
    $('btn-hint').onclick = askHint;
    $('btn-notebook').onclick = function () { CF.Sound.play('open'); openNotebook(); };
    $('clock').onclick = function () {
      if (!run) return;
      toast('The clock only moves when you make a mistake or take a hint. ' + run.s.lost + ' min lost so far.');
    };
    home();
  };
})();
